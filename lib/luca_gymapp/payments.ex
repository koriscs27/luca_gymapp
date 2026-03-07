defmodule LucaGymapp.Payments do
  @moduledoc false

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Payments.Barion
  alias LucaGymapp.Payments.Payment
  alias LucaGymapp.Payments.SzamlazzClient
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses
  import Ecto.Query, warn: false
  require Logger

  def payment_needed? do
    Application.get_env(:luca_gymapp, :payment_needed, true)
  end

  def start_season_pass_payment(%User{} = user, pass_name, redirect_url, callback_url) do
    if payment_needed?() do
      do_start_barion_payment(user, pass_name, redirect_url, callback_url)
    else
      {:ok, :skipped}
    end
  end

  def grant_cash_season_pass(%User{} = user, pass_name) do
    with {:ok, type_def} <- SeasonPasses.validate_purchase(user, pass_name),
         {:ok, payment} <- create_payment(user, type_def, "cash") do
      payment =
        payment
        |> Payment.changeset(%{
          payment_id: "cash-" <> Ecto.UUID.generate(),
          provider_response: %{"status" => "Succeeded", "source" => "cash"},
          status: "paid",
          barion_status: "Succeeded"
        })
        |> Repo.update!()

      maybe_finalize_payment(payment)
    end
  end

  def list_recent_user_payments(user_id, limit \\ 20) when is_integer(user_id) do
    Payment
    |> where([payment], payment.user_id == ^user_id)
    |> order_by([payment], desc: payment.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def handle_return(payment_id) when is_binary(payment_id) do
    with {:ok, payment} <- sync_payment_status(payment_id) do
      {:ok, payment.status}
    end
  end

  def handle_callback(payment_id) when is_binary(payment_id) do
    _ = sync_payment_status(payment_id)
    :ok
  end

  def sync_payment_status_for_user(user_id, payment_id)
      when is_integer(user_id) and is_binary(payment_id) do
    case Repo.get_by(Payment, payment_id: payment_id, user_id: user_id) do
      %Payment{payment_method: "barion"} -> sync_payment_status(payment_id)
      %Payment{} -> {:error, :refresh_not_supported}
      nil -> {:error, :payment_not_found}
    end
  end

  def resend_invoice_for_user(user_id, payment_id)
      when is_integer(user_id) and is_binary(payment_id) do
    case Repo.get_by(Payment, payment_id: payment_id, user_id: user_id) do
      nil ->
        {:error, :payment_not_found}

      %Payment{status: status} when status != "paid" ->
        {:error, :invoice_not_ready}

      %Payment{invoice_status: "ok"} ->
        {:error, :invoice_already_sent}

      %Payment{invoice_status: status} when status not in ["error", "no_response"] ->
        {:error, :invoice_resend_not_allowed}

      %Payment{} = payment ->
        maybe_dispatch_invoice_send(payment, :manual_retry)
    end
  end

  def sync_payment_status(payment_id) when is_binary(payment_id) do
    with %Payment{} = payment <- Repo.get_by(Payment, payment_id: payment_id),
         {:ok, barion_state} <- Barion.payment_state(payment_id) do
      barion_status = Map.get(barion_state, "Status")

      payment =
        payment
        |> Payment.changeset(%{
          barion_status: barion_status,
          provider_response: barion_state,
          status: payment_status_from_barion(barion_status)
        })
        |> Repo.update!()

      maybe_finalize_payment(payment)
    else
      nil -> {:error, :payment_not_found}
      {:error, _} = error -> error
    end
  end

  defp do_start_barion_payment(%User{} = user, pass_name, redirect_url, callback_url) do
    with {:ok, type_def} <- SeasonPasses.validate_purchase(user, pass_name),
         :ok <- validate_barion_config(),
         {:ok, payment} <- create_payment(user, type_def, "barion") do
      case Barion.start_payment(%{
             pos_key: barion_pos_key(),
             payee_email: barion_payee_email(),
             payment_request_id: payment.payment_request_id,
             pass_name: type_def.name,
             amount_huf: type_def.price_huf,
             payer_email: user.email,
             redirect_url: redirect_url,
             callback_url: callback_url
           }) do
        {:ok, barion} ->
          payment
          |> Payment.changeset(%{
            payment_id: barion.payment_id,
            gateway_url: barion.gateway_url,
            provider_response: barion.raw,
            status: "started",
            barion_status: Map.get(barion.raw, "Status")
          })
          |> Repo.update()

        {:error, reason} ->
          _ =
            payment
            |> Payment.changeset(%{
              status: "failed",
              provider_response: %{error: inspect(reason)}
            })
            |> Repo.update()

          {:error, reason}
      end
    end
  end

  defp create_payment(%User{} = user, type_def, payment_method) do
    %Payment{}
    |> Payment.changeset(%{
      user_id: user.id,
      payment_method: payment_method,
      pass_name: type_def.type,
      amount_huf: type_def.price_huf,
      currency: "HUF",
      payment_request_id: Ecto.UUID.generate(),
      status: "pending"
    })
    |> Repo.insert()
  end

  defp maybe_finalize_payment(%Payment{status: "paid"} = payment) do
    if is_nil(payment.season_pass_id) do
      user = Accounts.get_user!(payment.user_id)

      case SeasonPasses.purchase_season_pass(
             user,
             payment.pass_name,
             payment_id: payment.payment_id,
             payment_method: payment.payment_method
           ) do
        {:ok, pass} ->
          payment
          |> Payment.changeset(%{
            season_pass_id: pass.id,
            paid_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.update()
          |> case do
            {:ok, finalized_payment} ->
              case maybe_dispatch_invoice_send(finalized_payment, :post_grant) do
                {:ok, %Payment{} = invoice_updated_payment} ->
                  {:ok, invoice_updated_payment}

                _ ->
                  {:ok, finalized_payment}
              end

            {:error, _changeset} ->
              {:ok, payment}
          end

        {:error, _reason} ->
          {:ok, payment}
      end
    else
      {:ok, payment}
    end
  end

  defp maybe_finalize_payment(payment), do: {:ok, payment}

  defp maybe_dispatch_invoice_send(%Payment{} = payment, trigger) do
    if billing_async?() do
      case Task.Supervisor.start_child(LucaGymapp.InvoiceTaskSupervisor, fn ->
             _ = send_invoice_best_effort(payment, trigger)
             :ok
           end) do
        {:ok, _pid} -> {:ok, :queued}
        {:error, reason} -> {:error, {:invoice_task_start_failed, reason}}
      end
    else
      send_invoice_best_effort(payment, trigger)
    end
  end

  defp send_invoice_best_effort(%Payment{invoice_status: "ok"} = payment, _trigger),
    do: {:ok, payment}

  defp send_invoice_best_effort(%Payment{} = payment, _trigger) do
    if billing_enabled?() do
      with {:ok, user} <- fetch_user_for_billing(payment.user_id),
           :ok <- validate_billing_prerequisites(user),
           :ok <- validate_szamlazz_config(),
           {:ok, response} <- perform_invoice_send(payment, user) do
        updated =
          payment
          |> Payment.changeset(%{
            invoice_status: "ok",
            invoice_number: Map.get(response, :invoice_number),
            invoice_sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
            invoice_last_attempt_at: DateTime.utc_now() |> DateTime.truncate(:second),
            invoice_error: nil,
            invoice_response: stringify_map(response)
          })
          |> Repo.update!()

        {:ok, updated}
      else
        {:error, :missing_billing_profile} ->
          {:ok, mark_invoice_error(payment, :error, "missing_billing_profile")}

        {:error, :missing_szamlazz_agent_key} ->
          {:ok, mark_invoice_error(payment, :error, "missing_szamlazz_agent_key")}

        {:error, {:no_response, reason}} ->
          {:ok, mark_invoice_error(payment, :no_response, inspect(reason))}

        {:error, reason} ->
          {:ok, mark_invoice_error(payment, :error, inspect(reason))}
      end
    else
      {:ok, payment}
    end
  end

  defp perform_invoice_send(%Payment{} = payment, %User{} = user) do
    client = billing_client()

    if function_exported?(client, :send_invoice, 3) do
      item_name =
        case function_exported?(client, :invoice_item_name, 1) do
          true -> client.invoice_item_name(payment)
          false -> SzamlazzClient.invoice_item_name(payment)
        end

      client.send_invoice(payment, user, item_name: item_name)
    else
      {:error, :invalid_billing_client}
    end
  end

  defp fetch_user_for_billing(user_id) do
    case Accounts.get_user(user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  defp validate_billing_prerequisites(%User{} = user) do
    if Accounts.billing_profile_complete_for_pass_purchase?(user) do
      :ok
    else
      {:error, :missing_billing_profile}
    end
  end

  defp validate_szamlazz_config do
    if is_binary(szamlazz_agent_key()) and String.trim(szamlazz_agent_key()) != "" do
      :ok
    else
      {:error, :missing_szamlazz_agent_key}
    end
  end

  defp mark_invoice_error(%Payment{} = payment, status, reason) do
    invoice_status =
      case status do
        :no_response -> "no_response"
        _ -> "error"
      end

    payment
    |> Payment.changeset(%{
      invoice_status: invoice_status,
      invoice_last_attempt_at: DateTime.utc_now() |> DateTime.truncate(:second),
      invoice_error: truncate_error(reason),
      invoice_response: nil
    })
    |> Repo.update!()
  end

  defp truncate_error(reason) do
    reason
    |> to_string()
    |> String.slice(0, 1000)
  end

  defp stringify_map(map) when is_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_map(_), do: %{}

  defp payment_status_from_barion("Succeeded"), do: "paid"
  defp payment_status_from_barion("PartiallySucceeded"), do: "paid"
  defp payment_status_from_barion("Authorized"), do: "authorized"
  defp payment_status_from_barion("Canceled"), do: "failed"
  defp payment_status_from_barion("Failed"), do: "failed"
  defp payment_status_from_barion("Expired"), do: "failed"
  defp payment_status_from_barion(_), do: "pending"

  defp validate_barion_config do
    if is_nil(barion_payee_email()) or barion_payee_email() == "" do
      {:error, :missing_barion_payee_email}
    else
      :ok
    end
  end

  defp barion_pos_key do
    Application.get_env(:luca_gymapp, :barion, [])
    |> Keyword.fetch!(:pos_key)
  end

  defp barion_payee_email do
    Application.get_env(:luca_gymapp, :barion, [])
    |> Keyword.get(:payee_email)
  end

  defp billing_client do
    Application.get_env(:luca_gymapp, :billing_client, SzamlazzClient)
  end

  defp billing_enabled? do
    Application.get_env(:luca_gymapp, :billing_enabled, false)
  end

  defp billing_async? do
    Application.get_env(:luca_gymapp, :billing_async, true)
  end

  defp szamlazz_agent_key do
    Application.get_env(:luca_gymapp, :szamlazz, [])
    |> Keyword.get(:agent_key)
  end
end

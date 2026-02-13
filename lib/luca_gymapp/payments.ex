defmodule LucaGymapp.Payments do
  @moduledoc false

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Payments.Barion
  alias LucaGymapp.Payments.Payment
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses
  import Ecto.Query, warn: false

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

        {:error, _reason} ->
          {:ok, payment}
      end
    else
      {:ok, payment}
    end
  end

  defp maybe_finalize_payment(payment), do: {:ok, payment}

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
end

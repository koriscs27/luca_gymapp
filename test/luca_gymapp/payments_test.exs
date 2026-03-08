defmodule LucaGymapp.PaymentsTest do
  use LucaGymapp.DataCase, async: false

  alias LucaGymapp.Accounts
  alias LucaGymapp.Payments
  alias LucaGymapp.Payments.Payment
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  defmodule FakeBillingClient do
    @behaviour LucaGymapp.Payments.BillingClient

    @impl true
    def send_invoice(payment, _user, _opts) do
      if pid = Application.get_env(:luca_gymapp, :billing_test_notify_pid) do
        send(pid, {:fake_invoice_sent, payment.payment_id})
      end

      Application.get_env(
        :luca_gymapp,
        :billing_client_result,
        {:ok, %{invoice_number: "TESZT-1"}}
      )
    end

    def invoice_item_name(_payment), do: "Szemelyi edzes berlet - 1 alkalom"
  end

  test "cash grant creates paid payment and links pass metadata" do
    user = create_user()

    assert {:ok, %Payment{} = payment} =
             Payments.grant_cash_season_pass(user, "10_alkalmas_berlet")

    assert payment.payment_method == "cash"
    assert payment.status == "paid"
    assert is_binary(payment.payment_id)
    assert payment.season_pass_id

    pass = Repo.get!(SeasonPass, payment.season_pass_id)
    assert pass.payment_method == "cash"
    assert pass.payment_id == payment.payment_id
  end

  test "status refresh is disabled for non-barion payment methods" do
    user = create_user()

    assert {:ok, %Payment{} = payment} =
             Payments.grant_cash_season_pass(user, "10_alkalmas_berlet")

    assert {:error, :refresh_not_supported} =
             Payments.sync_payment_status_for_user(user.id, payment.payment_id)
  end

  test "cash grant sends invoice best effort and marks invoice ok on success" do
    with_billing_enabled(fn ->
      Application.put_env(
        :luca_gymapp,
        :billing_client_result,
        {:ok, %{invoice_number: "INV-2026-1"}}
      )

      user = create_billing_ready_user()

      assert {:ok, %Payment{} = payment} =
               Payments.grant_cash_season_pass(user, "10_alkalmas_berlet")

      payment_id = payment.payment_id
      assert_receive {:fake_invoice_sent, ^payment_id}
      payment = wait_for_invoice_update(payment.payment_id, ["ok"])
      assert payment.season_pass_id
      assert payment.invoice_status == "ok"
      assert payment.invoice_number == "INV-2026-1"
      assert %DateTime{} = payment.invoice_sent_at
    end)
  end

  test "cash grant keeps pass but marks no_response when billing has no answer" do
    with_billing_enabled(fn ->
      Application.put_env(
        :luca_gymapp,
        :billing_client_result,
        {:error, {:no_response, :timeout}}
      )

      user = create_billing_ready_user()

      assert {:ok, %Payment{} = payment} =
               Payments.grant_cash_season_pass(user, "10_alkalmas_berlet")

      payment_id = payment.payment_id
      assert_receive {:fake_invoice_sent, ^payment_id}
      payment = wait_for_invoice_update(payment.payment_id, ["no_response"])
      assert payment.season_pass_id
      assert payment.invoice_status == "no_response"
      assert is_binary(payment.invoice_error)
    end)
  end

  test "invoice resend is blocked when invoice was already sent successfully" do
    user = create_billing_ready_user()

    payment =
      create_payment(user.id, %{
        payment_id: "paid-ok-" <> Ecto.UUID.generate(),
        invoice_status: "ok",
        invoice_number: "INV-OK-1"
      })

    assert {:error, :invoice_already_sent} =
             Payments.resend_invoice_for_user(user.id, payment.payment_id)
  end

  test "invoice resend allowed for error and becomes ok with successful retry" do
    with_billing_enabled(fn ->
      Application.put_env(
        :luca_gymapp,
        :billing_client_result,
        {:ok, %{invoice_number: "INV-RETRY-1"}}
      )

      user = create_billing_ready_user()

      payment =
        create_payment(user.id, %{
          payment_id: "paid-error-" <> Ecto.UUID.generate(),
          invoice_status: "error",
          invoice_error: "previous error"
        })

      assert {:ok, :queued} =
               Payments.resend_invoice_for_user(user.id, payment.payment_id)

      payment_id = payment.payment_id
      assert_receive {:fake_invoice_sent, ^payment_id}
      retried = wait_for_invoice_update(payment.payment_id, ["ok"])
      assert retried.invoice_status == "ok"
      assert retried.invoice_number == "INV-RETRY-1"
    end)
  end

  test "invoice resend allowed for not_sent and becomes ok with successful retry" do
    with_billing_enabled(fn ->
      Application.put_env(
        :luca_gymapp,
        :billing_client_result,
        {:ok, %{invoice_number: "INV-RETRY-2"}}
      )

      user = create_billing_ready_user()

      payment =
        create_payment(user.id, %{
          payment_id: "paid-not-sent-" <> Ecto.UUID.generate(),
          invoice_status: "not_sent"
        })

      assert {:ok, :queued} =
               Payments.resend_invoice_for_user(user.id, payment.payment_id)

      payment_id = payment.payment_id
      assert_receive {:fake_invoice_sent, ^payment_id}
      retried = wait_for_invoice_update(payment.payment_id, ["ok"])
      assert retried.invoice_status == "ok"
      assert retried.invoice_number == "INV-RETRY-2"
    end)
  end

  defp create_user do
    email = "test-user-#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.create_user(%{email: email, name: "Payment Test User"})
    user
  end

  defp create_billing_ready_user do
    email = "billing-user-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Accounts.create_user(%{
        email: email,
        name: "Billing Test User",
        billing_country: "HU",
        billing_zip: "1111",
        billing_city: "Budapest",
        billing_address: "Fo utca 1."
      })

    user
  end

  defp create_payment(user_id, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Payment{}
    |> Payment.changeset(
      Map.merge(
        %{
          user_id: user_id,
          payment_method: "cash",
          pass_name: "10_alkalmas_berlet",
          amount_huf: 10_000,
          currency: "HUF",
          payment_request_id: Ecto.UUID.generate(),
          payment_id: "cash-" <> Ecto.UUID.generate(),
          status: "paid",
          barion_status: "Succeeded",
          paid_at: now,
          provider_response: %{"source" => "test"},
          invoice_status: "not_sent"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp with_billing_enabled(fun) do
    previous_enabled = Application.get_env(:luca_gymapp, :billing_enabled)
    previous_client = Application.get_env(:luca_gymapp, :billing_client)
    previous_szamlazz = Application.get_env(:luca_gymapp, :szamlazz)
    previous_result = Application.get_env(:luca_gymapp, :billing_client_result)
    previous_notify_pid = Application.get_env(:luca_gymapp, :billing_test_notify_pid)

    on_exit(fn ->
      Application.put_env(:luca_gymapp, :billing_enabled, previous_enabled)
      Application.put_env(:luca_gymapp, :billing_client, previous_client)
      Application.put_env(:luca_gymapp, :szamlazz, previous_szamlazz)
      Application.put_env(:luca_gymapp, :billing_client_result, previous_result)
      Application.put_env(:luca_gymapp, :billing_test_notify_pid, previous_notify_pid)
    end)

    Application.put_env(:luca_gymapp, :billing_enabled, true)
    Application.put_env(:luca_gymapp, :billing_client, FakeBillingClient)
    Application.put_env(:luca_gymapp, :szamlazz, agent_key: "agent-test-key")
    Application.put_env(:luca_gymapp, :billing_client_result, {:ok, %{invoice_number: "TESZT-1"}})
    Application.put_env(:luca_gymapp, :billing_test_notify_pid, self())
    fun.()
  end

  defp wait_for_invoice_update(payment_id, expected_statuses, attempts \\ 30)

  defp wait_for_invoice_update(_payment_id, _expected_statuses, 0) do
    flunk("timed out waiting for async invoice update")
  end

  defp wait_for_invoice_update(payment_id, expected_statuses, attempts) do
    payment = Repo.get_by!(Payment, payment_id: payment_id)

    if payment.invoice_status in expected_statuses do
      payment
    else
      receive do
      after
        20 -> wait_for_invoice_update(payment_id, expected_statuses, attempts - 1)
      end
    end
  end
end

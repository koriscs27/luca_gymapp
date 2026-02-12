defmodule LucaGymapp.PaymentsTest do
  use LucaGymapp.DataCase, async: false

  import Ecto.Query

  alias LucaGymapp.Accounts
  alias LucaGymapp.Payments
  alias LucaGymapp.Payments.Payment
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "dummy payment succeeds and finalizes purchase" do
    user = create_user()

    assert {:ok, %Payment{} = payment} =
             Payments.start_dummy_season_pass_payment(user, "10_alkalmas_berlet")

    assert payment.payment_method == "dummy"
    assert payment.status == "paid"
    assert is_binary(payment.payment_id)
    assert payment.season_pass_id

    pass = Repo.get!(SeasonPass, payment.season_pass_id)
    assert pass.payment_method == "dummy"
    assert pass.payment_id == payment.payment_id
  end

  test "dummy payment applies the same prechecks as barion path" do
    user = create_user()

    assert {:ok, %Payment{}} =
             Payments.start_dummy_season_pass_payment(user, "10_alkalmas_berlet")

    assert {:error, :active_pass_exists} =
             Payments.start_dummy_season_pass_payment(user, "10_alkalmas_berlet")
  end

  test "dummy payment is blocked when feature flag is disabled" do
    user = create_user()
    previous = Application.get_env(:luca_gymapp, :dummy_payment_enabled)
    Application.put_env(:luca_gymapp, :dummy_payment_enabled, false)

    on_exit(fn ->
      Application.put_env(:luca_gymapp, :dummy_payment_enabled, previous)
    end)

    assert {:error, :dummy_payment_not_available} =
             Payments.start_dummy_season_pass_payment(user, "10_alkalmas_berlet")

    refute Repo.exists?(from payment in Payment, where: payment.user_id == ^user.id)
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

  defp create_user do
    email = "test-user-#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.create_user(%{email: email, name: "Payment Test User"})
    user
  end
end

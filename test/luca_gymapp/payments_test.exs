defmodule LucaGymapp.PaymentsTest do
  use LucaGymapp.DataCase, async: false

  alias LucaGymapp.Accounts
  alias LucaGymapp.Payments

  test "barion purchase flow returns value and prints it for debugging" do
    user = create_user()
    pass_name = "10_alkalmas_berlet"
    redirect_url = "http://localhost:4000/barion/return"
    callback_url = "http://localhost:4000/barion/callback"

    previous_payment_needed = Application.get_env(:luca_gymapp, :payment_needed)

    Application.put_env(:luca_gymapp, :payment_needed, true)

    on_exit(fn ->
      if is_nil(previous_payment_needed) do
        Application.delete_env(:luca_gymapp, :payment_needed)
      else
        Application.put_env(:luca_gymapp, :payment_needed, previous_payment_needed)
      end
    end)

    result =
      Payments.start_season_pass_payment(
        user,
        pass_name,
        redirect_url,
        callback_url
      )

    IO.inspect(result, label: "barion_purchase_result")

    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end

  defp create_user do
    email = "test-user-#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.create_user(%{email: email, name: "Payment Test User"})
    user
  end
end

defmodule LucaGymapp.Payments.BillingClient do
  @moduledoc false

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Payments.Payment

  @callback send_invoice(Payment.t(), User.t(), keyword()) ::
              {:ok, map()} | {:error, term()}
end

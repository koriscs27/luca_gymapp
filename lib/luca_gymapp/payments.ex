defmodule LucaGymapp.Payments do
  @moduledoc false

  def payment_needed? do
    Application.get_env(:luca_gymapp, :payment_needed, true)
  end

  def ensure_payment(_attrs) do
    if payment_needed?() do
      {:error, :payment_required}
    else
      {:ok, :dummy}
    end
  end
end

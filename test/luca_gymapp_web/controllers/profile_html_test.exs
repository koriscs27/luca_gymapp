defmodule LucaGymappWeb.ProfileHTMLTest do
  use ExUnit.Case, async: true

  alias LucaGymappWeb.ProfileHTML

  test "invoice resend button is available for paid not_sent invoices" do
    payment = %{
      status: "paid",
      payment_id: "p-1",
      invoice_status: "not_sent"
    }

    assert ProfileHTML.invoice_resendable?(payment)
  end

  test "invoice resend button is available for paid nil invoice status" do
    payment = %{
      status: "paid",
      payment_id: "p-2",
      invoice_status: nil
    }

    assert ProfileHTML.invoice_resendable?(payment)
  end
end

defmodule LucaGymappWeb.EmailConfirmationRequestController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => ""}, as: :confirmation)
    render(conn, :new, form: form)
  end

  def create(conn, %{"confirmation" => %{"email" => email}}) do
    Accounts.deliver_confirmation_instructions_for_email(email)

    conn
    |> put_flash(:info, "Ha létezik fiók, új megerősítő e-mailt küldtünk erre a címre: #{email}")
    |> redirect(to: ~p"/confirm-email/new")
  end

  def create(conn, _params) do
    conn
    |> put_flash(:info, "Ha létezik fiók, új megerősítő e-mailt küldtünk.")
    |> redirect(to: ~p"/confirm-email/new")
  end
end

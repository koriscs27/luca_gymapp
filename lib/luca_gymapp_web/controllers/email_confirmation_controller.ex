defmodule LucaGymappWeb.EmailConfirmationController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts

  def show(conn, %{"token" => token}) do
    case Accounts.confirm_user_email(token) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Sikeresen megerősítetted az e-mail címedet.")
        |> redirect(to: ~p"/")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "A megerősítő link lejárt. Kérjük, regisztrálj újra.")
        |> redirect(to: ~p"/register")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Érvénytelen megerősítő link.")
        |> redirect(to: ~p"/register")
    end
  end
end

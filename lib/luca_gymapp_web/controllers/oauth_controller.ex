defmodule LucaGymappWeb.OAuthController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts

  plug Ueberauth

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.get_or_create_user_from_oauth(auth) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Sikeres bejelentkezĂ©s Google-fiĂłkkal.")
        |> redirect(to: ~p"/")

      {:error, :missing_email} ->
        conn
        |> put_flash(:error, "A Google-fiĂłk nem adott vissza e-mail cĂ­met.")
        |> redirect(to: "/#login-modal")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "A Google bejelentkezĂ©s sikertelen.")
        |> redirect(to: "/#login-modal")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "A Google bejelentkezĂ©s sikertelen.")
    |> redirect(to: "/#login-modal")
  end
end

defmodule LucaGymappWeb.OAuthController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  require Logger

  plug Ueberauth

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.get_or_create_user_from_oauth(auth) do
      {:ok, user} ->
        Logger.info("oauth_login_success provider=google user_id=#{user.id}")

        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Sikeres bejelentkezés Google-fiókkal.")
        |> redirect(to: ~p"/")

      {:error, :missing_email} ->
        Logger.warning("oauth_login_error_missing_email provider=google")

        conn
        |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
        |> redirect(to: "/#login-modal")

      {:error, _reason} ->
        Logger.warning("oauth_login_error provider=google")

        conn
        |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
        |> redirect(to: "/#login-modal")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    Logger.warning("oauth_login_failure provider=google")

    conn
    |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
    |> redirect(to: "/#login-modal")
  end
end

defmodule LucaGymappWeb.SessionController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  require Logger

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    if blank?(email) or blank?(password) do
      Logger.warning("login_error_missing_params")

      conn
      |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
      |> redirect(to: "/#login-modal")
    else
      case Accounts.authenticate_user(email, password) do
        {:ok, user} ->
          Logger.info("login_success email=#{user.email} name=#{user.name}")

          conn
          |> configure_session(renew: true)
          |> put_session(:user_id, user.id)
          |> put_flash(:info, "Sikeres bejelentkezés.")
          |> redirect(to: ~p"/")

        {:error, :unconfirmed} ->
          Logger.warning("login_error_unconfirmed email=#{email}")

          conn
          |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
          |> redirect(to: "/#login-modal")

        :error ->
          Logger.warning("login_error_invalid email=#{email}")

          conn
          |> put_flash(:error, "Hibás e-mail vagy jelszó.")
          |> redirect(to: "/#login-modal")
      end
    end
  end

  def create(conn, _params) do
    Logger.warning("login_error_missing_params")

    conn
    |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
    |> redirect(to: "/#login-modal")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Sikeres kijelentkezés.")
    |> redirect(to: ~p"/")
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true
end

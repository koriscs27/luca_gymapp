defmodule LucaGymappWeb.SessionController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  alias LucaGymapp.Security.RateLimiter
  require Logger

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case RateLimiter.allow_request(conn, :login, email: email) do
      :ok ->
        if blank?(email) or blank?(password) do
          Logger.warning("login_error_missing_params")

          conn
          |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
          |> redirect(to: "/#login-modal")
        else
          case Accounts.authenticate_user(email, password) do
            {:ok, user} ->
              Logger.info("login_success user_id=#{user.id}")

              conn
              |> configure_session(renew: true)
              |> put_session(:user_id, user.id)
              |> put_flash(:info, "Sikeres bejelentkezés.")
              |> redirect(to: ~p"/")

            {:error, :unconfirmed} ->
              Logger.warning("login_error_unconfirmed")

              conn
              |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
              |> redirect(to: "/#login-modal")

            :error ->
              Logger.warning("login_error_invalid")

              conn
              |> put_flash(:error, "Hibás e-mail vagy jelszó.")
              |> put_flash(:login_error, "Hibás e-mail vagy jelszó.")
              |> redirect(to: "/#login-modal")
          end
        end

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, RateLimiter.rate_limited_message())
        |> redirect(to: "/#login-modal")
    end
  end

  def create(conn, _params) do
    case RateLimiter.allow_request(conn, :login) do
      :ok ->
        Logger.warning("login_error_missing_params")

        conn
        |> put_flash(:error, "A bejelentkezés nem sikerült. Próbáld újra.")
        |> redirect(to: "/#login-modal")

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, RateLimiter.rate_limited_message())
        |> redirect(to: "/#login-modal")
    end
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

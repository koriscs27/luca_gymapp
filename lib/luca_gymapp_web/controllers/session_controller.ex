defmodule LucaGymappWeb.SessionController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Sikeres bejelentkezés.")
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> put_flash(:error, "Hibás e-mail vagy jelszó.")
        |> redirect(to: "/#login-modal")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Hibás e-mail vagy jelszó.")
    |> redirect(to: "/#login-modal")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Sikeres kijelentkezés.")
    |> redirect(to: ~p"/")
  end
end

defmodule LucaGymappWeb.SessionControllerTest do
  use LucaGymappWeb.ConnCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Repo

  setup do
    password = "titkos-jelszo-123"

    user =
      %User{email: "teszt@example.com", password_hash: Accounts.hash_password(password)}
      |> Repo.insert!()

    {:ok, user: user, password: password}
  end

  test "logs in with valid credentials", %{conn: conn, user: user, password: password} do
    conn = post(conn, ~p"/login", user: %{email: user.email, password: password})

    assert get_session(conn, :user_id) == user.id
    assert redirected_to(conn) == ~p"/"
  end

  test "rejects invalid credentials", %{conn: conn, user: user} do
    conn = post(conn, ~p"/login", user: %{email: user.email, password: "rossz-jelszo"})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Hibás e-mail vagy jelszó."
    assert redirected_to(conn) == "/#login-modal"
  end
end

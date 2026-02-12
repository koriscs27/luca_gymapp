defmodule LucaGymappWeb.SessionControllerTest do
  use LucaGymappWeb.ConnCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Repo

  setup do
    password = "titkos-jelszo-123"

    user =
      %User{
        email: "teszt@example.com",
        password_hash: Accounts.hash_password(password),
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
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
    assert Phoenix.Flash.get(conn.assigns.flash, :login_error) == "Hibás e-mail vagy jelszó."
    assert redirected_to(conn) == "/#login-modal"
  end

  test "shows dedicated login error message in modal after invalid credentials", %{
    conn: conn,
    user: user
  } do
    conn = post(conn, ~p"/login", user: %{email: user.email, password: "rossz-jelszo"})
    assert redirected_to(conn) == "/#login-modal"

    conn = conn |> recycle() |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ "login-error-message"
    assert html =~ "Hibás e-mail vagy jelszó."
  end

  test "rejects password login for google-only user without password", %{conn: conn} do
    user =
      %User{
        email: "google-only@example.com",
        password_hash: nil,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    conn = post(conn, ~p"/login", user: %{email: user.email, password: "barmi-jelszo"})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Hibás e-mail vagy jelszó."
    assert redirected_to(conn) == "/#login-modal"
  end

  test "rejects login when backend receives missing password", %{conn: conn, user: user} do
    conn = post(conn, ~p"/login", user: %{email: user.email})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A bejelentkezés nem sikerült. Próbáld újra."

    assert redirected_to(conn) == "/#login-modal"
  end

  test "rejects login when backend receives blank password", %{conn: conn, user: user} do
    conn = post(conn, ~p"/login", user: %{email: user.email, password: "   "})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A bejelentkezés nem sikerült. Próbáld újra."

    assert redirected_to(conn) == "/#login-modal"
  end
end

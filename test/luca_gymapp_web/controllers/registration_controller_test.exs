defmodule LucaGymappWeb.RegistrationControllerTest do
  use LucaGymappWeb.ConnCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Repo

  test "registers user with required fields", %{conn: conn} do
    params = %{
      email: "uj@example.com",
      password: "titkos-jelszo-123",
      name: "Teszt Elek",
      age: "28",
      phone_number: "+3612345678"
    }

    conn = post(conn, ~p"/register", user: params)

    assert redirected_to(conn) == ~p"/"

    user = Repo.get_by(User, email: "uj@example.com")
    assert user != nil
    assert user.password_hash == Accounts.hash_password("titkos-jelszo-123")
  end

  test "rejects registration without password", %{conn: conn} do
    conn = post(conn, ~p"/register", user: %{email: "nincs@jelszo.hu"})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A regisztráció sikertelen. Ellenőrizd az adatokat."

    assert html_response(conn, 200) =~ "Regisztráció"
  end
end

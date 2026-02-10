defmodule LucaGymappWeb.RegistrationControllerTest do
  use LucaGymappWeb.ConnCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Repo

  test "registers user with required fields", %{conn: conn} do
    params = %{
      email: "uj@example.com",
      password: "titkos-jelszo-123",
      password_confirmation: "titkos-jelszo-123",
      name: "Teszt Elek",
      age: "28",
      phone_number: "+3612345678"
    }

    conn = post(conn, ~p"/register", user: params)

    assert redirected_to(conn) == "/#registration-success"

    user = Repo.get_by(User, email: "uj@example.com")
    assert user != nil
    assert user.password_hash == Accounts.hash_password("titkos-jelszo-123")
  end

  test "shows error when email is already registered", %{conn: conn} do
    {:ok, _user} =
      %User{
        email: "dup@example.com",
        password_hash: Accounts.hash_password("titkos-123"),
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert()

    conn =
      post(conn, ~p"/register",
        user: %{
          email: "dup@example.com",
          password: "masik-123",
          password_confirmation: "masik-123"
        }
      )

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Ez az e-mail cím már regisztrálva van."

    assert html_response(conn, 200) =~ "Regisztráció"
  end

  test "rejects registration without password", %{conn: conn} do
    conn = post(conn, ~p"/register", user: %{email: "nincs@jelszo.hu"})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A regisztráció sikertelen. Ellenőrizd az adatokat."

    assert html_response(conn, 200) =~ "Regisztráció"
  end

  test "shows helpful message when password confirmation mismatches", %{conn: conn} do
    params = %{
      email: "rossz@jelszo.hu",
      password: "titkos-123",
      password_confirmation: "nem-ugyanaz"
    }

    conn = post(conn, ~p"/register", user: params)

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A megadott jelszavak nem egyeznek."

    assert html_response(conn, 200) =~ "Regisztráció"
  end
end

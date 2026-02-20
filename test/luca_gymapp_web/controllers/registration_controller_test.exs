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

    conn = post(conn, ~p"/register", user: params, accept_adatkezelesi: "true")

    assert redirected_to(conn) == "/#registration-success"

    user = Repo.get_by(User, email: "uj@example.com")
    assert user != nil
    assert is_binary(user.password_hash)
    assert String.starts_with?(user.password_hash, "pbkdf2_sha256$")
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
        },
        accept_adatkezelesi: "true"
      )

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Ez az e-mail cím már regisztrálva van."

    assert html_response(conn, 200) =~ "Regisztráció"
  end

  test "rejects registration without password", %{conn: conn} do
    conn =
      post(conn, ~p"/register", user: %{email: "nincs@jelszo.hu"}, accept_adatkezelesi: "true")

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

    conn = post(conn, ~p"/register", user: params, accept_adatkezelesi: "true")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A megadott jelszavak nem egyeznek."

    assert html_response(conn, 200) =~ "Regisztráció"
  end

  test "shows activation email message after successful registration", %{conn: conn} do
    params = %{
      email: "aktivacio@example.com",
      password: "titkos-jelszo-123",
      password_confirmation: "titkos-jelszo-123"
    }

    conn = post(conn, ~p"/register", user: params, accept_adatkezelesi: "true")

    assert redirected_to(conn) == "/#registration-success"
    info_flash = Phoenix.Flash.get(conn.assigns.flash, :info)
    assert is_binary(info_flash)
    assert String.contains?(String.downcase(info_flash), "e-mail")
    assert String.contains?(String.downcase(info_flash), "meger")
  end

  test "rejects registration when captcha is missing", %{conn: conn} do
    previous_value = Application.get_env(:luca_gymapp, :turnstile_required, false)
    Application.put_env(:luca_gymapp, :turnstile_required, true)

    on_exit(fn ->
      Application.put_env(:luca_gymapp, :turnstile_required, previous_value)
    end)

    params = %{
      email: "captcha-hianyzik@example.com",
      password: "titkos-jelszo-123",
      password_confirmation: "titkos-jelszo-123"
    }

    conn = post(conn, ~p"/register", user: params, accept_adatkezelesi: "true")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Kérlek igazold, hogy nem vagy robot."
    assert html_response(conn, 200) =~ "Regisztráció"
  end

  test "register page shows adatkezelesi tajekoztato link", %{conn: conn} do
    conn = get(conn, ~p"/register")
    html = html_response(conn, 200)

    assert html =~ ~s(id="register-accept-adatkezelesi")
    assert html =~ ~s(id="register-adatkezelesi-link")
    assert html =~ ~s(href="/adatkezelesi-tajekoztato?return_to=%2Fregister")
  end

  test "rejects registration when adatkezelesi is not accepted", %{conn: conn} do
    params = %{
      email: "nincs-elfogadas@example.com",
      password: "titkos-jelszo-123",
      password_confirmation: "titkos-jelszo-123"
    }

    conn = post(conn, ~p"/register", user: params)

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A regisztrációhoz el kell fogadnod az Adatkezelési Tájékoztatót."

    assert html_response(conn, 200) =~ ~s(id="register-form")
  end
end

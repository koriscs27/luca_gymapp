defmodule LucaGymappWeb.ProfileControllerTest do
  use LucaGymappWeb.ConnCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Payments.Payment
  alias LucaGymapp.Repo

  setup %{conn: conn} do
    password = "titkos-jelszo-123"

    user =
      %User{
        email: "profil@example.com",
        password_hash: Accounts.hash_password(password),
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        name: nil,
        phone_number: nil,
        age: nil,
        sex: nil,
        birth_date: nil
      }
      |> Repo.insert!()

    conn = init_test_session(conn, %{user_id: user.id})

    {:ok, conn: conn, user: user, password_hash: user.password_hash}
  end

  test "allows profile fields nil->value and value->nil, but not email/password changes", %{
    conn: conn,
    user: user,
    password_hash: password_hash
  } do
    conn =
      patch(conn, ~p"/profile",
        user: %{
          name: "Teszt Elek",
          phone_number: "+3612345678",
          age: "30",
          sex: "male",
          birth_date: "1994-03-20",
          email: "attacker@example.com",
          password_hash: "new-hash"
        }
      )

    assert html_response(conn, 200)

    updated_user = Repo.get!(User, user.id)
    assert updated_user.name == "Teszt Elek"
    assert updated_user.phone_number == "+3612345678"
    assert updated_user.age == 30
    assert updated_user.sex == "male"
    assert updated_user.birth_date == ~D[1994-03-20]
    assert updated_user.email == "profil@example.com"
    assert updated_user.password_hash == password_hash

    conn =
      patch(conn, ~p"/profile",
        user: %{
          name: nil,
          phone_number: nil,
          age: nil,
          sex: nil,
          birth_date: nil,
          email: "other@example.com",
          password_hash: "another-hash"
        }
      )

    assert html_response(conn, 200)

    cleared_user = Repo.get!(User, user.id)
    assert is_nil(cleared_user.name)
    assert is_nil(cleared_user.phone_number)
    assert is_nil(cleared_user.age)
    assert is_nil(cleared_user.sex)
    assert is_nil(cleared_user.birth_date)
    assert cleared_user.email == "profil@example.com"
    assert cleared_user.password_hash == password_hash
  end

  test "profile shows only last 20 payments by datetime", %{conn: conn, user: user} do
    Enum.each(1..21, fn idx ->
      create_payment(user.id, %{
        payment_id: "barion-#{idx}",
        payment_method: "barion",
        pass_name: "pass_#{idx}"
      })
    end)

    conn = get(conn, ~p"/profile")
    html = html_response(conn, 200)

    [_before, payments_table_after] = String.split(html, ~s(id="payments-table"), parts: 2)
    payments_table = ~s(id="payments-table") <> payments_table_after
    [payments_table_only | _] = String.split(payments_table, "</table>", parts: 2)

    payment_rows_count =
      payments_table_only
      |> String.split("class=\"border-b border-neutral-200/70\"")
      |> length()
      |> Kernel.-(1)

    assert payment_rows_count == 20
  end

  test "refresh is disabled for non-barion payments", %{conn: conn, user: user} do
    _cash =
      create_payment(user.id, %{
        payment_id: "cash-1",
        payment_method: "cash"
      })

    conn = patch(conn, ~p"/profile/payments/cash-1/refresh")

    assert redirected_to(conn) == ~p"/profile"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Ehhez a fizetési módhoz nem elérhető frissítés."
  end

  test "profile shows links to ASZF and adatkezelesi tajekoztato", %{conn: conn} do
    conn = get(conn, ~p"/profile")
    html = html_response(conn, 200)

    assert html =~ ~s(id="profile-aszf-link")
    assert html =~ ~s(href="/aszf?return_to=%2Fprofile")
    assert html =~ ~s(id="profile-adatkezelesi-link")
    assert html =~ ~s(href="/adatkezelesi-tajekoztato?return_to=%2Fprofile")
  end

  defp create_payment(user_id, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Payment{}
    |> Payment.changeset(
      Map.merge(
        %{
          user_id: user_id,
          payment_method: "barion",
          pass_name: "10_alkalmas_berlet",
          amount_huf: 10_000,
          currency: "HUF",
          payment_request_id: Ecto.UUID.generate(),
          payment_id: "barion-" <> Ecto.UUID.generate(),
          status: "paid",
          barion_status: "Succeeded",
          paid_at: now,
          provider_response: %{"source" => "test"}
        },
        attrs
      )
    )
    |> Repo.insert!()
  end
end

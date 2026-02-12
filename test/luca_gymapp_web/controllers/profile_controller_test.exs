defmodule LucaGymappWeb.ProfileControllerTest do
  use LucaGymappWeb.ConnCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
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
end

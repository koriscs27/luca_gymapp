defmodule LucaGymapp.AccountsTest do
  use LucaGymapp.DataCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Bookings.CrossBooking
  alias LucaGymapp.Bookings.PersonalBooking
  alias LucaGymapp.Payments.Payment
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "anonymize_user/1 replaces personal data and keeps related records linked" do
    user =
      Repo.insert!(%User{
        email: "anonymize-me@example.com",
        password_hash: "hash",
        name: "Teszt Elek",
        phone_number: "+36123456789",
        age: 33,
        sex: "ferfi",
        birth_date: ~D[1991-01-01],
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    pass =
      Repo.insert!(%SeasonPass{
        user_id: user.id,
        pass_id: Ecto.UUID.generate(),
        pass_name: "10_alkalmas_berlet",
        pass_type: "personal",
        payment_method: "barion",
        occasions: 10,
        purchase_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        purchase_price: 45_000,
        expiry_date: Date.add(Date.utc_today(), 30)
      })

    payment =
      Repo.insert!(%Payment{
        user_id: user.id,
        season_pass_id: pass.id,
        payment_method: "barion",
        pass_name: pass.pass_name,
        amount_huf: pass.purchase_price,
        currency: "HUF",
        payment_request_id: Ecto.UUID.generate(),
        payment_id: "barion-" <> Ecto.UUID.generate(),
        status: "paid"
      })

    personal_booking =
      Repo.insert!(%PersonalBooking{
        user_id: user.id,
        pass_id: pass.pass_id,
        user_name: "Teszt Elek",
        start_time:
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(86_400, :second),
        end_time:
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(90_000, :second),
        booking_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        status: "booked"
      })

    cross_booking =
      Repo.insert!(%CrossBooking{
        user_id: user.id,
        pass_id: pass.pass_id,
        user_name: "Teszt Elek",
        start_time:
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(172_800, :second),
        end_time:
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(176_400, :second),
        booking_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        status: "booked"
      })

    assert {:ok, anonymized_user} = Accounts.anonymize_user(user.id)
    assert anonymized_user.id == user.id
    assert anonymized_user.email == "deleted-user-#{user.id}@anon.invalid"
    assert anonymized_user.name == "Torolt felhasznalo ##{user.id}"
    assert anonymized_user.phone_number == nil
    assert anonymized_user.age == nil
    assert anonymized_user.sex == nil
    assert anonymized_user.birth_date == nil
    assert anonymized_user.password_hash == nil
    assert anonymized_user.email_confirmed_at == nil
    assert anonymized_user.email_confirmation_token_hash == nil
    assert anonymized_user.password_reset_token_hash == nil
    assert anonymized_user.admin == false

    assert Repo.get!(Payment, payment.id).user_id == user.id
    assert Repo.get!(SeasonPass, pass.id).user_id == user.id
    assert Repo.get!(PersonalBooking, personal_booking.id).user_id == user.id
    assert Repo.get!(CrossBooking, cross_booking.id).user_id == user.id

    assert Repo.get!(PersonalBooking, personal_booking.id).user_name ==
             "Torolt felhasznalo ##{user.id}"

    assert Repo.get!(CrossBooking, cross_booking.id).user_name == "Torolt felhasznalo ##{user.id}"
  end

  test "anonymize_user/1 returns not_found for unknown user id" do
    assert {:error, :not_found} = Accounts.anonymize_user(999_999_999)
    assert {:error, :not_found} = Accounts.anonymize_user("not-a-number")
  end
end

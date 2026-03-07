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
        billing_country: "HU",
        billing_zip: "1111",
        billing_city: "Budapest",
        billing_address: "Fo utca 1.",
        billing_company_name: "Teszt Kft",
        billing_tax_number: "12345678-1-42",
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
    assert anonymized_user.billing_country == nil
    assert anonymized_user.billing_zip == nil
    assert anonymized_user.billing_city == nil
    assert anonymized_user.billing_address == nil
    assert anonymized_user.billing_company_name == nil
    assert anonymized_user.billing_tax_number == nil
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

  test "company name requires tax number on user changeset" do
    changeset =
      Accounts.change_user(%User{}, %{
        email: "company@example.com",
        billing_company_name: "Teszt Kft",
        billing_tax_number: nil
      })

    refute changeset.valid?
    assert "Adoszam kotelezo, ha cegnevet adsz meg." in errors_on(changeset).billing_tax_number
  end

  test "billing_profile_complete_for_pass_purchase?/1 validates required billing fields" do
    user = %User{email: "u@example.com", name: "Teszt", billing_country: "HU"}
    refute Accounts.billing_profile_complete_for_pass_purchase?(user)

    valid_user = %User{
      email: "u@example.com",
      name: "Teszt",
      billing_country: "HU",
      billing_zip: "1111",
      billing_city: "Budapest",
      billing_address: "Fo utca 1.",
      billing_company_name: nil,
      billing_tax_number: nil
    }

    assert Accounts.billing_profile_complete_for_pass_purchase?(valid_user)

    company_without_tax = %{
      valid_user
      | billing_company_name: "Teszt Kft",
        billing_tax_number: nil
    }

    refute Accounts.billing_profile_complete_for_pass_purchase?(company_without_tax)
  end
end

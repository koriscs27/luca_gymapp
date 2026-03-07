defmodule LucaGymapp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :phone_number, :string
    field :age, :integer
    field :sex, :string
    field :billing_country, :string
    field :billing_zip, :string
    field :billing_city, :string
    field :billing_address, :string
    field :billing_company_name, :string
    field :billing_tax_number, :string
    field :password_hash, :string
    field :birth_date, :date
    field :email_confirmed_at, :utc_datetime
    field :email_confirmation_token_hash, :binary
    field :email_confirmation_sent_at, :utc_datetime
    field :password_reset_token_hash, :binary
    field :password_reset_sent_at, :utc_datetime
    field :admin, :boolean, default: false

    has_many :season_passes, LucaGymapp.SeasonPasses.SeasonPass
    has_many :personal_bookings, LucaGymapp.Bookings.PersonalBooking
    has_many :cross_bookings, LucaGymapp.Bookings.CrossBooking

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :name,
      :email,
      :phone_number,
      :age,
      :sex,
      :birth_date,
      :billing_country,
      :billing_zip,
      :billing_city,
      :billing_address,
      :billing_company_name,
      :billing_tax_number
    ])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_company_tax_number()
    |> unique_constraint(:email)
  end

  def with_password_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password_hash])
  end

  defp validate_company_tax_number(changeset) do
    company_name = get_field(changeset, :billing_company_name) |> normalize_string()
    tax_number = get_field(changeset, :billing_tax_number) |> normalize_string()

    cond do
      company_name == nil ->
        changeset

      tax_number == nil ->
        add_error(
          changeset,
          :billing_tax_number,
          "Adoszam kotelezo, ha cegnevet adsz meg."
        )

      true ->
        changeset
    end
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(_), do: nil
end

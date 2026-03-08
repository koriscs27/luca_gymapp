defmodule LucaGymapp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @country_name_to_code %{
    "magyarorszag" => "HU",
    "magyarország" => "HU",
    "hungary" => "HU"
  }
  @legacy_hu_replacements %{
    "ß" => "á",
    "ẞ" => "Á"
  }

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
    |> normalize_billing_country()
    |> normalize_profile_text_fields()
    |> validate_hungary_zip()
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

  defp normalize_billing_country(changeset) do
    update_change(changeset, :billing_country, &normalize_country_code/1)
  end

  defp normalize_profile_text_fields(changeset) do
    country = get_field(changeset, :billing_country) |> normalize_string()

    fields = [:name, :billing_city, :billing_address, :billing_company_name]

    Enum.reduce(fields, changeset, fn field, acc ->
      update_change(acc, field, &normalize_profile_text(&1, country))
    end)
  end

  defp validate_hungary_zip(changeset) do
    country = get_field(changeset, :billing_country) |> normalize_string()
    zip = get_field(changeset, :billing_zip) |> normalize_string()

    if country == "HU" and zip != nil and not Regex.match?(~r/^\d{4}$/, zip) do
      add_error(changeset, :billing_zip, "Magyarorszag eseten az iranyitoszam 4 szamjegy.")
    else
      changeset
    end
  end

  defp normalize_country_code(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    cond do
      normalized == "" ->
        nil

      map_size(@country_name_to_code) > 0 and Map.has_key?(@country_name_to_code, normalized) ->
        Map.fetch!(@country_name_to_code, normalized)

      String.match?(normalized, ~r/^[a-z]{2}$/) ->
        String.upcase(normalized)

      true ->
        value |> String.trim()
    end
  end

  defp normalize_country_code(_), do: nil

  defp normalize_profile_text(value, country) when is_binary(value) do
    normalized = :unicode.characters_to_nfc_binary(value)

    if country == "HU" do
      Enum.reduce(@legacy_hu_replacements, normalized, fn {from, to}, acc ->
        String.replace(acc, from, to)
      end)
    else
      normalized
    end
  end

  defp normalize_profile_text(value, _country), do: value

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(_), do: nil
end

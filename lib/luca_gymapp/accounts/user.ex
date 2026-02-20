defmodule LucaGymapp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :phone_number, :string
    field :age, :integer
    field :sex, :string
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
    |> cast(attrs, [:name, :email, :phone_number, :age, :sex, :birth_date])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
  end

  def with_password_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password_hash])
  end
end

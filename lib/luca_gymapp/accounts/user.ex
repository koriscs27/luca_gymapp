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

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :phone_number, :age, :sex, :password_hash, :birth_date])
    |> validate_required([:email, :password_hash])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
  end
end

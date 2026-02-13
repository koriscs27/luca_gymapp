defmodule LucaGymapp.Bookings.PersonalBooking do
  use Ecto.Schema
  import Ecto.Changeset

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.SeasonPasses.SeasonPass

  schema "personal_bookings" do
    field :user_name, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :booking_timestamp, :utc_datetime
    field :status, :string

    belongs_to :user, User

    belongs_to :season_pass, SeasonPass,
      references: :pass_id,
      foreign_key: :pass_id,
      type: :string

    timestamps(type: :utc_datetime)
  end

  def changeset(personal_booking, attrs) do
    personal_booking
    |> cast(attrs, [
      :user_name,
      :start_time,
      :end_time,
      :booking_timestamp,
      :status,
      :pass_id
    ])
    |> validate_required([
      :user_name,
      :start_time,
      :end_time,
      :booking_timestamp,
      :status,
      :pass_id
    ])
    |> validate_inclusion(:status, ["booked", "cancelled"])
  end
end

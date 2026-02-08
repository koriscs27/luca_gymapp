defmodule LucaGymapp.Bookings.CalendarSlot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "calendar_slots" do
    field :slot_type, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime

    timestamps()
  end

  def changeset(calendar_slot, attrs) do
    calendar_slot
    |> cast(attrs, [:slot_type, :start_time, :end_time])
    |> validate_required([:slot_type, :start_time, :end_time])
    |> validate_inclusion(:slot_type, ["personal", "cross"])
    |> unique_constraint(:slot_type, name: :calendar_slots_unique_slot)
  end
end

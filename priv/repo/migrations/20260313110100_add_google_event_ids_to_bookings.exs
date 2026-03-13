defmodule LucaGymapp.Repo.Migrations.AddGoogleEventIdsToBookings do
  use Ecto.Migration

  def change do
    alter table(:personal_bookings) do
      add :google_event_id, :string
    end

    alter table(:cross_bookings) do
      add :google_event_id, :string
    end

    create index(:personal_bookings, [:google_event_id])
    create index(:cross_bookings, [:google_event_id])
  end
end

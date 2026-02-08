defmodule LucaGymapp.Repo.Migrations.CreateCrossBookings do
  use Ecto.Migration

  def change do
    create table(:cross_bookings) do
      add :user_name, :string, null: false
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime, null: false
      add :booking_timestamp, :utc_datetime, null: false
      add :status, :string, null: false, default: "booked"
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :pass_id, references(:season_passes, column: :pass_id, type: :string), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:cross_bookings, [:user_id])
    create index(:cross_bookings, [:pass_id])

    execute("""
    CREATE INDEX cross_bookings_time_range_idx
    ON cross_bookings
    USING gist (tsrange(start_time, end_time, '[)'))
    """)

    create constraint(:cross_bookings, :end_after_start, check: "end_time > start_time")

    create constraint(:cross_bookings, :valid_status, check: "status IN ('booked', 'cancelled')")
  end
end

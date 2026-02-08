defmodule LucaGymapp.Repo.Migrations.CreatePersonalBookings do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS btree_gist"

    create table(:personal_bookings) do
      add :user_name, :string, null: false
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime, null: false
      add :booking_timestamp, :utc_datetime, null: false
      add :status, :string, null: false, default: "booked"
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :pass_id, references(:season_passes, column: :pass_id, type: :string), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:personal_bookings, [:user_id])
    create index(:personal_bookings, [:pass_id])

    execute("""
    CREATE INDEX personal_bookings_time_range_idx
    ON personal_bookings
    USING gist (tsrange(start_time, end_time, '[)'))
    """)

    create constraint(:personal_bookings, :end_after_start, check: "end_time > start_time")

    create constraint(:personal_bookings, :valid_status,
             check: "status IN ('booked', 'cancelled')"
           )

    execute("""
    ALTER TABLE personal_bookings
    ADD CONSTRAINT personal_bookings_no_overlap
    EXCLUDE USING gist (
      user_id WITH =,
      tsrange(start_time, end_time, '[)') WITH &&
    )
    WHERE (status = 'booked')
    """)
  end
end

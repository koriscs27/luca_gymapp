defmodule LucaGymapp.Repo.Migrations.DropPersonalBookingOverlapConstraint do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE personal_bookings
    DROP CONSTRAINT IF EXISTS personal_bookings_no_overlap
    """)
  end

  def down do
    execute("""
    ALTER TABLE personal_bookings
    ADD CONSTRAINT personal_bookings_no_overlap
    EXCLUDE USING gist (
      tsrange(start_time, end_time, '[)') WITH &&
    )
    WHERE (status = 'booked')
    """)
  end
end

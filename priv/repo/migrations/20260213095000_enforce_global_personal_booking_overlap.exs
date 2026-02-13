defmodule LucaGymapp.Repo.Migrations.EnforceGlobalPersonalBookingOverlap do
  use Ecto.Migration

  def up do
    # Keep one booked row per exact personal slot, cancel duplicates to satisfy new global constraint.
    execute("""
    WITH ranked AS (
      SELECT id,
             row_number() OVER (
               PARTITION BY start_time, end_time
               ORDER BY booking_timestamp, id
             ) AS rn
      FROM personal_bookings
      WHERE status = 'booked'
    )
    UPDATE personal_bookings
    SET status = 'cancelled', updated_at = NOW()
    WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
    """)

    execute("""
    ALTER TABLE personal_bookings
    DROP CONSTRAINT IF EXISTS personal_bookings_no_overlap
    """)

    execute("""
    ALTER TABLE personal_bookings
    ADD CONSTRAINT personal_bookings_no_overlap
    EXCLUDE USING gist (
      tsrange(start_time, end_time, '[)') WITH &&
    )
    WHERE (status = 'booked')
    """)
  end

  def down do
    execute("""
    ALTER TABLE personal_bookings
    DROP CONSTRAINT IF EXISTS personal_bookings_no_overlap
    """)

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

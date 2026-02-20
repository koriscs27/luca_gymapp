defmodule LucaGymapp.Repo.Migrations.ClearExistingAppData do
  use Ecto.Migration

  def up do
    execute("""
    TRUNCATE TABLE
      payments,
      season_passes,
      personal_bookings,
      cross_bookings,
      calendar_slots,
      users
    RESTART IDENTITY CASCADE
    """)
  end

  def down do
    :ok
  end
end

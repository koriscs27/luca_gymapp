defmodule LucaGymapp.Repo.Migrations.CreateCalendarSlots do
  use Ecto.Migration

  def change do
    create table(:calendar_slots) do
      add :slot_type, :string, null: false
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:calendar_slots, [:slot_type, :start_time, :end_time],
             name: :calendar_slots_unique_slot
           )

    create index(:calendar_slots, [:slot_type, :start_time])
    create index(:calendar_slots, [:slot_type, :end_time])
  end
end

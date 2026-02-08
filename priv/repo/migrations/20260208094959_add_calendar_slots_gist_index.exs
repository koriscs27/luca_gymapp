defmodule LucaGymapp.Repo.Migrations.AddCalendarSlotsGistIndex do
  use Ecto.Migration

  def change do
    create index(:calendar_slots, ["tsrange(start_time, end_time, '[)')"],
             using: :gist,
             name: :calendar_slots_time_range_gist
           )
  end
end

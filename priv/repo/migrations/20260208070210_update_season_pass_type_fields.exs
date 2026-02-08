defmodule LucaGymapp.Repo.Migrations.UpdateSeasonPassTypeFields do
  use Ecto.Migration

  def change do
    rename table(:season_passes), :pass_type, to: :pass_name

    alter table(:season_passes) do
      add :pass_type, :string, null: false, default: "other"
    end

    execute("""
    UPDATE season_passes
    SET pass_type = CASE
      WHEN pass_name LIKE 'cross%' THEN 'cross'
      WHEN pass_name LIKE '%alkalmas%' THEN 'personal'
      ELSE 'other'
    END
    """)

    alter table(:season_passes) do
      modify :pass_type, :string, null: false, default: nil
    end
  end
end

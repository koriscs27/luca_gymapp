defmodule LucaGymapp.Repo.Migrations.CreateSeasonPasses do
  use Ecto.Migration

  def change do
    create table(:season_passes) do
      add :pass_id, :string, null: false
      add :pass_type, :string, null: false
      add :occasions, :integer, null: false
      add :purchase_timestamp, :utc_datetime, null: false
      add :purchase_price, :integer, null: false
      add :expiry_date, :date, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:season_passes, [:user_id])
    create unique_index(:season_passes, [:pass_id])
  end
end

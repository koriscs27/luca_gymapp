defmodule LucaGymapp.Repo.Migrations.CreateGoogleCalendarConnections do
  use Ecto.Migration

  def change do
    create table(:google_calendar_connections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :google_email, :string
      add :refresh_token_encrypted, :text
      add :calendar_id, :string
      add :oauth_mode, :string, null: false
      add :sync_enabled, :boolean, default: true, null: false
      add :last_sync_error, :text
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:google_calendar_connections, [:user_id])
    create index(:google_calendar_connections, [:sync_enabled])
    create index(:google_calendar_connections, [:oauth_mode])
  end
end

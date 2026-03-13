defmodule LucaGymapp.GoogleCalendar.Connection do
  use Ecto.Schema
  import Ecto.Changeset

  alias LucaGymapp.Accounts.User

  schema "google_calendar_connections" do
    field :google_email, :string
    field :refresh_token_encrypted, :string
    field :calendar_id, :string
    field :oauth_mode, :string
    field :sync_enabled, :boolean, default: true
    field :last_sync_error, :string
    field :last_synced_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :user_id,
      :google_email,
      :refresh_token_encrypted,
      :calendar_id,
      :oauth_mode,
      :sync_enabled,
      :last_sync_error,
      :last_synced_at
    ])
    |> validate_required([:user_id, :oauth_mode, :sync_enabled])
    |> validate_inclusion(:oauth_mode, ["test", "production"])
    |> unique_constraint(:user_id)
  end
end

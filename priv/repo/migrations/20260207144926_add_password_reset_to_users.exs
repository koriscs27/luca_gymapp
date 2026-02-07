defmodule LucaGymapp.Repo.Migrations.AddPasswordResetToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :password_reset_token_hash, :binary
      add :password_reset_sent_at, :utc_datetime
    end

    create index(:users, [:password_reset_token_hash])
  end
end

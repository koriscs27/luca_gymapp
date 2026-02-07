defmodule LucaGymapp.Repo.Migrations.AddEmailConfirmationToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :email_confirmed_at, :utc_datetime
      add :email_confirmation_token_hash, :binary
      add :email_confirmation_sent_at, :utc_datetime
    end

    create index(:users, [:email_confirmation_token_hash])
  end
end

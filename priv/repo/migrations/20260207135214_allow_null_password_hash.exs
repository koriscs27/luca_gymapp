defmodule LucaGymapp.Repo.Migrations.AllowNullPasswordHash do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :password_hash, :string, null: true
    end
  end
end

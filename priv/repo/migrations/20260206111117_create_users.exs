defmodule LucaGymapp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :email, :string, null: false
      add :phone_number, :string
      add :age, :integer
      add :sex, :string
      add :password_hash, :string, null: false
      add :birth_date, :date

      timestamps()
    end

    create unique_index(:users, [:email])
  end
end

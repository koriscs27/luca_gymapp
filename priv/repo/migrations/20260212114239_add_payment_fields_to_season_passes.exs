defmodule LucaGymapp.Repo.Migrations.AddPaymentFieldsToSeasonPasses do
  use Ecto.Migration

  def change do
    alter table(:season_passes) do
      add :payment_id, :string
      add :payment_method, :string, null: false, default: "cash"
    end

    create index(:season_passes, [:payment_id])

    execute(
      "UPDATE season_passes SET payment_method = 'cash' WHERE payment_method IS NULL",
      "UPDATE season_passes SET payment_method = NULL WHERE payment_method = 'cash'"
    )
  end
end

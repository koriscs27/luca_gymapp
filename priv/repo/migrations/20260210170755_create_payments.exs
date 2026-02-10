defmodule LucaGymapp.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :season_pass_id, references(:season_passes, on_delete: :nilify_all)
      add :payment_method, :string, null: false, default: "barion"
      add :pass_name, :string, null: false
      add :amount_huf, :integer, null: false
      add :currency, :string, null: false, default: "HUF"
      add :payment_request_id, :string, null: false
      add :payment_id, :string
      add :gateway_url, :string
      add :status, :string, null: false, default: "pending"
      add :barion_status, :string
      add :paid_at, :utc_datetime
      add :provider_response, :map

      timestamps(type: :utc_datetime)
    end

    create index(:payments, [:user_id])
    create index(:payments, [:season_pass_id])
    create unique_index(:payments, [:payment_request_id])
    create unique_index(:payments, [:payment_id])
  end
end

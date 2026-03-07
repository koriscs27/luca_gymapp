defmodule LucaGymapp.Repo.Migrations.AddBillingFieldsToUsersAndPayments do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :billing_country, :string
      add :billing_zip, :string
      add :billing_city, :string
      add :billing_address, :string
      add :billing_company_name, :string
      add :billing_tax_number, :string
    end

    alter table(:payments) do
      add :invoice_status, :string, null: false, default: "not_sent"
      add :invoice_number, :string
      add :invoice_sent_at, :utc_datetime
      add :invoice_last_attempt_at, :utc_datetime
      add :invoice_error, :string
      add :invoice_response, :map
    end

    create index(:payments, [:invoice_status])
  end
end

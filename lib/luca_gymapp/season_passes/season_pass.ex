defmodule LucaGymapp.SeasonPasses.SeasonPass do
  use Ecto.Schema
  import Ecto.Changeset

  alias LucaGymapp.Accounts.User

  schema "season_passes" do
    field :pass_id, :string
    field :pass_name, :string
    field :pass_type, :string
    field :payment_id, :string
    field :payment_method, :string, default: "cash"
    field :occasions, :integer
    field :purchase_timestamp, :utc_datetime
    field :purchase_price, :integer
    field :expiry_date, :date

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(season_pass, attrs) do
    season_pass
    |> change(attrs)
    |> validate_required([
      :pass_id,
      :pass_name,
      :pass_type,
      :payment_method,
      :occasions,
      :purchase_timestamp,
      :purchase_price,
      :expiry_date,
      :user_id
    ])
    |> validate_required([
      :payment_method
    ])
  end
end

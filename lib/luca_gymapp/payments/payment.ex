defmodule LucaGymapp.Payments.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.SeasonPasses.SeasonPass

  schema "payments" do
    field :payment_method, :string, default: "barion"
    field :pass_name, :string
    field :amount_huf, :integer
    field :currency, :string, default: "HUF"
    field :payment_request_id, :string
    field :payment_id, :string
    field :gateway_url, :string
    field :status, :string, default: "pending"
    field :barion_status, :string
    field :paid_at, :utc_datetime
    field :provider_response, :map

    belongs_to :user, User
    belongs_to :season_pass, SeasonPass

    timestamps(type: :utc_datetime)
  end

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :user_id,
      :season_pass_id,
      :payment_method,
      :pass_name,
      :amount_huf,
      :currency,
      :payment_request_id,
      :payment_id,
      :gateway_url,
      :status,
      :barion_status,
      :paid_at,
      :provider_response
    ])
    |> validate_required([
      :user_id,
      :payment_method,
      :pass_name,
      :amount_huf,
      :currency,
      :payment_request_id,
      :status
    ])
  end
end

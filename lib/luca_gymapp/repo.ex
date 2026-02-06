defmodule LucaGymapp.Repo do
  use Ecto.Repo,
    otp_app: :luca_gymapp,
    adapter: Ecto.Adapters.Postgres
end

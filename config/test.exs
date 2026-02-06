import Config

env_path =
  ["../.env.test", "../.env.dev"]
  |> Enum.map(&Path.expand(&1, __DIR__))
  |> Enum.find(&File.exists?/1)

if env_path do
  env_path
  |> File.stream!()
  |> Enum.each(fn line ->
    line = String.trim(line)

    if line != "" and not String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          value =
            value
            |> String.trim()
            |> String.trim("\"'")

          System.put_env(key, value)

        _ ->
          :ok
      end
    end
  end)
end

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :luca_gymapp, LucaGymapp.Repo,
  username: System.get_env("DB_USER") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  hostname: System.get_env("DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  database: "luca_gymapp_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :luca_gymapp, LucaGymappWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Wkfyhc8ha1TGmctp2bixnleI3dNRp8nu0kSgfX83ztF7gvZspnwvJFFUY5HrvbAb",
  server: false

# In test we don't send emails
config :luca_gymapp, LucaGymapp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

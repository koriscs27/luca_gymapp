# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :luca_gymapp,
  ecto_repos: [LucaGymapp.Repo],
  generators: [timestamp_type: :utc_datetime],
  coach_contact_email: "pankotailucafitness@gmail.com",
  coach_contact_phone: "+36705030443",
  payment_needed: true,
  personal_max_overlap: 1,
  cross_max_overlap: 8,
  season_pass_types: %{
    :"1_alkalmas_jegy" => %{price_huf: 6_000, occasions: 1},
    :"5_alkalmas_kezdo" => %{price_huf: 15_000, occasions: 5, once_per_user: true},
    :"5_alkalmas_berlet" => %{price_huf: 25_000, occasions: 5},
    :"10_alkalmas_berlet" => %{price_huf: 45_000, occasions: 10},
    cross_1_alkalmas_jegy: %{price_huf: 2_500, occasions: 1},
    cross_10_alkalmas_berlet: %{price_huf: 23_000, occasions: 10}
  },
  booking_schedule: %{
    personal: %{
      default_view: :week,
      availability: %{
        monday: [%{from: ~T[08:00:00], to: ~T[18:00:00]}],
        tuesday: [%{from: ~T[08:00:00], to: ~T[12:00:00]}],
        wednesday: [%{from: ~T[08:00:00], to: ~T[18:00:00]}],
        thursday: [%{from: ~T[08:00:00], to: ~T[12:00:00]}],
        friday: [%{from: ~T[11:00:00], to: ~T[14:00:00]}],
        saturday: [%{from: ~T[08:00:00], to: ~T[12:00:00]}]
      }
    },
    cross: %{
      default_view: :week,
      availability: %{
        monday: [%{from: ~T[17:00:00], to: ~T[18:00:00]}],
        wednesday: [%{from: ~T[17:00:00], to: ~T[18:00:00]}],
        saturday: [%{from: ~T[10:00:00], to: ~T[11:00:00]}]
      },
      max_overlap: 8
    }
  }

# Configure the endpoint
config :luca_gymapp, LucaGymappWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LucaGymappWeb.ErrorHTML, json: LucaGymappWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LucaGymapp.PubSub,
  live_view: [signing_salt: "JQ+d1NRd"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :luca_gymapp, LucaGymapp.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  luca_gymapp: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  luca_gymapp: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

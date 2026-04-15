# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :tpro_nvr, env: :dev

# Configure Mix tasks and generators
config :tpro_nvr,
  namespace: CVR,
  ecto_repos: [TProNVR.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tpro_nvr, TProNVR.Mailer, adapter: Swoosh.Adapters.Local

config :tpro_nvr,
  namespace: CVRWeb,
  ecto_repos: [TProNVR.Repo],
  generators: [context_app: :tpro_nvr],
  # CVEDIX-RT configuration for video analytics
  # Disabled to save RAM during development
  cvedix: [
    base_url: "http://127.0.0.1:3546",
    poll_interval: 1_000,
    enabled: true
  ]

# Configures the endpoint
config :tpro_nvr, TProNVRWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: TProNVRWeb.ErrorHTML, json: TProNVRWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TProNVR.PubSub,
  live_view: [signing_salt: "ASTBdstw"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:device_id, :user_id, :request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :os_mon,
  disk_space_check_interval: {:second, 30},
  disk_almost_full_threshold: 0.9

config :bundlex, :disable_precompiled_os_deps, apps: [:ex_libsrtp]

config :exqlite, force_build: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

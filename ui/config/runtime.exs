import Config

config :tpro_nvr,
  admin_username: System.get_env("CVR_ADMIN_USERNAME", "admin@localhost"),
  admin_password: System.get_env("CVR_ADMIN_PASSWORD", "P@ssw0rd"),
  download_dir: System.get_env("CVR_DOWNLOAD_DIR")

if config_env() == :prod do
  config :tpro_nvr, hls_directory: System.get_env("CVR_HLS_DIRECTORY", "/tmp/hls")

    database_path =
      System.get_env("DATABASE_PATH") ||
      Path.expand("../cvr.db", __DIR__)

  config :tpro_nvr, TProNVR.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  config :tpro_nvr, ice_servers: System.get_env("CVR_ICE_SERVERS", "[]")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    "4skDslGBPAnCMeX2KAXe7pzeIerNJhouqrpvqwTz17sRtPvlchHEonEYKhG+g69Q"

  url = URI.parse(System.get_env("CVR_URL", "http://localhost:4000"))

  check_origin =
    case System.get_env("CVR_CHECK_ORIGIN", "true") do
      "true" -> true
      "false" -> false
      origins -> String.split(origins, ",")
    end

  config :tpro_nvr, TProNVRWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("CVR_HTTP_PORT") || "4000")
    ],
    secret_key_base: secret_key_base,
    url: [scheme: url.scheme, host: url.host, port: url.port],
    check_origin: check_origin

  ## SSL Support
  enable_ssl = String.to_existing_atom(System.get_env("CVR_ENABLE_HTTPS", "false"))

  if enable_ssl do
    config :tpro_nvr, TProNVRWeb.Endpoint,
      https: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: String.to_integer(System.get_env("CVR_HTTPS_PORT") || "443"),
        cipher_suite: :compatible,
        keyfile: System.get_env("CVR_SSL_KEY_PATH"),
        certfile: System.get_env("CVR_SSL_CERT_PATH")
      ]
  end

  config :tpro_nvr, TProNVRWeb.Endpoint, server: true

  ## Logging configuration
  log_json? = System.get_env("CVR_JSON_LOGGER", "true") == "true"

  if log_json? do
    config :logger, :default_handler,
      level: :info,
      formatter: LoggerJSON.Formatters.Basic.new(metadata: [:device_id, :user_id, :request_id])
  end

  config :tpro_nvr,
    remote_server: [
      uri: System.get_env("CVR_REMOTE_SERVER_URI"),
      token: System.get_env("CVR_REMOTE_SERVER_TOKEN")
    ]

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :tpro_nvr, TProNVR.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

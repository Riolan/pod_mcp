# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :podcast_mcp, :scopes,
  user: [
    default: true,
    module: PodcastMcp.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: PodcastMcp.AccountsFixtures,
    test_login_helper: :register_and_log_in_user
  ]

config :podcast_mcp,
  ecto_repos: [PodcastMcp.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :podcast_mcp, PodcastMcpWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PodcastMcpWeb.ErrorHTML, json: PodcastMcpWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PodcastMcp.PubSub,
  live_view: [signing_salt: "ZtZQIsW3"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :podcast_mcp, PodcastMcp.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  podcast_mcp: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  podcast_mcp: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]



# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"


config :mime, :types, %{
  "audio/mp4" => ["m4a"],
  "audio/ogg" => ["ogg"],
  # Add other custom types here if needed, for example:
  # "audio/aac" => ["aac"] # If .aac also causes issues later
}


config :ex_aws,
  access_key_id: System.get_env("MINIO_ACCESS_KEY_ID") || "minioadmin",
  secret_access_key: System.get_env("MINIO_SECRET_ACCESS_KEY") || "minioadmin",
  region: System.get_env("MINIO_REGION") || "us-east-1" # MinIO isn't strict about regions

config :ex_aws, :s3,
  scheme: System.get_env("MINIO_SCHEME") || "http", # "http" for local, "https" for production with TLS
  host: System.get_env("MINIO_HOST") || "localhost",
  port: String.to_integer(System.get_env("MINIO_PORT") || "9000"),
  path_style: true # Usually required for MinIO unless you've configured virtual host bucket addressing

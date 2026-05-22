import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :archive_classifier, ArchiveClassifier.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "archive_classifier_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :archive_classifier, ArchiveClassifierWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "T2Oxic5kIXQpW8nSy6CTpbqrn1Z1qJ1bIkApxeFH7Vtx+5+DML4NnUvUO91jLTKY",
  server: false

# Whisper ML serving — disabled by default in test to avoid loading large models
config :archive_classifier, start_whisper: false
config :archive_classifier, whisper_model: "openai/whisper-tiny"

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

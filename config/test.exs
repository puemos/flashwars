import Config
config :flashwars, Oban, testing: :manual
config :flashwars, token_signing_secret: "jaR+3ysX5eSvRyY+2jBuAIRd4/0eTRhi"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :flashwars, Flashwars.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "flashwars_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :flashwars, FlashwarsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Cw8rhET1MXmVf7V7394IkN25xpVlZd+avrxR88DT2PRuGOfrh9C2/SMnD6L7Oj54",
  server: false

# In test we don't send emails
config :flashwars, Flashwars.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

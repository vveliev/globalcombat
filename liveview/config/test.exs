import Config

# GIF-68: the scheduler polls GlobalCombat.Repo on its own timer, outside any test's Ecto
# Sandbox ownership — left running it would race sandboxed test transactions. Tests that exercise
# GlobalCombat.Games.TurnScheduler start their own instance directly instead.
config :global_combat, :start_turn_scheduler, false

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :global_combat, GlobalCombat.Repo,
  username: System.get_env("MYSQL_USER", "root"),
  password: System.get_env("MYSQL_PASSWORD", ""),
  hostname: System.get_env("MYSQL_HOST", "localhost"),
  port: String.to_integer(System.get_env("MYSQL_PORT", "11434")),
  database: "global_combat_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :global_combat, GlobalCombatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 11402],
  secret_key_base: "WBeKtzj/YRAZhQfxCDqEjTReuLuXL55b591jOOvLxwpw3FCL4nMc3GScy8yRlP2Z",
  server: false

# In test we don't send emails
config :global_combat, GlobalCombat.Mailer, adapter: Swoosh.Adapters.Test

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

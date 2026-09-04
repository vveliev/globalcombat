import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/global_combat start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :global_combat, GlobalCombatWeb.Endpoint, server: true
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :global_combat, GlobalCombatWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/global_combat_web/router\.ex$",
        ~r"lib/global_combat_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :global_combat, GlobalCombat.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :global_combat, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :global_combat, GlobalCombatWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :global_combat, GlobalCombatWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :global_combat, GlobalCombatWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Mailer (docs/launch.md §2.3)
  #
  # Password reset and account notifications (`GlobalCombat.Accounts.Notifier`) go out through
  # Mailgun when its credentials are present. `MAILGUN_API_KEY` and `MAILGUN_DOMAIN` come from
  # 1Password via the fleet's compose env, like `DATABASE_URL`/`SECRET_KEY_BASE` above.
  # `MAILER_FROM` is the bare sender address (defaults to no-reply@ the Mailgun domain).
  #
  # Without a key the app still boots, but with the in-memory Local adapter, so mail is
  # silently dropped in production — hence the loud warning rather than a hard failure: a
  # first deploy shouldn't be blocked on mail, but nobody should discover this from a player
  # who never got their reset link. `config :swoosh, api_client: Swoosh.ApiClient.Req` is
  # already set in config/prod.exs.
  case System.get_env("MAILGUN_API_KEY") do
    nil ->
      IO.warn(
        "MAILGUN_API_KEY is not set: GlobalCombat.Mailer is using Swoosh.Adapters.Local, so " <>
          "password-reset and notification email will NOT be delivered (docs/launch.md §2.3)."
      )

    api_key ->
      domain =
        System.get_env("MAILGUN_DOMAIN") ||
          raise "MAILGUN_DOMAIN is required when MAILGUN_API_KEY is set (docs/launch.md §2.3)"

      config :global_combat, GlobalCombat.Mailer,
        adapter: Swoosh.Adapters.Mailgun,
        api_key: api_key,
        domain: domain

      config :global_combat,
             :mailer_from,
             {"Global Combat", System.get_env("MAILER_FROM", "no-reply@#{domain}")}
  end
end

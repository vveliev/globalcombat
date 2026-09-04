defmodule GlobalCombat.MailerConfig do
  @moduledoc """
  Decides the production `GlobalCombat.Mailer` configuration from the environment
  (docs/launch.md §2.3). Pulled out of `config/runtime.exs` so the decision is a plain function
  with tests, rather than logic that only ever runs at release boot.

  Mailgun when `MAILGUN_API_KEY` is set (`MAILGUN_DOMAIN` is then required); otherwise the
  log-only `Swoosh.Adapters.Logger` with a boot-time warning. The log-only fallback is
  deliberate: `config/prod.exs` disables Swoosh's in-memory `Local` storage, so falling back to
  `Swoosh.Adapters.Local` there would crash every password-reset request rather than merely not
  send — the failure mode this module exists to avoid. A first deploy is not blocked on mail,
  but every delivery attempt is visible in the logs at `:warning`.
  """

  @legacy_sender {"Global Combat", "noreply@globalcombat.com"}

  @typedoc "Config to apply plus an optional boot warning."
  @type decision :: %{
          mailer: keyword(),
          from: {String.t(), String.t()},
          warning: String.t() | nil
        }

  @doc "The sender used when no `MAILER_FROM` applies — the address `AccountController.cs` used."
  def legacy_sender, do: @legacy_sender

  @doc """
  `env` is a map of environment variables (`System.get_env/0` in production; a literal in tests).
  Raises when `MAILGUN_API_KEY` is set without `MAILGUN_DOMAIN`, since a half-configured mailer
  would fail on every send with a less obvious error.
  """
  @spec from_env(%{optional(String.t()) => String.t()}) :: decision()
  def from_env(env) when is_map(env) do
    case Map.get(env, "MAILGUN_API_KEY") do
      nil ->
        %{
          mailer: [adapter: Swoosh.Adapters.Logger, level: :warning],
          from: @legacy_sender,
          warning:
            "MAILGUN_API_KEY is not set: GlobalCombat.Mailer is using Swoosh.Adapters.Logger, so " <>
              "password-reset and notification email will be logged but NOT delivered " <>
              "(docs/launch.md §2.3)."
        }

      api_key ->
        domain =
          Map.get(env, "MAILGUN_DOMAIN") ||
            raise ArgumentError,
                  "MAILGUN_DOMAIN is required when MAILGUN_API_KEY is set (docs/launch.md §2.3)"

        %{
          mailer: [adapter: Swoosh.Adapters.Mailgun, api_key: api_key, domain: domain],
          from: {"Global Combat", Map.get(env, "MAILER_FROM", "no-reply@#{domain}")},
          warning: nil
        }
    end
  end
end

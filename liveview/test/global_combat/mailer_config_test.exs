defmodule GlobalCombat.MailerConfigTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.MailerConfig

  describe "from_env/1 (docs/launch.md §2.3)" do
    test "with no MAILGUN_API_KEY it falls back to the log-only adapter and warns" do
      decision = MailerConfig.from_env(%{})

      assert decision.mailer[:adapter] == Swoosh.Adapters.Logger
      assert decision.from == MailerConfig.legacy_sender()
      assert decision.warning =~ "MAILGUN_API_KEY is not set"
      assert decision.warning =~ "NOT delivered"
    end

    test "with a key and domain it configures Mailgun and a no-reply sender on that domain" do
      decision =
        MailerConfig.from_env(%{"MAILGUN_API_KEY" => "key-123", "MAILGUN_DOMAIN" => "mg.example"})

      assert decision.mailer == [
               adapter: Swoosh.Adapters.Mailgun,
               api_key: "key-123",
               domain: "mg.example"
             ]

      assert decision.from == {"Global Combat", "no-reply@mg.example"}
      assert decision.warning == nil
    end

    test "MAILER_FROM overrides the sender address" do
      decision =
        MailerConfig.from_env(%{
          "MAILGUN_API_KEY" => "k",
          "MAILGUN_DOMAIN" => "mg.example",
          "MAILER_FROM" => "hello@globalcombat.example"
        })

      assert decision.from == {"Global Combat", "hello@globalcombat.example"}
    end

    test "a key without a domain is a configuration error, not a silent half-setup" do
      assert_raise ArgumentError, ~r/MAILGUN_DOMAIN is required/, fn ->
        MailerConfig.from_env(%{"MAILGUN_API_KEY" => "k"})
      end
    end

    test "the log-only fallback actually delivers without a storage process (unlike Local)" do
      # config/prod.exs sets `config :swoosh, local: false`; this is the case the fallback guards.
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.to("player@example.com")
        |> Swoosh.Email.from(MailerConfig.legacy_sender())
        |> Swoosh.Email.subject("Reset")
        |> Swoosh.Email.text_body("hi")

      assert {:ok, _} = Swoosh.Adapters.Logger.deliver(email, level: :debug)
    end
  end
end

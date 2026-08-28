defmodule GlobalCombatWeb.Components.Boutique.PullQuoteTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.PullQuote

  test "renders a blockquote with a figcaption attribution" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <PullQuote.pull_quote attribution="— Mochi, staff engineer (tabby)">
        “We went from chasing our own tails to shipping nightly.”
      </PullQuote.pull_quote>
      """)

    assert html =~ "<figure"
    assert html =~ "<blockquote"
    assert html =~ "chasing our own tails"
    assert html =~ "<figcaption"
    assert html =~ "Mochi"
  end

  test "hangs the punctuation via the theme's measured advances" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <PullQuote.pull_quote attribution="— A">“Q”</PullQuote.pull_quote>
      """)

    assert html =~ "--quote-hang"
    assert html =~ "--attribution-hang"
  end

  test "omits the figcaption without an attribution and uses no literal colors" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <PullQuote.pull_quote>“Q”</PullQuote.pull_quote>
      """)

    refute html =~ "<figcaption"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/pull_quote.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

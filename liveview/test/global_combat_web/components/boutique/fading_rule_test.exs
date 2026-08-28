defmodule GlobalCombatWeb.Components.Boutique.FadingRuleTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.FadingRule

  test "renders a separator on the divider token" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <FadingRule.fading_rule />
      """)

    assert html =~ "<hr"
    assert html =~ ~s(role="separator")
    assert html =~ "--color-divider"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/fading_rule.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

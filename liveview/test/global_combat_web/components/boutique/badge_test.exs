defmodule GlobalCombatWeb.Components.Boutique.BadgeTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Badge

  test "renders the neutral fill by default" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Badge.badge>New</Badge.badge>
      """)

    assert html =~ "New"
    assert html =~ "bg-surface-muted"
  end

  test "maps intent to status-hue fills" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Badge.badge intent="danger">Blocked</Badge.badge>
      """)

    assert html =~ "bg-danger/15"
    assert html =~ "text-danger"
  end

  test "dot variant renders a hidden colored dot instead of the fill, word stays" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Badge.badge intent="success" dot>Online</Badge.badge>
      """)

    assert html =~ ~s(aria-hidden="true")
    assert html =~ "bg-success"
    assert html =~ "Online"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/badge.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

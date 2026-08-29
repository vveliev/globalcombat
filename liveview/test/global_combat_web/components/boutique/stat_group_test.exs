defmodule GlobalCombatWeb.Components.Boutique.StatGroupTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.StatGroup

  test "renders a definition list with label/value pairs in valid order" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatGroup.stat_group aria-label="Pounce, by the numbers">
        <StatGroup.stat_group_stat value="9" label="Lives per incident" />
        <StatGroup.stat_group_stat value="42ms" label="Nap-to-alert latency" emphasis="primary" />
      </StatGroup.stat_group>
      """)

    assert html =~ "<dl"
    assert html =~ "9"
    assert html =~ "Lives per incident"
    # dt precedes dd in the DOM (visual order is flipped with CSS)
    dt_index = :binary.match(html, "<dt") |> elem(0)
    dd_index = :binary.match(html, "<dd") |> elem(0)
    assert dt_index < dd_index
  end

  test "inks emphasised figures with the primary token" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatGroup.stat_group>
        <StatGroup.stat_group_stat value="42ms" label="Nap-to-alert latency" emphasis="primary" />
        <StatGroup.stat_group_stat value="9" label="Lives per incident" />
      </StatGroup.stat_group>
      """)

    assert html =~ "text-primary"
    assert html =~ "text-text"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/stat_group.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

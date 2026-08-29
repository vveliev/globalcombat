defmodule GlobalCombatWeb.Components.Boutique.QuantityTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Quantity

  test "always renders the unit of measure" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Quantity.quantity value={48} unit="ea" />
      """)

    assert html =~ "48 ea"
  end

  test "states a stock breach in words, not only in colour" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Quantity.quantity value={3} unit="sheet" min={10} />
      """)

    assert html =~ "below min"
  end

  test "leaves a healthy quantity unmarked" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Quantity.quantity value={80} unit="kg" min={10} />
      """)

    refute html =~ "below min"
    refute html =~ "text-status-offline"
  end

  test "uses semantic tokens and tabular figures for a breach" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Quantity.quantity value={1} unit="kg" min={10} />
      """)

    assert html =~ "tabular-nums"
    assert html =~ "text-status-offline"
    refute html =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end

  test "respects an explicit precision" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Quantity.quantity value={3.5} unit="kg" precision={2} />
      """)

    assert html =~ "3.50 kg"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/quantity.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

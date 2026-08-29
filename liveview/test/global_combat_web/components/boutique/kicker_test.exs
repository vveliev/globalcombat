defmodule GlobalCombatWeb.Components.Boutique.KickerTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Kicker

  test "renders the label with a decorative dash hidden from AT" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Kicker.kicker>What Pounce does</Kicker.kicker>
      """)

    assert html =~ "What Pounce does"
    assert html =~ ~s(aria-hidden="true")
  end

  test "omits the dash when dash={false}" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Kicker.kicker dash={false}>Plain</Kicker.kicker>
      """)

    assert html =~ "Plain"
    refute html =~ ~s(aria-hidden="true")
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/kicker.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

defmodule GlobalCombatWeb.Components.Boutique.CardTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Card

  test "renders header/body/footer slots on token classes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Card.card>
        <:header>Title</:header>
        Body copy
        <:footer>Footer note</:footer>
      </Card.card>
      """)

    assert html =~ "Title"
    assert html =~ "Body copy"
    assert html =~ "Footer note"
    assert html =~ "bg-surface"
    assert html =~ "border-border"
    assert html =~ "shadow-md"
  end

  test "omits header/footer wrappers when their slots are unused" do
    assigns = %{}
    html = rendered_to_string(~H"<Card.card>Just body</Card.card>")

    assert html =~ "Just body"
    refute html =~ "border-t border-border"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/card.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

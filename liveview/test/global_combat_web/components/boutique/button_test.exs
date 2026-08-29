defmodule GlobalCombatWeb.Components.Boutique.ButtonTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Button

  test "renders an accessible button with the default primary intent" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Button.button>Save</Button.button>
      """)

    assert html =~ ~r/<button[^>]*type="button"/
    assert html =~ "Save"
    assert html =~ "bg-primary"
    assert html =~ "text-primary-contrast"
  end

  test "maps intent to distinct token-driven classes" do
    assigns = %{}

    neutral =
      rendered_to_string(~H"""
      <Button.button intent="neutral">Cancel</Button.button>
      """)

    danger =
      rendered_to_string(~H"""
      <Button.button intent="danger">Delete</Button.button>
      """)

    assert neutral =~ "bg-surface"
    assert neutral =~ "border-border"
    assert danger =~ "bg-red-600"
  end

  test "supports submit type and disabled state" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Button.button type="submit" disabled>Save</Button.button>
      """)

    assert html =~ ~s(type="submit")
    assert html =~ "disabled"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/button.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

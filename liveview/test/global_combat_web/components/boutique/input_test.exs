defmodule GlobalCombatWeb.Components.Boutique.InputTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Input

  test "renders a labelled text input on token classes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Input.input id="email" name="email" label="Email" />
      """)

    assert html =~ ~s(id="email")
    assert html =~ "Email"
    assert html =~ "border-border"
    assert html =~ "bg-surface"
  end

  test "surfaces field errors via the error class hook" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Input.input id="email" name="email" errors={["can't be blank"]} />
      """)

    assert html =~ "can&#39;t be blank"
    assert html =~ "border-danger"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/input.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

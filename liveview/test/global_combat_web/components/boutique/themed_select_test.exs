defmodule GlobalCombatWeb.Components.Boutique.ThemedSelectTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.ThemedSelect

  test "renders a labelled select with options on token classes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ThemedSelect.themed_select id="fruit" name="fruit" label="Fruit">
        <:option value="apple">Apple</:option>
        <:option value="banana">Banana</:option>
      </ThemedSelect.themed_select>
      """)

    assert html =~ ~s(id="fruit")
    assert html =~ "Fruit"
    assert html =~ ~s(value="apple")
    assert html =~ "Apple"
    assert html =~ ~s(value="banana")
    assert html =~ "Banana"
    assert html =~ "border-border"
    assert html =~ "bg-surface"
  end

  test "marks the option matching the current value as selected" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ThemedSelect.themed_select id="fruit" name="fruit" label="Fruit" value="banana">
        <:option value="apple">Apple</:option>
        <:option value="banana">Banana</:option>
      </ThemedSelect.themed_select>
      """)

    assert html =~ ~r/<option[^>]*value="banana"[^>]*selected/
    refute html =~ ~r/<option[^>]*value="apple"[^>]*selected/
  end

  test "renders a leading prompt option when given" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ThemedSelect.themed_select id="fruit" name="fruit" label="Fruit" prompt="Choose a fruit">
        <:option value="apple">Apple</:option>
      </ThemedSelect.themed_select>
      """)

    assert html =~ ~s(value="")
    assert html =~ "Choose a fruit"
  end

  test "disables an individual option" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ThemedSelect.themed_select id="fruit" name="fruit" label="Fruit">
        <:option value="apple" disabled>Apple</:option>
      </ThemedSelect.themed_select>
      """)

    assert html =~ ~r/<option[^>]*value="apple"[^>]*disabled/
  end

  test "surfaces field errors via token error classes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ThemedSelect.themed_select id="fruit" name="fruit" errors={["can't be blank"]}>
        <:option value="apple">Apple</:option>
      </ThemedSelect.themed_select>
      """)

    assert html =~ "can&#39;t be blank"
    assert html =~ "border-danger"
    assert html =~ "text-danger"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/themed_select.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

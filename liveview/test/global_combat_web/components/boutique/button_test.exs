defmodule GlobalCombatWeb.Components.Boutique.ButtonTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import GlobalCombatWeb.HTMLAssertions

  alias GlobalCombatWeb.Components.Boutique.Button

  test "renders an accessible button with the default primary intent" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Button.button>Save</Button.button>
      """)

    button = html |> LazyHTML.from_fragment() |> LazyHTML.query("button")

    assert button |> LazyHTML.filter(~s([type="button"])) |> Enum.any?()
    assert LazyHTML.text(button) =~ "Save"
    assert "bg-primary" in classes(button)
    assert "text-primary-contrast" in classes(button)
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

    neutral_classes = neutral |> LazyHTML.from_fragment() |> LazyHTML.query("button") |> classes()
    danger_classes = danger |> LazyHTML.from_fragment() |> LazyHTML.query("button") |> classes()

    assert "bg-surface" in neutral_classes
    assert "border-border" in neutral_classes
    assert "bg-red-600" in danger_classes
  end

  test "supports submit type and disabled state" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Button.button type="submit" disabled>Save</Button.button>
      """)

    button = html |> LazyHTML.from_fragment() |> LazyHTML.query("button")

    assert button |> LazyHTML.filter(~s([type="submit"])) |> Enum.any?()
    assert button |> LazyHTML.filter("[disabled]") |> Enum.any?()
  end

  test "renders as a link, not a button, when given navigate/href/patch" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Button.button intent="primary" navigate="/Create-Game">Play again</Button.button>
      """)

    parsed = LazyHTML.from_fragment(html)

    link = LazyHTML.filter(parsed, ~s(a[href="/Create-Game"]))

    assert Enum.any?(link)
    assert "bg-primary" in classes(link)
    assert parsed |> LazyHTML.filter("button") |> Enum.empty?()
  end

  test "raises when disabled is combined with a navigable attr" do
    assigns = %{}

    assert_raise ArgumentError, ~r/disabled.*cannot be combined/, fn ->
      rendered_to_string(~H"""
      <Button.button navigate="/Create-Game" disabled>Play again</Button.button>
      """)
    end
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/button.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

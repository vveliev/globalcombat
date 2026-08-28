defmodule GlobalCombatWeb.Components.Boutique.SegmentedControlTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.SegmentedControl

  test "renders both options as native radios sharing the group name" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <SegmentedControl.segmented_control name="quality" label="Stream quality" value="hd">
        <:option value="sd">SD</:option>
        <:option value="hd">HD</:option>
      </SegmentedControl.segmented_control>
      """)

    assert html =~ "SD"
    assert html =~ "HD"
    assert html =~ ~s(type="radio")
    assert html =~ ~s(name="quality")
    assert html =~ ~s(value="sd")
    assert html =~ ~s(value="hd")
  end

  test "the group exposes an accessible name via role=radiogroup + aria-label" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <SegmentedControl.segmented_control name="quality" label="Stream quality" value="hd">
        <:option value="sd">SD</:option>
        <:option value="hd">HD</:option>
      </SegmentedControl.segmented_control>
      """)

    assert html =~ ~s(role="radiogroup")
    assert html =~ ~s(aria-label="Stream quality")
  end

  test "the option matching value is checked, the other is not" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <SegmentedControl.segmented_control name="quality" label="Stream quality" value="hd">
        <:option value="sd">SD</:option>
        <:option value="hd">HD</:option>
      </SegmentedControl.segmented_control>
      """)

    [sd_input] = Regex.run(~r/<input[^>]*value="sd"[^>]*>/, html) |> List.wrap()
    [hd_input] = Regex.run(~r/<input[^>]*value="hd"[^>]*>/, html) |> List.wrap()

    refute sd_input =~ "checked"
    assert hd_input =~ "checked"
  end

  test "the hidden radio stays keyboard-focusable — sr-only, never hidden/display:none" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <SegmentedControl.segmented_control name="quality" label="Stream quality" value="hd">
        <:option value="sd">SD</:option>
        <:option value="hd">HD</:option>
      </SegmentedControl.segmented_control>
      """)

    [input_tag] = Regex.run(~r/<input[^>]*value="sd"[^>]*>/, html) |> List.wrap()

    assert input_tag =~ "sr-only"
    refute input_tag =~ "hidden"
    refute input_tag =~ "display:none"
    refute input_tag =~ "display: none"
  end

  test "the active segment's label carries the peer-checked lift-off treatment" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <SegmentedControl.segmented_control name="quality" label="Stream quality" value="hd">
        <:option value="sd">SD</:option>
        <:option value="hd">HD</:option>
      </SegmentedControl.segmented_control>
      """)

    assert html =~ "peer-checked:bg-surface"
    assert html =~ "peer-checked:shadow-sm"
    assert html =~ "peer-focus-visible:outline-focus-ring"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/segmented_control.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

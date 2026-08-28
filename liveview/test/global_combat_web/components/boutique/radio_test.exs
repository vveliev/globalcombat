defmodule GlobalCombatWeb.Components.Boutique.RadioTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Radio

  test "renders a native radio input with its label association" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Radio.radio id="freq-daily" name="frequency" value="daily" label="Daily" />
      """)

    assert html =~ ~s(type="radio")
    assert html =~ ~s(id="freq-daily")
    assert html =~ ~s(value="daily")
    assert html =~ "Daily"
    assert html =~ "accent-[var(--color-primary)]"
  end

  test "group renders a labelled fieldset wrapping its radios" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Radio.group label="Frequency">
        <Radio.radio id="freq-daily" name="frequency" value="daily" label="Daily" checked />
        <Radio.radio id="freq-weekly" name="frequency" value="weekly" label="Weekly" />
      </Radio.group>
      """)

    assert html =~ "<fieldset"
    assert html =~ "Frequency"
    assert html =~ "Daily"
    assert html =~ "Weekly"
    assert html =~ "checked"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/radio.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

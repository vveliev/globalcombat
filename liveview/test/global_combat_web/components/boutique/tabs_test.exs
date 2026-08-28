defmodule GlobalCombatWeb.Components.Boutique.TabsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Tabs

  test "exposes tablist/tab/tabpanel semantics, active tab is aria-selected" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Tabs.tab_list label="Settings sections">
        <Tabs.tab id="profile" active="profile" phx-click="switch_tab" phx-value-id="profile">
          Profile
        </Tabs.tab>
        <Tabs.tab id="appearance" active="profile" phx-click="switch_tab" phx-value-id="appearance">
          Appearance
        </Tabs.tab>
      </Tabs.tab_list>
      """)

    assert html =~ ~s(role="tablist")
    assert html =~ ~s(aria-label="Settings sections")
    assert html =~ ~s(role="tab")
    assert html =~ ~s(id="tab-profile")
    assert html =~ ~s(aria-selected="true")
    assert html =~ ~s(id="tab-appearance")
    assert html =~ ~s(aria-selected="false")
  end

  test "pills variant marks the active tab's fill, inactive tabs get muted text" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Tabs.tab id="profile" active="profile">Profile</Tabs.tab>
      <Tabs.tab id="appearance" active="profile">Appearance</Tabs.tab>
      """)

    assert html =~ "bg-primary"
    assert html =~ "text-primary-contrast"
    assert html =~ "text-text-muted"
  end

  test "keepMounted=false: only the active panel renders, inactive panel content is absent" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Tabs.tab_panel id="profile" active="profile">Profile panel</Tabs.tab_panel>
      <Tabs.tab_panel id="appearance" active="profile">Appearance panel</Tabs.tab_panel>
      """)

    assert html =~ "Profile panel"
    refute html =~ "Appearance panel"
    assert html =~ ~s(role="tabpanel")
    assert html =~ ~s(id="panel-profile")
    assert html =~ ~s(aria-labelledby="tab-profile")
  end

  test "switching the active id flips which panel renders" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Tabs.tab_panel id="profile" active="appearance">Profile panel</Tabs.tab_panel>
      <Tabs.tab_panel id="appearance" active="appearance">Appearance panel</Tabs.tab_panel>
      """)

    assert html =~ "Appearance panel"
    refute html =~ "Profile panel"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/tabs.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

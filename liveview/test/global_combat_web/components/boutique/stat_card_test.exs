defmodule GlobalCombatWeb.Components.Boutique.StatCardTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.StatCard

  test "renders eyebrow, value, detail and hint on token classes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatCard.stat_card eyebrow="Fleet size" value="24" detail="All sites" hint="Last synced 1m ago" />
      """)

    assert html =~ "Fleet size"
    assert html =~ "24"
    assert html =~ "All sites"
    assert html =~ "Last synced 1m ago"
    assert html =~ "bg-surface"
    assert html =~ "border-border"
    assert html =~ "tabular-nums"
  end

  test "is non-interactive by default — renders a div, not a button" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatCard.stat_card eyebrow="Fleet size" value="24" />
      """)

    refute html =~ "<button"
    assert html =~ "<div"
  end

  test "interactive variant renders a real button with a composed accessible name" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatCard.stat_card
        eyebrow="Offline now"
        value="2"
        tone="danger"
        interactive
        action_label="View"
        phx-click="show_offline"
      />
      """)

    assert html =~ ~s(<button)
    assert html =~ ~s(type="button")
    assert html =~ ~s(aria-label="Offline now: 2")
    assert html =~ ~s(phx-click="show_offline")
    assert html =~ "View"
  end

  test "interactive variant accepts an accessible-name override" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatCard.stat_card eyebrow="Offline now" value="2" interactive aria_label="Custom name" />
      """)

    assert html =~ ~s(aria-label="Custom name")
  end

  test "labels its progress meter and defaults the label to eyebrow" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatCard.stat_card eyebrow="24h availability" value="97%" progress={97} tone="success" />
      """)

    assert html =~ "<progress"
    assert html =~ ~s(aria-label="24h availability")
    assert html =~ ~s(value="97")
    assert html =~ "accent-[var(--color-success)]"
  end

  test "an explicit progress_label overrides the eyebrow fallback" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatCard.stat_card
        eyebrow="24h availability"
        value="97%"
        progress={97}
        progress_label="Uptime over the last 24 hours"
      />
      """)

    assert html =~ ~s(aria-label="Uptime over the last 24 hours")
  end

  test "omits the progress meter entirely when progress is not passed" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatCard.stat_card eyebrow="Fleet size" value="24" />
      """)

    refute html =~ "<progress"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/stat_card.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

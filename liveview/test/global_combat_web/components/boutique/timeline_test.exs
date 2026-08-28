defmodule GlobalCombatWeb.Components.Boutique.TimelineTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Timeline

  @events [
    %{date: "2026-01", title: "Kickoff"},
    %{date: "2026-03", title: "First pilot", detail: "two shops"},
    %{date: "2026-06", title: "GA", current: true},
    %{date: "2026-09", title: "v2 hardware"}
  ]

  test "renders an ordered, labelled list of milestones" do
    assigns = %{events: @events}

    html =
      rendered_to_string(~H"""
      <Timeline.timeline events={@events} label="Product milestones" />
      """)

    assert html =~ ~s(aria-label="Product milestones")
    assert html =~ "<ol "
    assert Enum.count(Regex.scan(~r/<li /, html)) == length(@events)
    assert html =~ "First pilot"
    assert html =~ "two shops"
  end

  test "marks the current milestone and splits history (filled) from future (outlined)" do
    assigns = %{events: @events}

    html =
      rendered_to_string(~H"""
      <Timeline.timeline events={@events} label="Product milestones" />
      """)

    assert html =~ ~s(aria-current="step")
    # reached dots (Kickoff..GA) fill with the primary token
    assert html =~ "bg-primary"
    # future dot (v2 hardware) sits outlined on the surface
    assert html =~ "bg-surface"
    assert html =~ "border-border"
  end

  test "treats a timeline with no current event as finished history (all filled)" do
    assigns = %{
      events: [
        %{date: "2025-01", title: "Founded"},
        %{date: "2025-12", title: "Sold"}
      ]
    }

    html =
      rendered_to_string(~H"""
      <Timeline.timeline events={@events} label="Company history" />
      """)

    refute html =~ ~s(aria-current="step")
    refute html =~ "bg-surface"
    assert Enum.count(Regex.scan(~r/border-primary bg-primary/, html)) == 2
  end

  test "omits the connecting-rule segment before the first dot" do
    assigns = %{events: @events}

    html =
      rendered_to_string(~H"""
      <Timeline.timeline events={@events} label="Product milestones" />
      """)

    # 3 rule segments for 4 events (none before the first)
    assert Enum.count(Regex.scan(~r/top-\[0\.3125rem\]/, html)) == length(@events) - 1
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/timeline.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

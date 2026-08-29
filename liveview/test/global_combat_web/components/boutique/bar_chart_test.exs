defmodule GlobalCombatWeb.Components.Boutique.BarChartTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.BarChart

  @data [
    %{label: "Q1", value: 1208, display: "1.2k"},
    %{label: "Q2", value: 1650, display: "1.7k"},
    %{label: "Q3", value: 2210, display: "2.2k"}
  ]

  test "renders an accessible figure with one bar per datum" do
    assigns = %{data: @data}

    html =
      rendered_to_string(~H"""
      <BarChart.bar_chart label="Orders by quarter" data={@data} />
      """)

    assert html =~ ~s(role="img")
    assert html =~ ~s(aria-label="Orders by quarter")
    assert Enum.count(Regex.scan(~r/<path /, html)) == length(@data)
    # per-mark native tooltip carries label and display value
    assert html =~ "<title>Q1: 1.2k</title>"
  end

  test "direct-labels values in text ink, never the series color" do
    assigns = %{data: @data}

    html =
      rendered_to_string(~H"""
      <BarChart.bar_chart label="Orders by quarter" data={@data} />
      """)

    assert html =~ "fill-text"
    assert html =~ "fill-primary"
    refute html =~ "fill=\"var(--color-primary)\""
  end

  test "ships a sr-only table fallback with the same data, not aria-hidden" do
    assigns = %{data: @data}

    html =
      rendered_to_string(~H"""
      <BarChart.bar_chart label="Orders by quarter" data={@data} />
      """)

    assert html =~ "sr-only"
    assert Enum.count(Regex.scan(~r/<tr>/, html)) == length(@data)
    assert html =~ "Q3"
    assert html =~ "2.2k"
    refute html =~ ~s(<table aria-hidden)
  end

  test "defaults display to the raw value when no display string is given" do
    assigns = %{data: [%{label: "Mon", value: 4}]}

    html =
      rendered_to_string(~H"""
      <BarChart.bar_chart label="Weekly signups" data={@data} />
      """)

    assert html =~ "<title>Mon: 4</title>"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/bar_chart.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

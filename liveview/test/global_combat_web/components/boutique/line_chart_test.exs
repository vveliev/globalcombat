defmodule GlobalCombatWeb.Components.Boutique.LineChartTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.LineChart

  @labels ["Jan", "Feb", "Mar", "Apr"]
  @one [%{name: "Orders", points: [10, 14, 12, 18]}]
  @two [
    %{name: "Orders", points: [10, 14, 12, 18]},
    %{name: "Returns", points: [2, 3, 2, 4]}
  ]

  test "renders one polyline and marker set per series" do
    assigns = %{labels: @labels, series: @two}

    html =
      rendered_to_string(~H"""
      <LineChart.line_chart labels={@labels} series={@series} label="Orders vs returns" />
      """)

    assert html =~ ~s(aria-label="Orders vs returns")
    assert Enum.count(Regex.scan(~r/<polyline /, html)) == 2
    assert Enum.count(Regex.scan(~r/<circle /, html)) == length(@labels) * 2
  end

  test "differentiates the second series by ink AND dash, and legends both" do
    assigns = %{labels: @labels, series: @two}

    html =
      rendered_to_string(~H"""
      <LineChart.line_chart labels={@labels} series={@series} label="Orders vs returns" />
      """)

    assert html =~ "stroke-primary"
    assert html =~ "stroke-text"
    assert html =~ ~s(stroke-dasharray="10 8")
    assert html =~ "<figcaption"
    assert html =~ "Orders"
    assert html =~ "Returns"
  end

  test "skips the legend box for a single series" do
    assigns = %{labels: @labels, series: @one}

    html =
      rendered_to_string(~H"""
      <LineChart.line_chart labels={@labels} series={@series} label="Orders" />
      """)

    refute html =~ "<figcaption"
  end

  test "raises on a third series instead of inventing a palette" do
    assigns = %{labels: @labels, series: @two ++ [%{name: "Refunds", points: [1, 1, 2, 1]}]}

    assert_raise ArgumentError, ~r/1 or 2 series/, fn ->
      rendered_to_string(~H"""
      <LineChart.line_chart labels={@labels} series={@series} label="Too many" />
      """)
    end
  end

  test "accepts a per-point preformatted string in place of the React formatValue callback" do
    assigns = %{
      labels: @labels,
      series: [
        %{
          name: "Orders",
          points: [
            %{value: 10, formatted: "10k"},
            %{value: 14, formatted: "14k"},
            %{value: 12, formatted: "12k"},
            %{value: 18, formatted: "18k"}
          ]
        }
      ]
    }

    html =
      rendered_to_string(~H"""
      <LineChart.line_chart labels={@labels} series={@series} label="Orders" />
      """)

    assert html =~ "Orders — Jan: 10k"
    assert html =~ "18k"
  end

  test "defaults formatted to the raw value's string when only bare numbers are given" do
    assigns = %{labels: @labels, series: @one}

    html =
      rendered_to_string(~H"""
      <LineChart.line_chart labels={@labels} series={@series} label="Orders" />
      """)

    assert html =~ "Orders — Jan: 10"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/line_chart.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

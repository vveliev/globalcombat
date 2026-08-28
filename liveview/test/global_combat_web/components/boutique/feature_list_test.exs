defmodule GlobalCombatWeb.Components.Boutique.FeatureListTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.FeatureList

  test "renders numbered rows, zero-padded, with heading titles" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <FeatureList.feature_list>
        <:item index={1} title="Pawprint tracing">Distributed tracing at paw level.</:item>
        <:item index={2} title="Zoomies profiler">Flame graphs for the 3 a.m. sprint.</:item>
        <:item index={3} title="Nine-lives recovery">Crash reporting that lands on its feet.</:item>
      </FeatureList.feature_list>
      """)

    assert html =~ "01"
    assert html =~ "03"
    assert html =~ "<h3"
    assert html =~ "Zoomies profiler"
    assert html =~ "Distributed tracing at paw level."
  end

  test "parts rows with rules — one fewer than the rows" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <FeatureList.feature_list>
        <:item index={1} title="A">One</:item>
        <:item index={2} title="B">Two</:item>
        <:item index={3} title="C">Three</:item>
      </FeatureList.feature_list>
      """)

    rule_count = html |> String.split("<hr") |> length() |> Kernel.-(1)
    assert rule_count == 2
  end

  test "feature_list_item is independently usable and passes non-numeric index through" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <FeatureList.feature_list_item index="A" title="Custom">Copy here.</FeatureList.feature_list_item>
      """)

    assert html =~ "Custom"
    assert html =~ "Copy here."
    assert html =~ "A"
    # standalone usage still shows its own leading rule by default
    assert html =~ "<hr"
  end

  test "first row suppresses the leading rule when composed by the wrapper" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <FeatureList.feature_list>
        <:item index={1} title="Only row">Just one.</:item>
      </FeatureList.feature_list>
      """)

    refute html =~ "<hr"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/feature_list.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

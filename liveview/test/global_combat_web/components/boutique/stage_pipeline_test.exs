defmodule GlobalCombatWeb.Components.Boutique.StagePipelineTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.StagePipeline

  @stages [
    %{name: "Cut", state: "done", elapsed: "2h 10m"},
    %{name: "Weld", state: "current", elapsed: "45m"},
    %{name: "Galvanize", state: "outsourced"},
    %{name: "QC", state: "pending"}
  ]

  test "renders a labelled ordered list so the sequence survives without sight" do
    assigns = %{stages: @stages}

    html =
      rendered_to_string(~H"""
      <StagePipeline.stage_pipeline stages={@stages} label="Work order WO-1183 stages" />
      """)

    assert html =~ "<ol"
    assert html =~ ~s(aria-label="Work order WO-1183 stages")
    assert Regex.scan(~r/<li/, html) |> length() == 4
  end

  test "writes each stage's state out in words" do
    assigns = %{stages: @stages}

    html =
      rendered_to_string(~H"""
      <StagePipeline.stage_pipeline stages={@stages} label="Stages" />
      """)

    assert html =~ "complete"
    assert html =~ "in progress"
    assert html =~ "outsourced"
    assert html =~ "not started"
  end

  test "marks the current stage programmatically" do
    assigns = %{stages: @stages}

    html =
      rendered_to_string(~H"""
      <StagePipeline.stage_pipeline stages={@stages} label="Stages" />
      """)

    assert html =~ ~s(aria-current="step")
    [_, current_li] = String.split(html, ~s(aria-current="step"), parts: 2)
    assert current_li =~ "Weld"
  end

  test "shows cumulative time where a stage has been booked against" do
    assigns = %{stages: @stages}

    html =
      rendered_to_string(~H"""
      <StagePipeline.stage_pipeline stages={@stages} label="Stages" />
      """)

    assert html =~ "2h 10m"
    assert html =~ "45m"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/stage_pipeline.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

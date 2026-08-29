defmodule GlobalCombatWeb.Components.Boutique.PageStateTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.PageState

  test "loading announces via role=status and requires a label" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <PageState.loading label="Loading fleet…" />
      """)

    assert html =~ ~s(role="status")
    assert html =~ "Loading fleet…"
  end

  test "error announces via role=alert" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <PageState.error title="Couldn't load" message="Try again in a moment." />
      """)

    assert html =~ ~s(role="alert")
    assert html =~ "Couldn&#39;t load"
    assert html =~ "Try again in a moment."
  end

  test "empty renders the optional icon badge hidden from assistive tech" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <PageState.empty title="No devices" message="Add one to get started." icon="hero-inbox" />
      """)

    assert html =~ "No devices"
    assert html =~ ~s(aria-hidden="true")
  end

  test "retry wraps the neutral button with the given phx-click" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <PageState.retry phx-click="retry" />
      """)

    assert html =~ "Retry"
    assert html =~ ~s(phx-click="retry")
    assert html =~ "bg-surface"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/page_state.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

defmodule GlobalCombatWeb.Components.Boutique.StatusPillTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.StatusPill

  test "always renders the module's own status word" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatusPill.status_pill tone="waiting">Sent to vendor</StatusPill.status_pill>
      """)

    assert html =~ "Sent to vendor"
  end

  test "keeps the hue decorative — the dot is hidden from assistive tech" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <StatusPill.status_pill tone="blocked">Overdue</StatusPill.status_pill>
      """)

    assert html =~ ~s(aria-hidden="true")
    assert html =~ "Overdue"
  end

  test "maps all six lifecycle tones onto status tokens, never literals" do
    assigns = %{
      tones: ~w(new active waiting partial blocked done)
    }

    html =
      rendered_to_string(~H"""
      <StatusPill.status_pill :for={tone <- @tones} tone={tone}>{tone}</StatusPill.status_pill>
      """)

    assert html =~ "bg-status-unknown"
    assert html =~ "bg-info"
    assert html =~ "bg-status-warning"
    assert html =~ "bg-status-partial"
    assert html =~ "bg-status-offline"
    assert html =~ "bg-status-online"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/status_pill.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

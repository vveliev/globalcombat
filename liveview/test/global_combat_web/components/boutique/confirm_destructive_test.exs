defmodule GlobalCombatWeb.Components.Boutique.ConfirmDestructiveTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.ConfirmDestructive

  test "renders an accessible dialog naming the action, with the consequence in the body" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ConfirmDestructive.confirm_destructive
        id="archive-modal"
        title="Archive Courier Scout"
        consequence="Its telemetry history stays readable, but the robot stops accepting commands."
        confirm_label="Archive robot"
      />
      """)

    assert html =~ "Archive Courier Scout"
    assert html =~ "stops accepting commands"
    assert html =~ "Archive robot"
  end

  test "confirm is enabled when no phrase gate is set" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ConfirmDestructive.confirm_destructive
        id="archive-modal"
        title="Archive Courier Scout"
        consequence="Stops accepting commands."
        confirm_label="Archive robot"
      />
      """)

    refute html =~ ~r/\sdisabled(\s|>)/
  end

  test "keeps confirm disabled until the required phrase matches exactly" do
    assigns = %{}

    mismatched =
      rendered_to_string(~H"""
      <ConfirmDestructive.confirm_destructive
        id="archive-modal"
        title="Archive Courier Scout"
        consequence="Stops accepting commands."
        confirm_label="Archive robot"
        required_phrase="Courier Scout"
        typed_phrase="Courier"
      />
      """)

    matched =
      rendered_to_string(~H"""
      <ConfirmDestructive.confirm_destructive
        id="archive-modal"
        title="Archive Courier Scout"
        consequence="Stops accepting commands."
        confirm_label="Archive robot"
        required_phrase="Courier Scout"
        typed_phrase="Courier Scout"
      />
      """)

    assert mismatched =~ ~r/\sdisabled(\s|>)/
    refute matched =~ ~r/\sdisabled(\s|>)/
    assert matched =~ "Type the phrase above to continue"
  end

  test "emergency_action slot renders inside the modal body (the focus trap)" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ConfirmDestructive.confirm_destructive
        id="archive-modal"
        title="Archive Courier Scout"
        consequence="Stops accepting commands."
        confirm_label="Archive robot"
      >
        <:emergency_action>
          <button type="button">STOP</button>
        </:emergency_action>
      </ConfirmDestructive.confirm_destructive>
      """)

    assert html =~ "STOP"
    # inside the modal's description/content region, not projected elsewhere
    assert html =~ ~r/id="archive-modal-description"[^>]*>.*STOP.*<\/div>/s
  end

  test "cancel reuses the modal's composed close-and-custom-command hook" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ConfirmDestructive.confirm_destructive
        id="archive-modal"
        title="Archive Courier Scout"
        consequence="Stops accepting commands."
        confirm_label="Archive robot"
        cancel_label="Never mind"
      />
      """)

    assert html =~ "Never mind"
    assert html =~ "data-cancel"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/confirm_destructive.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

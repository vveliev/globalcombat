defmodule GlobalCombatWeb.Components.Boutique.NotificationTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Notification

  test "renders title and message" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Notification.notification id="n1" title="Saved">
        Your changes are live.
      </Notification.notification>
      """)

    assert html =~ "Saved"
    assert html =~ "Your changes are live."
  end

  test "closes via a labelled close button, dismissing client-side by id" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Notification.notification id="n2" title="Saved">Done</Notification.notification>
      """)

    assert html =~ ~s(aria-label="Close notification")
    assert html =~ "#n2"
  end

  test "maps intent to a soft status-hue fill, not a solid fill" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Notification.notification id="n3" intent="danger" title="Failed">
        Something broke.
      </Notification.notification>
      """)

    assert html =~ "bg-danger/10"
    assert html =~ "border-danger"
    assert html =~ "text-danger"
  end

  test "danger and warning announce via role=alert" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Notification.notification id="n4" intent="warning" title="Heads up">
        Check this.
      </Notification.notification>
      """)

    assert html =~ ~s(role="alert")
  end

  test "info and success announce via role=status" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Notification.notification id="n5" intent="success" title="Saved">
        All good.
      </Notification.notification>
      """)

    assert html =~ ~s(role="status")
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/notification.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

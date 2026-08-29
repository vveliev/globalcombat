defmodule GlobalCombatWeb.Components.Boutique.ModalTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Modal

  test "renders an accessible dialog with a title and the projected content" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Modal.modal id="settings-modal" title="Settings">
        Body
      </Modal.modal>
      """)

    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-modal="true")
    assert html =~ "Settings"
    assert html =~ "Body"
  end

  test "carries a labelled close button, inherited from the wrapped primitive" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Modal.modal id="settings-modal" title="Settings">
        Body
      </Modal.modal>
      """)

    assert html =~ ~s(aria-label="close")
  end

  test "paints on semantic tokens, not the primitive's default color/variant classes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Modal.modal id="settings-modal" title="Settings">
        Body
      </Modal.modal>
      """)

    assert html =~ "bg-surface"
    assert html =~ "border-border"
    assert html =~ "rounded-[var(--radius-md)]"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/modal.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

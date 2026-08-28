defmodule GlobalCombatWeb.Components.Boutique.ConfirmDestructive do
  @moduledoc """
  Confirmation dialog for unrecoverable actions — LiveView mirror of
  `components/react/ConfirmDestructive` (ported from robo-hub's
  `@vveliev/react-platform ConfirmDestructive.tsx`). Its two signature
  rules travel with it: `consequence` is required — "a confirm that only
  asks 'are you sure?' gives the operator nothing to be sure about" — and
  the `:emergency_action` slot renders INSIDE the modal's focus trap (their
  spec 017 FR-005 STOP button), never outside it. Built on this port's
  `Boutique.Modal` (`size="sm"`, matching the React default — not exposed
  as a prop here either) and `Boutique.Button` (`intent="danger"` for
  confirm, `intent="neutral"` for cancel).

  State ownership: this is a stateless function component, not a
  LiveComponent, so the type-to-confirm gate's live value is owned by the
  calling LiveView, same as any other Phoenix function component with
  interactive sub-state. Wire an input event (e.g. `phx-keyup`) to a
  handler that updates a `typed_phrase` assign, pass that assign back in as
  `:typed_phrase`, and name the event via `:phrase_change` — the confirm
  button's `disabled` is computed from `typed_phrase == required_phrase` on
  every render, no client-only JS gate involved. Confirm/cancel actions are
  `Phoenix.LiveView.JS` commands (`:on_confirm`/`:on_cancel`), matching
  `Boutique.Modal`'s own `on_cancel` convention; cancel reuses the modal's
  composed close-and-custom-command path via its `data-cancel` hook so
  there's one source of truth for "cancel" regardless of whether it's
  triggered by this button, Escape, or click-away.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  alias GlobalCombatWeb.Components.Boutique.{Button, Input, Modal}

  attr :id, :string, required: true

  attr :title, :string,
    required: true,
    doc: "Names the action and its object, e.g. \"Archive Courier Scout\"."

  attr :consequence, :string,
    required: true,
    doc: "What happens if the user continues. Required on purpose."

  attr :confirm_label, :string,
    required: true,
    doc: "A verb phrase, e.g. \"Archive robot\" — never \"OK\"."

  attr :required_phrase, :string,
    default: nil,
    doc: "Type-to-confirm gate. Reserve for actions unrecoverable from the app itself."

  attr :required_phrase_label, :string, default: "Type the phrase above to continue"
  attr :typed_phrase, :string, default: "", doc: "Owned by the caller's LiveView; see moduledoc."

  attr :phrase_change, :string,
    default: nil,
    doc: "phx-keyup event name the caller updates typed_phrase from."

  attr :cancel_label, :string, default: "Cancel"
  attr :loading, :boolean, default: false, doc: "Shows in-flight state on the confirm button."
  attr :show, :boolean, default: false
  attr :on_confirm, JS, default: %JS{}
  attr :on_cancel, JS, default: %JS{}
  attr :class, :any, default: nil

  slot :emergency_action,
    doc:
      "A control that must stay reachable while the dialog traps focus (e.g. an emergency STOP). Not a general footer slot."

  def confirm_destructive(assigns) do
    ~H"""
    <Modal.modal id={@id} title={@title} show={@show} on_cancel={@on_cancel} size="sm" class={@class}>
      <div class="flex flex-col gap-[var(--space-4)]">
        <p class="text-text">{@consequence}</p>

        <div :if={@required_phrase} class="flex flex-col gap-[var(--space-2)]">
          <p class="font-mono text-danger">{@required_phrase}</p>
          <Input.input
            id={"#{@id}-phrase"}
            name="typed_phrase"
            label={@required_phrase_label}
            value={@typed_phrase}
            phx-keyup={@phrase_change}
          />
        </div>

        <div :if={@emergency_action != []}>
          {render_slot(@emergency_action)}
        </div>

        <div class="flex justify-end gap-[var(--space-3)]">
          <Button.button intent="neutral" phx-click={JS.exec("data-cancel", to: "##{@id}")}>
            {@cancel_label}
          </Button.button>
          <Button.button
            intent="danger"
            disabled={confirm_disabled?(@loading, @required_phrase, @typed_phrase)}
            phx-click={@on_confirm}
          >
            <span
              :if={@loading}
              aria-hidden="true"
              class="inline-block size-4 rounded-full border-2 border-white/40 border-t-white animate-spin"
            />
            {@confirm_label}
          </Button.button>
        </div>
      </div>
    </Modal.modal>
    """
  end

  defp confirm_disabled?(loading, required_phrase, typed_phrase) do
    loading || !phrase_satisfied?(required_phrase, typed_phrase)
  end

  defp phrase_satisfied?(nil, _typed_phrase), do: true
  defp phrase_satisfied?(required_phrase, typed_phrase), do: required_phrase == typed_phrase
end

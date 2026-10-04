defmodule GlobalCombatWeb.GameLive.Dock do
  @moduledoc """
  The stage-mode action dock: the order panel while a territory is selected, the turn
  controls (End Turn / Waiting / Force Turn / Quit) otherwise.

  Only markup lives here. The selection (`:selected_area`/`:target_area`) and the draft
  `:order_amount` are `GameLive` socket assigns, and every button only fires an event
  (`submit_order`, `change_amount`, `step_amount`, `max_amount`, `unassign_order`,
  `cancel_order`, `done`, `force_turn`, `quit`) that `GameLive` handles.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Card
  alias GlobalCombatWeb.Components.Boutique.Input

  import GlobalCombatWeb.GameLive.ViewHelpers, only: [find_area: 2, my_player: 1]

  # The dock's idle row (End Turn/Waiting/Force Turn) when nothing is
  # selected, or the order panel once a territory is — never both, so a
  # player never has to scroll the sheet to find the button they want
  # (`docs/mobile-battle-mode.md` §4.3, "Dock contents by state"). Only
  # rendered at all while stage mode is on (`GameLive`'s `:dock` slot),
  # which already implies `@view.ended == false` — but not that there's a
  # seated player: a spectator's `viewer_number` is `nil`, so `my_player/1`
  # returns `nil` and a turn-controls row built around `my_player(@view).done`
  # must stay gated on `@view.viewer_number`, same as the original
  # (pre-stage) turn-controls div was.
  attr :view, :map, required: true
  attr :selected_area, :any, required: true
  attr :target_area, :any, required: true
  attr :order_amount, :string, required: true

  def dock(assigns) do
    ~H"""
    <.order_panel
      :if={@selected_area}
      view={@view}
      selected_area={@selected_area}
      target_area={@target_area}
      order_amount={@order_amount}
    />
    <div
      :if={!@selected_area && @view.viewer_number}
      id="turn-controls"
      class="flex flex-col gap-[var(--space-2)] sm:flex-row"
    >
      <Button.button
        :if={!my_player(@view).done}
        id="end-turn-button"
        class="w-full sm:w-auto"
        phx-click="done"
      >
        End Turn
      </Button.button>
      <span :if={my_player(@view).done} class="text-text-muted">Waiting on other players…</span>
      <Button.button
        id="force-turn-button"
        intent="neutral"
        class="w-full sm:w-auto"
        phx-click="force_turn"
      >
        Force Turn
      </Button.button>
      <%!-- Desktop only: below lg the drawer carries Quit instead (the
      #quit-button in GameLive's :players slot). --%>
      <Button.button
        :if={!my_player(@view).eliminated}
        id="turn-controls-quit"
        intent="neutral"
        class="max-lg:hidden"
        phx-click="quit"
      >
        Quit
      </Button.button>
    </div>
    """
  end

  # The order-composition panel — LiveView equivalent of `Main.js`'s
  # `EntryForm`/`ActionMessage`/`AmountInput`/`ActionSubmit`. `:assign` (no target
  # picked yet) offers Assign + Unassign (only if there's something pending to undo);
  # `:transfer`/`:attack` (a target picked) offer a single verb button matching
  # `SelectTarget`'s owned-vs-enemy branch.
  attr :view, :map, required: true
  attr :selected_area, :integer, required: true
  attr :target_area, :any, required: true
  attr :order_amount, :string, required: true

  defp order_panel(assigns) do
    source = find_area(assigns.view, assigns.selected_area)
    target = assigns.target_area && find_area(assigns.view, assigns.target_area)
    mode = order_mode(assigns.view, target)

    assigns = assign(assigns, source: source, target: target, mode: mode)

    ~H"""
    <Card.card id="order-panel" class="min-w-[16rem]">
      <:header>{order_panel_title(@mode, @target)}</:header>
      <form
        id="order-form"
        phx-change="change_amount"
        phx-submit="submit_order"
        class="flex flex-col gap-[var(--space-3)]"
      >
        <Input.input
          id="order-amount"
          name="amount"
          type="number"
          min="0"
          label="Armies"
          value={@order_amount}
          inputmode="numeric"
          pattern="[0-9]*"
          autocomplete="off"
          enterkeyhint="done"
        />
        <div id="order-stepper" class="flex flex-wrap gap-[var(--space-2)]">
          <Button.button
            type="button"
            intent="neutral"
            phx-click="step_amount"
            phx-value-delta="-1"
            aria-label="One army fewer"
          >
            −
          </Button.button>
          <Button.button
            type="button"
            intent="neutral"
            phx-click="step_amount"
            phx-value-delta="1"
            aria-label="One army more"
          >
            +
          </Button.button>
          <Button.button type="button" intent="neutral" phx-click="max_amount">
            Max
          </Button.button>
        </div>
        <div class="flex flex-wrap gap-[var(--space-2)]">
          <Button.button type="submit" intent="primary">
            {order_submit_label(@mode)}
          </Button.button>
          <Button.button
            :if={(@mode == :assign and @source) && @source.pending_armies > 0}
            type="button"
            intent="neutral"
            phx-click="unassign_order"
          >
            Unassign
          </Button.button>
          <Button.button type="button" intent="neutral" phx-click="cancel_order">
            Cancel
          </Button.button>
        </div>
      </form>
    </Card.card>
    """
  end

  defp order_mode(_view, nil), do: :assign

  defp order_mode(view, target),
    do: if(target.owner_number == view.viewer_number, do: :transfer, else: :attack)

  defp order_panel_title(:assign, _target), do: "Assign new armies or select a target area"
  defp order_panel_title(:transfer, target), do: "Transfer how many armies to #{target.name}?"
  defp order_panel_title(:attack, target), do: "Attack #{target.name} with how many armies?"

  defp order_submit_label(:assign), do: "Assign"
  defp order_submit_label(:transfer), do: "Transfer"
  defp order_submit_label(:attack), do: "Attack"
end

defmodule GlobalCombatWeb.GameLive.Dock do
  @moduledoc """
  The stage-mode action dock: the order panel (with the phone's placement bar) while a
  territory is selected, the turn controls (Undo / coach line / End Turn / Waiting / Force
  Turn / Quit) otherwise.

  Only markup lives here. The selection (`:selected_area`/`:target_area`), the draft
  `:order_amount`, the Undo history and End Turn's armed state are `GameLive` socket assigns,
  and every button only fires an event (`submit_order`, `change_amount`, `step_amount`,
  `max_amount`, `unassign_order`, `remove_order`, `cancel_order`, `quick_assign`,
  `unplace_one`, `undo_assign`, `arm_end_turn`, `done`, `force_turn`, `quit`) that `GameLive`
  handles. The HUD wording and numbers come from `GameLive.Hud`.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Card
  alias GlobalCombatWeb.Components.Boutique.Input
  alias GlobalCombatWeb.GameLive.Hud
  alias GlobalCombatWeb.GameLive.WorldMap

  import GlobalCombatWeb.GameLive.ViewHelpers,
    only: [find_area: 2, my_player: 1, order_limit: 3, order_queued_to?: 2, parse_amount: 1]

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
  #
  # The idle row reads like a game HUD: an Undo for the latest placed
  # reinforcement, a coach line saying what to do next, and End Turn as a big
  # thumb button whose ring fills as reinforcements are placed. Ending a turn
  # with armies still unplaced takes a second tap (`arm_end_turn`).
  attr :view, :map, required: true
  attr :selected_area, :any, required: true
  attr :target_area, :any, required: true
  attr :order_amount, :string, required: true

  attr :assign_history, :list,
    required: true,
    doc: "the Undo history (`GameLive`'s `:assign_history`); Undo shows while it's non-empty"

  attr :end_turn_armed, :boolean,
    required: true,
    doc: "End Turn was tapped once with armies unplaced; the next tap ends the turn"

  def dock(assigns) do
    me = assigns.view.viewer_number && my_player(assigns.view)

    assigns =
      assign(assigns,
        me: me,
        progress: me && Hud.placement_progress(assigns.view, me),
        coach: me && Hud.coach_line(assigns.view, me, :phone),
        desktop_coach: me && Hud.coach_line(assigns.view, me, :desktop)
      )

    ~H"""
    <.order_panel
      :if={@selected_area}
      view={@view}
      selected_area={@selected_area}
      target_area={@target_area}
      order_amount={@order_amount}
    />
    <div :if={!@selected_area && @me} id="turn-controls" class="turn-controls">
      <button
        :if={@assign_history != [] && !@me.done}
        type="button"
        id="undo-assign"
        phx-click="undo_assign"
        aria-label="Undo last placement"
        class="hud-chip turn-controls-undo lg:hidden"
      >
        <.icon name="hero-arrow-uturn-left" class="size-5" />
      </button>
      <p :if={@coach} id="turn-coach" class="turn-coach">
        <span class="lg:hidden">{@coach}</span>
        <span class="hidden lg:inline">{@desktop_coach}</span>
      </p>
      <div class="turn-controls-actions">
        <button
          :if={!@me.done}
          type="button"
          id="end-turn"
          phx-click={
            if(@me.unassigned_armies == 0 or @end_turn_armed, do: "done", else: "arm_end_turn")
          }
          data-unplaced={@me.unassigned_armies}
          class={[
            "end-turn",
            @me.unassigned_armies == 0 && "end-turn--ready",
            @end_turn_armed && "is-armed"
          ]}
        >
          <svg class="end-turn-ring" viewBox="0 0 100 100" aria-hidden="true">
            <circle class="end-turn-ring-track" cx="50" cy="50" r="46" pathLength="100" />
            <circle
              class="end-turn-ring-fill"
              cx="50"
              cy="50"
              r="46"
              pathLength="100"
              stroke-dashoffset={100 - round(@progress * 100)}
            />
          </svg>
          <span class="end-turn-label">
            {if @end_turn_armed,
              do: "#{@me.unassigned_armies} unplaced · tap again",
              else: "End Turn"}
          </span>
        </button>
        <Button.button
          id="force-turn"
          intent="neutral"
          class="turn-controls-force"
          phx-click="force_turn"
        >
          Force Turn
        </Button.button>
        <%!-- Desktop only: below lg the drawer carries Quit instead (the
        #quit-button in GameLive's :players slot). --%>
        <Button.button
          :if={!@me.eliminated}
          id="turn-controls-quit"
          intent="neutral"
          class="max-lg:hidden"
          phx-click="quit"
        >
          Quit
        </Button.button>
        <span :if={@me.done} class="turn-waiting">Waiting on other players…</span>
      </div>
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

  # A slider and quick picks (1 · Half · Max) sit beside the exact number, so a
  # thumb can set an amount without the keyboard. Opened on an order that is
  # already queued (a drag, or tapping its arrow) it edits that order: the
  # primary button updates it and Remove takes it off the board. A territory
  # carries one order a turn, so when a different one is already queued from
  # the source the panel says which order submitting would replace.
  #
  # With a target picked the card carries `data-anchor`, the board point at
  # the middle of the order's arrow; on a phone `.MapViewport` floats the card
  # beside that point instead of leaving it in the dock.
  defp order_panel(assigns) do
    view = assigns.view
    source = find_area(view, assigns.selected_area)
    target = assigns.target_area && find_area(view, assigns.target_area)
    mode = order_mode(view, target)
    limit = order_limit(view, assigns.selected_area, assigns.target_area) || 0
    queued? = WorldMap.queued_order?(source)
    editing? = order_queued_to?(source, assigns.target_area)

    replaces =
      if mode != :assign and queued? and not editing?,
        do: find_area(view, source.order.target)

    assigns =
      assign(assigns,
        source: source,
        target: target,
        mode: mode,
        limit: limit,
        half: max(div(limit, 2), 1),
        amount: max(parse_amount(assigns.order_amount), 0),
        editing: editing?,
        replaces: replaces,
        anchor: target && WorldMap.order_anchor(view.map_name, source.number, target.number)
      )

    ~H"""
    <Card.card
      id="order-panel"
      class={["order-panel min-w-[16rem]", "order-panel--#{@mode}"]}
      data-anchor={@anchor}
    >
      <:header>
        <span class="lg:hidden">{phone_panel_title(@mode, @source, @target)}</span>
        <span class="hidden lg:inline">{order_panel_title(@mode, @target)}</span>
      </:header>
      <%!-- The phone's placement bar: a tap selected this territory; these
      buttons place on it, one tap each, and −1 takes one back. Below `lg`
      it replaces the amount form for placing (the form stays for orders). --%>
      <div :if={@mode == :assign && @source} id="placement-bar" class="placement-bar lg:hidden">
        <p id="placement-status" class="placement-status">
          <b>{@source.armies}</b>
          armies<span :if={@source.pending_armies > 0}>
            (+{@source.pending_armies})
          </span>
          · <b>{@limit}</b>
          left
        </p>
        <div class="placement-buttons">
          <Button.button
            id="place-minus"
            type="button"
            intent="neutral"
            phx-click="unplace_one"
            phx-value-area={@source.number}
            disabled={@source.pending_armies == 0}
            aria-label="Take one army back"
          >
            −1
          </Button.button>
          <Button.button
            id="place-one"
            type="button"
            phx-click="quick_assign"
            phx-value-area={@source.number}
            phx-value-amount="1"
            disabled={@limit == 0}
          >
            +1
          </Button.button>
          <Button.button
            id="place-five"
            type="button"
            phx-click="quick_assign"
            phx-value-area={@source.number}
            phx-value-amount={Hud.hold_amount()}
            disabled={@limit == 0}
          >
            +{Hud.hold_amount()}
          </Button.button>
          <Button.button
            id="place-all"
            type="button"
            phx-click="quick_assign"
            phx-value-area={@source.number}
            phx-value-amount="all"
            disabled={@limit == 0}
          >
            All {@limit}
          </Button.button>
          <Button.button
            id="placement-done"
            type="button"
            intent="neutral"
            phx-click="cancel_order"
            aria-label="Done"
          >
            <.icon name="hero-check" class="size-5" />
          </Button.button>
        </div>
        <p class="placement-hint">Drag the army token onto a neighbour to attack or move</p>
      </div>
      <form
        id="order-form"
        phx-change="change_amount"
        phx-submit="submit_order"
        class={["flex flex-col gap-[var(--space-3)]", @mode == :assign && "max-lg:hidden"]}
      >
        <p :if={@replaces} id="order-replaces" class="order-replaces">
          Replaces {@source.name}'s order to {@replaces.name}: one order per territory each turn.
        </p>
        <div class="order-amount-row">
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
            class="order-amount-input"
          />
          <%!-- A plain range input: the design system's Input has no slider
          variant, and its label/field wrapper doesn't fit a bare track. --%>
          <input
            :if={@limit > 0}
            id="order-amount-range"
            name="amount_range"
            type="range"
            min="0"
            max={@limit}
            value={min(@amount, @limit)}
            aria-label="Armies"
            class="order-amount-range"
          />
        </div>
        <div id="order-stepper" class="order-stepper">
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
          <Button.button
            :if={@limit > 1}
            id="order-pick-one"
            type="button"
            intent="neutral"
            phx-click="change_amount"
            phx-value-amount="1"
          >
            1
          </Button.button>
          <Button.button
            :if={@limit > 2}
            id="order-pick-half"
            type="button"
            intent="neutral"
            phx-click="change_amount"
            phx-value-amount={@half}
            aria-label={"Half: #{@half}"}
          >
            ½
          </Button.button>
          <Button.button id="order-pick-max" type="button" intent="neutral" phx-click="max_amount">
            Max
          </Button.button>
        </div>
        <div class="order-actions">
          <Button.button id="order-submit" type="submit" intent="primary" class="order-submit">
            {order_submit_label(@mode)} {@amount}
          </Button.button>
          <Button.button
            :if={(@mode == :assign and @source) && @source.pending_armies > 0}
            type="button"
            intent="neutral"
            phx-click="unassign_order"
          >
            Unassign
          </Button.button>
          <Button.button
            :if={@editing}
            type="button"
            intent="neutral"
            id="remove-order"
            phx-click="remove_order"
          >
            Remove
          </Button.button>
          <Button.button id="order-cancel" type="button" intent="neutral" phx-click="cancel_order">
            {if @editing, do: "Keep", else: "Cancel"}
          </Button.button>
        </div>
      </form>
    </Card.card>
    """
  end

  defp order_mode(_view, nil), do: :assign

  defp order_mode(view, target),
    do: if(target.owner_number == view.viewer_number, do: :transfer, else: :attack)

  # The phone's short panel titles: the territory first, then what the panel does.
  defp phone_panel_title(:assign, source, _target), do: "#{source.name} · place armies"
  defp phone_panel_title(:transfer, source, target), do: "#{source.name} → #{target.name} · move"
  defp phone_panel_title(:attack, source, target), do: "#{source.name} → #{target.name} · attack"

  defp order_panel_title(:assign, _target), do: "Assign new armies or select a target area"
  defp order_panel_title(:transfer, target), do: "Transfer how many armies to #{target.name}?"
  defp order_panel_title(:attack, target), do: "Attack #{target.name} with how many armies?"

  defp order_submit_label(:assign), do: "Assign"
  defp order_submit_label(:transfer), do: "Transfer"
  defp order_submit_label(:attack), do: "Attack"
end

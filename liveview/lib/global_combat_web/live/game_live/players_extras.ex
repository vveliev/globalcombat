defmodule GlobalCombatWeb.GameLive.PlayersExtras do
  @moduledoc """
  The in-play cards between the roster and chat in the players drawer/rail
  (`docs/mobile-battle-mode.md` §4.3): the viewer's army and income breakdown, region bonuses,
  the viewer's queued orders, and the last turn's results (`GameLive.TurnResults`). Only
  rendered while the game is playing.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombat.Engine.MapInfo
  alias GlobalCombatWeb.Components.Boutique.Card
  alias GlobalCombatWeb.GameLive.Hud
  alias GlobalCombatWeb.GameLive.TurnResults
  alias GlobalCombatWeb.GameLive.WorldMap

  import GlobalCombatWeb.GameLive.ViewHelpers, only: [my_player: 1]

  attr :view, :map, required: true
  attr :replay_steps, :list, required: true

  def players_extras(assigns) do
    me = assigns.view.viewer_number && my_player(assigns.view)

    assigns =
      assign(assigns,
        my_orders: my_orders(assigns.view),
        income: me && !me.eliminated && Hud.income(assigns.view, me),
        unplaced: me && me.unassigned_armies
      )

    ~H"""
    <.income_card :if={!@view.ended && @income} income={@income} unplaced={@unplaced} />
    <.region_bonuses :if={!@view.ended} map_name={@view.map_name} />
    <.your_orders_card :if={@my_orders != []} orders={@my_orders} />
    <TurnResults.turn_results :if={@replay_steps != []} turn={@view.turn} steps={@replay_steps} />
    """
  end

  # The same queued transfers/attacks the board draws as arrows, worded as
  # plain text — an "error prevention" review surface for all five queued orders at
  # once without re-clicking every source territory, and the accessible equivalent of
  # the arrows for anyone who can't see the board (an arrow's own `aria-label` covers
  # it in isolation, but this list is what makes "did I queue everything I meant to"
  # answerable in one place). `WorldMap.order_label/3` words each line so this list and
  # an arrow's `aria-label` can never describe the same order differently.
  # `view.areas` already dropped every non-owner's `order` to `nil` (`PlayerView`'s
  # fog-of-war boundary), so this needs no owner check of its own.
  defp my_orders(view) do
    area_names = WorldMap.area_names(view.areas)

    # A removed order is one cut to zero armies (`remove_order`) — not listed.
    for area <- view.areas, WorldMap.queued_order?(area) do
      WorldMap.order_label(area.name, area.order, Map.fetch!(area_names, area.order.target))
    end
  end

  # Where the viewer's armies stand: on the board, still to place this turn,
  # and what next turn brings, worked out the way the engine does it
  # (`Hud.income/2`) so the player can see why — territories, then each region
  # held outright, then the game's minimum if that is what applies.
  attr :income, :map, required: true
  attr :unplaced, :integer, required: true

  defp income_card(assigns) do
    ~H"""
    <Card.card id="income-breakdown" class="min-w-[16rem]">
      <:header>Your armies</:header>
      <dl class="income-list">
        <div>
          <dt>On the board and in hand</dt>
          <dd class="tabular-nums">{@income.armies}</dd>
        </div>
        <div>
          <dt>Left to place this turn</dt>
          <dd class="tabular-nums">{@unplaced}</dd>
        </div>
        <div class="income-total">
          <dt>Next turn</dt>
          <dd class="tabular-nums">+{@income.total}</dd>
        </div>
        <div>
          <dt>{@income.territories} territories ÷ 2</dt>
          <dd class="tabular-nums">+{@income.base}</dd>
        </div>
        <div :for={bonus <- @income.bonuses}>
          <dt>{bonus.name} held</dt>
          <dd class="tabular-nums">+{bonus.bonus}</dd>
        </div>
        <div :if={@income.bonuses == []}>
          <dt>Region bonuses</dt>
          <dd>none held yet</dd>
        </div>
        <div :if={@income.total == @income.minimum and @income.minimum > 0}>
          <dt>Game minimum applies</dt>
          <dd class="tabular-nums">{@income.minimum}</dd>
        </div>
      </dl>
    </Card.card>
    """
  end

  attr :orders, :list, required: true

  defp your_orders_card(assigns) do
    ~H"""
    <Card.card class="min-w-[16rem]">
      <:header>Your orders</:header>
      <ul id="your-orders" class="flex flex-col gap-[var(--space-1)] text-sm">
        <li :for={order <- @orders}>{order}</li>
      </ul>
    </Card.card>
    """
  end

  # Player-facing rule info: every region's control bonus, sourced
  # from the same `MapInfo.regions/1` the board's areas/adjacency already
  # come from rather than hardcoded per-map text, so a future map addition
  # doesn't need a matching edit here.
  #
  # The map itself draws these bonuses as a legend in its bottom-left sea
  # (`WorldMap.legend/1`), like a printed board. That legend is SVG art that
  # shrinks with the board, too small to read below `md:`, so there this
  # list stays visible in the players drawer (`players_extras/1`); from `md:`
  # up it is screen-reader only, since the legend is aria-hidden.
  attr :map_name, :atom, required: true

  defp region_bonuses(assigns) do
    # Same highest-bonus-first order as the map's legend.
    regions = assigns.map_name |> MapInfo.regions() |> Enum.sort_by(&elem(&1, 3), :desc)
    assigns = assign(assigns, :regions, regions)

    ~H"""
    <section
      id="region-bonuses"
      aria-labelledby="region-bonuses-heading"
      class="mt-[var(--space-2)] flex flex-wrap items-baseline gap-x-[var(--space-3)] text-xs leading-tight text-text md:sr-only"
    >
      <h2
        id="region-bonuses-heading"
        class="m-0 font-semibold uppercase tracking-wide text-text-muted"
      >
        Region Bonuses
      </h2>
      <ul class="m-0 flex list-none flex-wrap gap-x-[var(--space-3)] p-0">
        <li
          :for={{_number, name, _num_areas, army_bonus} <- @regions}
          class="flex items-center gap-[var(--space-1)]"
        >
          <span>{name}</span>
          <span class="font-semibold tabular-nums">{army_bonus}</span>
        </li>
      </ul>
    </section>
    """
  end
end

defmodule GlobalCombatWeb.GameLive.Hud do
  @moduledoc """
  The game HUD's own logic, kept out of `GameLive` (`docs/mobile-battle-mode.md`
  §8): where the viewer is in the turn and how that is worded, End Turn's
  progress ring, the lens button, what a tap, hold, drag or Undo should do,
  and the bookkeeping behind them — the optimistic local copies and the Undo
  history.

  Everything here is a pure function of a `GlobalCombat.Games.PlayerView` (and,
  where it matters, the viewer's own entry in `view.players`, which `GameLive`
  already looks up once per render). Nothing talks to the game server:
  `placement/4`, `undo_plan/3` and `drag_plan/4` say what to send, and
  `GameLive` sends it.
  """

  alias GlobalCombat.Engine.MapInfo
  alias GlobalCombatWeb.GameLive.WorldMap

  @lenses [:owner, :region, :frontier]
  @hold_amount 5

  @doc "The placement bar's bigger step (+5): `quick_assign` never places more at once, except \"All\"."
  def hold_amount, do: @hold_amount

  @doc "True when `area` is visible to, and owned by, the seated viewer."
  def own_area?(view, area), do: WorldMap.viewer_owns?(area, view.viewer_number)

  @doc """
  What a tap/hold placement of `requested` armies on `area_number` should
  queue: `{:ok, amount}` (clamped to 1..`hold_amount/0` and to the pool) or
  `:error` when the viewer can't place there.
  """
  def placement(view, me, area_number, requested) do
    with %{done: false, unassigned_armies: pool} when pool > 0 <- me,
         %{} = area <- find_area(view, area_number),
         true <- own_area?(view, area) do
      case requested do
        :all -> {:ok, pool}
        n -> {:ok, n |> max(1) |> min(@hold_amount) |> min(pool)}
      end
    else
      _ -> :error
    end
  end

  @doc """
  What the viewer will be given next turn, worked the way the engine does it
  (`Engine.Game.reinforce/2`): half their territories, rounded down, plus the
  bonus of every region they hold outright, never below the game's minimum.
  `nil` for a viewer without a seat.
  """
  def income(_view, nil), do: nil

  def income(view, me) do
    owned = Enum.filter(view.areas, &own_area?(view, &1))
    owned_numbers = MapSet.new(owned, & &1.number)
    areas_by_region = WorldMap.areas_by_region(view.map_name)

    bonuses =
      for {number, name, _num_areas, bonus} <- MapInfo.regions(view.map_name),
          Enum.all?(Map.fetch!(areas_by_region, number), &MapSet.member?(owned_numbers, &1)),
          do: %{name: name, bonus: bonus}

    base = div(length(owned), 2)
    minimum = Map.get(view, :minimum_armies, 0)
    subtotal = base + Enum.sum(Enum.map(bonuses, & &1.bonus))

    %{
      territories: length(owned),
      base: base,
      bonuses: bonuses,
      minimum: minimum,
      total: max(subtotal, minimum),
      armies: me.armies
    }
  end

  @doc """
  How to undo the placement `{area_number, amount}`. The engine can only clear
  an area's whole assignment, so: clear it, re-queue `keep` (what came before),
  and — since clearing also trims a transfer/attack queued from that area to
  what its standing armies alone allow — put that order back at as much of
  its amount as the area can still send. Returns `{:ok, plan}` or `:error`.
  """
  def undo_plan(view, me, {area_number, amount}) do
    with %{done: false} <- me,
         %{} = area <- find_area(view, area_number),
         true <- own_area?(view, area) do
      undone = min(amount, area.pending_armies)

      order =
        if WorldMap.queued_order?(area),
          do: {area.order.target, min(area.order.amount, max(area.armies - undone - 1, 0))}

      {:ok,
       %{area: area_number, undone: undone, keep: area.pending_armies - undone, order: order}}
    else
      _ -> :error
    end
  end

  @doc """
  What releasing a drag from `from` over `to` should do. A territory carries
  one order a turn, so it depends on what is already queued from it:

    * `{:queue, order}` — nothing queued: queue `order` now, with everything
      the territory can spare;
    * `{:reopen, amount}` — this same order is queued: reopen it untouched;
    * `{:draft, amount}` — an order to somewhere else is queued: queue nothing
      yet, and let the panel say which order submitting would replace;
    * `:error` — not a legal drag.
  """
  def drag_plan(view, me, from, to) do
    with %{done: false} <- me,
         %{} = source <- find_area(view, from),
         true <- own_area?(view, source),
         %{visible: true} = target <- find_area(view, to),
         true <- to in source.adjacent,
         spare when spare > 0 <- spare_armies(source) do
      cond do
        not WorldMap.queued_order?(source) ->
          command = if own_area?(view, target), do: :transfer, else: :attack
          {:queue, %{command: command, target: to, amount: spare}}

        source.order.target == to ->
          {:reopen, source.order.amount}

        true ->
          {:draft, spare}
      end
    else
      _ -> :error
    end
  end

  @doc """
  What a phone tap on `area_number` does, given the area currently selected:

    * `{:select, n}` — one of the viewer's own: select it (the placement bar
      opens on it). Orders between your own territories are dragged, so a
      tap on another own territory switches selection rather than target it;
    * `{:target, n}` — a visible enemy neighbour of the selected territory:
      target it (the attack panel opens);
    * `:clear` — anything else while something is selected: close the panel;
    * `:none` — anything else.
  """
  def tap_plan(view, selected, area_number) do
    area = find_area(view, area_number)
    source = selected && find_area(view, selected)

    cond do
      is_nil(area) -> :none
      own_area?(view, area) -> {:select, area_number}
      source && area.visible && area_number in source.adjacent -> {:target, area_number}
      source -> :clear
      true -> :none
    end
  end

  @doc "The most a transfer/attack from `area` can send: the engine always leaves one army behind."
  def spare_armies(area), do: max(area.armies - 1, 0)

  @doc """
  Where the viewer is in the turn, in the order a turn is played: `:watching`
  (no seat, or eliminated), `:done` (ended their turn), `{:place, n}` (`n`
  reinforcements still to place) or `{:orders, n}` (`n` orders queued).
  """
  def turn_phase(_view, nil), do: :watching
  def turn_phase(_view, %{eliminated: true}), do: :watching
  def turn_phase(_view, %{done: true}), do: :done
  def turn_phase(_view, %{unassigned_armies: n}) when n > 0, do: {:place, n}
  def turn_phase(view, _me), do: {:orders, Enum.count(view.areas, &WorldMap.queued_order?/1)}

  @doc "The status strip's short readout of `turn_phase/2`; `nil` when there is nothing to say."
  def turn_hint(view, me) do
    case turn_phase(view, me) do
      :watching -> nil
      :done -> "Waiting on others"
      {:place, n} -> "Place #{armies(n)}"
      {:orders, 0} -> "Give your orders"
      {:orders, n} -> "#{orders(n)} ready"
    end
  end

  @doc """
  The dock's one sentence on what to do next, worded for how the board is
  played at that size: `:phone` (below `lg`, the tap/hold/drag gestures) or
  `:desktop` (click a territory, then a neighbour).
  """
  def coach_line(view, me, size) do
    case {turn_phase(view, me), size} do
      {:watching, _} ->
        nil

      {:done, _} ->
        "Orders locked in. The turn runs once everyone has ended theirs."

      {{:place, n}, :phone} ->
        "Tap a territory of yours to place #{armies(n)} there"

      {{:place, n}, :desktop} ->
        "Click your territories to place #{armies(n)}"

      {{:orders, 0}, :phone} ->
        "Drag an army token onto a neighbour to attack or move"

      {{:orders, 0}, :desktop} ->
        "Click your territory, then a neighbour, to attack or move"

      {{:orders, n}, :phone} ->
        "#{orders(n)} ready · tap an arrow to change it"

      {{:orders, n}, :desktop} ->
        "#{orders(n)} ready · click an arrow to change it"
    end
  end

  @doc "How many reinforcements a seated, still-playing viewer has left to place; `nil` for anyone who can't act."
  def gesture_pool(view, me) do
    case turn_phase(view, me) do
      {:place, n} -> n
      {:orders, _n} -> 0
      _ -> nil
    end
  end

  @doc "Share (0.0..1.0) of this turn's reinforcements already placed, for End Turn's ring."
  def placement_progress(view, me) do
    placed =
      view.areas
      |> Enum.filter(&own_area?(view, &1))
      |> Enum.map(& &1.pending_armies)
      |> Enum.sum()

    case placed + me.unassigned_armies do
      0 -> 1.0
      total -> placed / total
    end
  end

  @doc "The lens after `lens` on the phone HUD's one-button lens control."
  def next_lens(lens) do
    index = Enum.find_index(@lenses, &(&1 == lens))
    Enum.at(@lenses, rem(index + 1, length(@lenses)))
  end

  def lens_name(:owner), do: "Owner"
  def lens_name(:region), do: "Region control"
  def lens_name(:frontier), do: "Frontier"

  def lens_icon(:owner), do: "hero-flag"
  def lens_icon(:region), do: "hero-squares-2x2"
  def lens_icon(:frontier), do: "hero-shield-exclamation"

  @doc """
  Optimistic local copy of an assign (`delta > 0`) or its undo (`delta < 0`) on
  the viewer's own area and pool, so the HUD responds before the server's
  `:reload` replaces the view with the truth.
  """
  def adjust_assigned(view, area_number, delta) do
    viewer = view.viewer_number

    areas =
      Enum.map(view.areas, fn
        %{number: ^area_number} = a ->
          %{a | armies: a.armies + delta, pending_armies: a.pending_armies + delta}

        a ->
          a
      end)

    players =
      Enum.map(view.players, fn
        %{number: ^viewer} = p -> %{p | unassigned_armies: p.unassigned_armies - delta}
        p -> p
      end)

    %{view | areas: areas, players: players}
  end

  @doc "Optimistic local copy of a just-submitted order on the viewer's own area."
  def put_order(view, area_number, order) do
    areas =
      Enum.map(view.areas, fn
        %{number: ^area_number} = a -> %{a | order: order}
        a -> a
      end)

    %{view | areas: areas}
  end

  @doc """
  Brings the Undo history (newest first, `{area_number, amount}`) back in line
  with what is actually queued. Entries are trimmed to each own area's
  `pending_armies` — an Unassign from the order panel, or a new turn, simply
  empties them — and anything queued that the history doesn't account for
  (placed before a reconnect) joins as its oldest entries, so Undo can always
  walk back every reinforcement placed this turn.
  """
  def reconcile_history(history, view) do
    pending =
      for a <- view.areas, own_area?(view, a), a.pending_armies > 0, into: %{} do
        {a.number, a.pending_armies}
      end

    {kept, unaccounted} =
      Enum.reduce(history, {[], pending}, fn {area, amount}, {kept, left} ->
        case min(amount, Map.get(left, area, 0)) do
          0 -> {kept, left}
          take -> {[{area, take} | kept], Map.update!(left, area, &(&1 - take))}
        end
      end)

    Enum.reverse(kept) ++ for({area, n} <- Enum.sort(unaccounted), n > 0, do: {area, n})
  end

  defp find_area(view, number), do: Enum.find(view.areas, &(&1.number == number))

  defp armies(1), do: "1 army"
  defp armies(n), do: "#{n} armies"

  defp orders(1), do: "1 order"
  defp orders(n), do: "#{n} orders"
end

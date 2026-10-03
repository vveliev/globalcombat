defmodule GlobalCombatWeb.GameLive.Hud do
  @moduledoc """
  The game HUD's own logic, kept out of `GameLive` (`docs/mobile-battle-mode.md`
  §8): where the viewer is in the turn and how that is worded, End Turn's
  progress ring, the lens button, and the bookkeeping behind tap-to-place —
  the optimistic local copy of a placement and the Undo history.

  Everything here is a pure function of a `GlobalCombat.Games.PlayerView` (and,
  where it matters, the viewer's own entry in `view.players`, which `GameLive`
  already looks up once per render). Nothing talks to the game server.
  """

  alias GlobalCombatWeb.GameLive.WorldMap

  @lenses [:owner, :region, :frontier]

  @doc "True when `area` is visible to, and owned by, the seated viewer."
  def own_area?(view, area),
    do:
      area.visible and not is_nil(view.viewer_number) and area.owner_number == view.viewer_number

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

  @doc "The dock's one sentence on what to do next."
  def coach_line(view, me) do
    case turn_phase(view, me) do
      :watching -> nil
      :done -> "Orders locked in. The turn runs once everyone has ended theirs."
      {:place, n} -> "Tap your territories to place #{armies(n)} · hold for +5"
      {:orders, 0} -> "Drag an army token onto a neighbour to attack or move"
      {:orders, n} -> "#{orders(n)} ready · tap an arrow to change it"
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

  defp armies(1), do: "1 army"
  defp armies(n), do: "#{n} armies"

  defp orders(1), do: "1 order"
  defp orders(n), do: "#{n} orders"
end

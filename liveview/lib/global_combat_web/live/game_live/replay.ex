defmodule GlobalCombatWeb.GameLive.Replay do
  @moduledoc """
  Builds the "last turn" replay steps from `PlayerView.last_turn_events` —
  already fog-filtered by `PlayerView.build/3`, so every event handed to `steps/4` is
  safe to narrate, draw, and count in full for this viewer.

  Each step is a plain, JSON-ready map (`Jason.encode!/1`) consumed three ways: the
  board's `world-map-replay` SVG layer (`GameLive.WorldMap`) draws an arrow between
  `from`/`to` for `:attack`/`:transfer` steps and a halo pulse when `captured`, the
  accessible ordered list renders `text` for every step, and the colocated
  `.TurnReplay` hook (`GameLive`) reads the same JSON to drive stepwise reveal,
  the live-region announcement, and the running army-count overlay from `counts`.

  `counts` is a best-effort *running* army count for the areas a step touches,
  back-computed from each area's currently-known (fog-filtered) final count and the
  deltas every later event in the same turn applied to it. This is exact whenever
  every event touching that area this turn is itself visible to this viewer; if fog
  hid an earlier event on an area that only became visible later in the turn, the
  running count for its earlier steps is left off entirely (never guessed) — see
  `resolve_running/2`. A capture resets the chain: the pre-capture defender's count
  belonged to a different owner's pool entirely, not a delta of the post-capture
  survivor count, so nothing before a capture step is ever backfilled past it.
  """

  alias GlobalCombatWeb.GameLive.MapGeometry, as: Geometry

  @doc "Builds the ordered replay steps for one turn's (already fog-filtered) events."
  def steps(events, areas, players, map_name) do
    areas_by_number = Map.new(areas, &{&1.number, &1})
    player_names = Map.new(players, &{&1.number, &1.name})
    running = running_totals(events, areas_by_number)

    events
    |> Enum.with_index()
    |> Enum.map(fn {event, index} ->
      build_step(event, index, areas_by_number, player_names, map_name, running)
    end)
  end

  defp build_step(event, index, areas_by_number, player_names, map_name, running) do
    %{
      index: index,
      kind: kind(event),
      text: describe(event, areas_by_number, player_names),
      from: endpoint(from_area(event), map_name),
      to: endpoint(to_area(event), map_name),
      captured: captured?(event),
      counts: counts_at(event, index, running)
    }
  end

  defp kind({:assign, _, _}), do: :assign
  defp kind({:transfer, _, _, _}), do: :transfer
  defp kind({:attack, _, _, _, _, _, _}), do: :attack
  defp kind({:eliminated, _}), do: :eliminated
  defp kind({:ended, _}), do: :ended

  defp from_area({:transfer, from, _to, _amount}), do: from

  defp from_area({:attack, from, _to, _amount, _attacker_lost, _defender_lost, _captured?}),
    do: from

  defp from_area(_event), do: nil

  defp to_area({:transfer, _from, to, _amount}), do: to
  defp to_area({:attack, _from, to, _amount, _attacker_lost, _defender_lost, _captured?}), do: to
  defp to_area(_event), do: nil

  defp captured?({:attack, _from, _to, _amount, _attacker_lost, _defender_lost, captured?}),
    do: captured?

  defp captured?(_event), do: false

  defp endpoint(nil, _map_name), do: nil

  defp endpoint(area_number, map_name) do
    {x, y} = Geometry.label(map_name, area_number)
    %{area: area_number, x: x, y: y}
  end

  defp counts_at(event, index, running) do
    event
    |> event_area_numbers()
    |> Enum.flat_map(fn area_number ->
      case get_in(running, [area_number, index]) do
        nil -> []
        value -> [%{area: area_number, value: value}]
      end
    end)
  end

  defp event_area_numbers({:assign, area, _amount}), do: [area]
  defp event_area_numbers({:transfer, from, to, _amount}), do: [from, to]
  defp event_area_numbers({:attack, from, to, _amount, _al, _dl, _c}), do: [from, to]
  defp event_area_numbers({:eliminated, _player}), do: []
  defp event_area_numbers({:ended, _winner}), do: []

  # --- narration ------------------------------------------------------------

  defp describe({:assign, area, amount}, areas_by_number, _player_names) do
    "#{area_name(area, areas_by_number)} received #{armies_text(amount)}."
  end

  defp describe({:transfer, from, to, amount}, areas_by_number, _player_names) do
    "#{area_name(from, areas_by_number)} sent #{armies_text(amount)} to " <>
      "#{area_name(to, areas_by_number)}."
  end

  defp describe(
         {:attack, from, to, amount, attacker_lost, defender_lost, captured?},
         areas_by_number,
         _player_names
       ) do
    outcome = if captured?, do: ", #{area_name(to, areas_by_number)} captured", else: ""

    "#{area_name(from, areas_by_number)} attacked #{area_name(to, areas_by_number)} " <>
      "with #{armies_text(amount)}: #{attacker_lost} lost, #{defender_lost} defenders lost#{outcome}"
  end

  defp describe({:eliminated, player}, _areas_by_number, player_names) do
    "#{player_name(player, player_names)} was eliminated."
  end

  defp describe({:ended, winner}, _areas_by_number, player_names) do
    "#{player_name(winner, player_names)} won the game."
  end

  defp area_name(number, areas_by_number), do: Map.fetch!(areas_by_number, number).name
  defp player_name(number, player_names), do: Map.get(player_names, number, "A player")

  defp armies_text(1), do: "1 army"
  defp armies_text(n), do: "#{n} armies"

  # --- running army counts ----------------------------------------------------

  defp running_totals(events, areas_by_number) do
    events
    |> Enum.with_index()
    |> Enum.flat_map(fn {event, index} ->
      Enum.map(deltas(event), fn {area, op} -> {area, index, op} end)
    end)
    |> Enum.group_by(fn {area, _index, _op} -> area end, fn {_area, index, op} -> {index, op} end)
    |> Map.new(fn {area, touches} ->
      final = areas_by_number[area] && areas_by_number[area].armies
      {area, resolve_running(touches, final)}
    end)
  end

  defp deltas({:assign, area, amount}), do: [{area, {:delta, amount}}]

  defp deltas({:transfer, from, to, amount}),
    do: [{from, {:delta, -amount}}, {to, {:delta, amount}}]

  defp deltas({:attack, from, to, amount, attacker_lost, _defender_lost, true}),
    do: [{from, {:delta, -amount}}, {to, {:pin, amount - attacker_lost}}]

  defp deltas({:attack, from, to, _amount, attacker_lost, defender_lost, false}),
    do: [{from, {:delta, -attacker_lost}}, {to, {:delta, -defender_lost}}]

  defp deltas(_event), do: []

  # `touches` is one area's own {index, op} pairs, already in resolution order
  # (Enum.group_by/3 preserves each value list's original relative order). Two
  # independent passes anchor a running value from either end, then `forward`
  # wins wherever both resolved something (a pin is only ever produced going
  # forward, and it's the one truth a backward, final-anchored walk can't see).
  defp resolve_running(touches, final) do
    indices = Enum.map(touches, fn {index, _op} -> index end)

    {forward, _} =
      Enum.reduce(touches, {%{}, nil}, fn {index, op}, {acc, running} ->
        running = apply_op(op, running)
        {Map.put(acc, index, running), running}
      end)

    backward =
      if final do
        {acc, _} =
          touches
          |> Enum.reverse()
          |> Enum.reduce({%{}, final}, fn {index, op}, {acc, running_after} ->
            {Map.put(acc, index, running_after), undo_op(op, running_after)}
          end)

        acc
      else
        %{}
      end

    Map.new(indices, fn index -> {index, forward[index] || Map.get(backward, index)} end)
  end

  defp apply_op({:pin, value}, _running), do: value
  defp apply_op({:delta, delta}, running), do: running && running + delta

  defp undo_op({:pin, _value}, _running_after), do: nil
  defp undo_op({:delta, delta}, running_after), do: running_after && running_after - delta
end

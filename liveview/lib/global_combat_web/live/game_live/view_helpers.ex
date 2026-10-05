defmodule GlobalCombatWeb.GameLive.ViewHelpers do
  @moduledoc """
  Small lookups over a `%GlobalCombat.Games.PlayerView{}` shared by `GlobalCombatWeb.GameLive`
  and the function-component modules it renders (`Dock`, `GameOver`, `PlayersList`, ...), plus
  the order-amount rules the order panel (`Dock`) and `GameLive`'s amount events must agree on.

  Everything here reads the already fog-of-war-filtered view only — nothing reaches the game
  server — so these are safe to call from templates as well as from event handlers.
  """

  alias GlobalCombatWeb.GameLive.Hud
  alias GlobalCombatWeb.GameLive.WorldMap

  @doc "The area numbered `number` in `view.areas`, or `nil`."
  def find_area(view, number), do: Enum.find(view.areas, &(&1.number == number))

  @doc "The viewer's own seat, or `nil` for a spectator (`viewer_number: nil`)."
  def my_player(view), do: Enum.find(view.players, &(&1.number == view.viewer_number))

  @doc """
  The most an order from area `selected` (to `target`, or an assignment when `nil`) can carry.
  Assign mode tops out at the viewer's unassigned pool; transfer and attack at what the source
  can actually send — the engine always leaves one army behind, so Max and a full slider never
  promise more than will go. `nil` when there is no such area or (assigning) no seat.
  """
  def order_limit(view, selected, target) do
    case {find_area(view, selected), target, my_player(view)} do
      {nil, _target, _me} -> nil
      {_source, nil, nil} -> nil
      {_source, nil, me} -> me.unassigned_armies
      {source, _target, _me} -> Hud.spare_armies(source)
    end
  end

  @doc "True when `area` has a live order queued to exactly `target`."
  def order_queued_to?(area, target),
    do: WorldMap.queued_order?(area) and area.order.target == target and not is_nil(target)

  @doc "The draft amount as a non-negative integer, or `-1` when it isn't one."
  def parse_amount(amount_str) do
    case Integer.parse(String.trim(to_string(amount_str))) do
      {amount, _} when amount >= 0 -> amount
      _ -> -1
    end
  end

  @doc """
  Player-facing ordinal ("1st place"), replacing the engine's bare `place` integer
  ("place 1") that used to leak straight into the UI — port of `Player.cs`'s `GetPlace()`.
  """
  def ordinal(n) when rem(n, 100) in 11..13, do: "#{n}th"

  def ordinal(n) do
    case rem(n, 10) do
      1 -> "#{n}st"
      2 -> "#{n}nd"
      3 -> "#{n}rd"
      _ -> "#{n}th"
    end
  end
end

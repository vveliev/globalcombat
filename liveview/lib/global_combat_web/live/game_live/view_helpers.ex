defmodule GlobalCombatWeb.GameLive.ViewHelpers do
  @moduledoc """
  Small lookups over a `%GlobalCombat.Games.PlayerView{}` shared by `GlobalCombatWeb.GameLive`
  and the function-component modules it renders (`Dock`, `GameOver`, `PlayersList`, ...).

  Everything here reads the already fog-of-war-filtered view only — nothing reaches the game
  server — so these are safe to call from templates as well as from event handlers.
  """

  @doc "The area numbered `number` in `view.areas`, or `nil`."
  def find_area(view, number), do: Enum.find(view.areas, &(&1.number == number))

  @doc "The viewer's own seat, or `nil` for a spectator (`viewer_number: nil`)."
  def my_player(view), do: Enum.find(view.players, &(&1.number == view.viewer_number))

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

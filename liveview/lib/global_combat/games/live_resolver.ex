defmodule GlobalCombat.Games.LiveResolver do
  @moduledoc """
  Production `GlobalCombat.Games.TurnScheduler.Resolver`. `GlobalCombat.Games.TurnScheduler` has
  already claimed `game`'s turn slot (advanced `prev_turn_time`/`last_turn_time`) by the time
  `resolve_turn/1` runs; this module hands the turn to the game's one
  `GlobalCombat.Games.Server` process (starting it from `games.serialized` if it isn't alive), so
  every turn — payouts, tourney bookkeeping, broadcasts — goes through the same code and a
  restarted process can never overwrite a turn resolved somewhere else.
  """

  @behaviour GlobalCombat.Games.TurnScheduler.Resolver

  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Server
  alias GlobalCombat.Games.Supervisor, as: GamesSupervisor

  @impl true
  def resolve_turn(%GamesDb.Game{} = game) do
    case GamesSupervisor.ensure_started(game.id) do
      :ok -> Server.run_scheduled_turn(game.id, game.last_turn_time, game.prev_turn_time)
      {:error, _} -> {:error, {:no_persisted_state, game.id}}
    end
  end
end

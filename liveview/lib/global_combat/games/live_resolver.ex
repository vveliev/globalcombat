defmodule GlobalCombat.Games.LiveResolver do
  @moduledoc """
  Production `GlobalCombat.Games.TurnScheduler.Resolver` (GIF-74) — the bridge the scheduler's
  own moduledoc says doesn't exist yet. `GlobalCombat.Games.TurnScheduler` has already claimed
  `game`'s turn slot (advanced `turn`/`prev_turn_time`/`last_turn_time`) by the time
  `resolve_turn/1` runs; this module's only job is making the actual `GlobalCombat.Engine.Game`
  turn happen and land back in `games.serialized`:

    * If a `GlobalCombat.Games.Server` process is already running this game (the common case —
      the node hasn't restarted since), hand off to it via `Server.run_scheduled_turn/2` so the
      live process (and every LiveView subscribed to it) sees the same turn the scheduler forced,
      instead of two independent copies of this game's state silently diverging.
    * Otherwise (the node restarted between the last turn and this claim, or this game outlived
      its process for any other reason), rehydrate the last snapshot straight from
      `games.serialized` and run the turn without spinning up a whole `Server` just to persist
      its result and throw it away — `GlobalCombat.Games.Supervisor` will pick this game back up
      into a live process on its own next boot-time sweep regardless.
  """

  @behaviour GlobalCombat.Games.TurnScheduler.Resolver

  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.Wire
  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Live, as: GamesLive
  alias GlobalCombat.Games.Server
  alias GlobalCombat.GrpcHost

  @impl true
  def resolve_turn(%GamesDb.Game{} = game) do
    if GamesLive.game_exists?(game.id) do
      Server.run_scheduled_turn(game.id, game.last_turn_time)
    else
      resolve_offline(game)
    end
  end

  defp resolve_offline(%{serialized: nil, id: id}) do
    {:error, {:no_persisted_state, id}}
  end

  defp resolve_offline(%{serialized: serialized} = game) do
    wire = GrpcHost.Game.decode(serialized)
    rng = DotnetRandom.new(:erlang.unique_integer())
    %{engine: engine} = Wire.from_wire_snapshot(wire, rng)

    engine = Engine.run_turn(engine)

    resolved_wire =
      Wire.to_wire_game(engine,
        game_id: game.id,
        turn_length_minutes: game.turn_length,
        max_players: Map.fetch!(wire, :MaxPlayers),
        is_fogged: Map.fetch!(wire, :IsFogged)
      )

    GamesDb.persist_serialized(game.id, GrpcHost.Game.encode(resolved_wire))
    if engine.ended, do: GamesDb.finish_game(game.id)

    :ok
  end
end

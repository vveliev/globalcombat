defmodule GlobalCombat.Games.ServerTest do
  use GlobalCombat.DataCase, async: true

  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.Game.{Area, Player}
  alias GlobalCombat.Engine.Wire
  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Game
  alias GlobalCombat.Games.Server
  alias GlobalCombat.GrpcHost

  describe "rehydrate_from: — boot-time reconstruction (GIF-74)" do
    test "starts straight into :playing with the persisted engine state, not an empty lobby" do
      game_id = System.unique_integer([:positive])
      serialized = serialized_engine(turn: 5)

      {:ok, _pid} =
        Server.start_link(
          game_id: game_id,
          rehydrate_from: serialized,
          turn_length_minutes: 30,
          last_turn_time: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:playing, view} = Server.player_view(game_id, 101)
      assert view.turn == 5
      assert Enum.map(view.players, & &1.name) |> Enum.sort() == ["Alice", "Bob"]
    end

    test "a scheduled turn run afterward persists back to the same games row it was rehydrated from" do
      serialized = serialized_engine(turn: 5)

      game =
        %Game{status: :active, private: false, turn_length: 30, serialized: serialized}
        |> Repo.insert!()

      {:ok, game} = GamesDb.mark_active(game)

      {:ok, _pid} =
        Server.start_link(
          game_id: game.id,
          rehydrate_from: game.serialized,
          turn_length_minutes: 30,
          last_turn_time: game.last_turn_time,
          callers: [self() | Process.get(:"$callers", [])]
        )

      assert :ok = Server.run_scheduled_turn(game.id, game.last_turn_time)

      persisted = GamesDb.get_game!(game.id)
      decoded = GrpcHost.Game.decode(persisted.serialized)
      assert Map.fetch!(decoded, :Turn) == 6
    end
  end

  # A real, runnable two-player engine state (both alive, one area each on :original) encoded
  # exactly like `GlobalCombat.Games.Server.persist_snapshot/1` would have written it.
  defp serialized_engine(opts) do
    engine = %Engine{
      map_name: :original,
      rng: DotnetRandom.new(3),
      turn: Keyword.fetch!(opts, :turn),
      is_non_random: true,
      minimum_armies: 3,
      areas: %{
        1 => %Area{number: 1, owner_number: 1, armies: 8},
        2 => %Area{number: 2, owner_number: 2, armies: 6}
      },
      players: %{
        1 => %Player{number: 1, account_id: 101, name: "Alice", areas: 1, armies: 8},
        2 => %Player{number: 2, account_id: 102, name: "Bob", areas: 1, armies: 6}
      }
    }

    wire =
      Wire.to_wire_game(engine,
        game_id: 0,
        turn_length_minutes: 30,
        max_players: 2,
        is_fogged: false
      )

    GrpcHost.Game.encode(wire)
  end
end

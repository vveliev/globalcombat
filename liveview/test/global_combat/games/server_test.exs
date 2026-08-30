defmodule GlobalCombat.Games.ServerTest do
  use GlobalCombat.DataCase, async: true

  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.Game.{Area, Player}
  alias GlobalCombat.Engine.Wire
  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Game
  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombat.Games.Server
  alias GlobalCombat.GrpcHost

  describe "training mode: the Computer opponent takes its turn on its own (GIF-104)" do
    test "the Computer seat is Done the instant its turn starts, never left Thinking forever" do
      game_id =
        Games.create_game(%{map_name: :original, is_training: true, minimum_armies: 3})

      {:ok, 1} = Games.join(game_id, 101, "Alice")
      {:ok, 2} = Games.join(game_id, 1, "Computer")
      :ok = Games.start_game(game_id, 101)

      {:playing, view} = Games.player_view(game_id, 101)
      computer = Enum.find(view.players, &(&1.name == "Computer"))
      refute is_nil(computer)
      assert computer.done
    end

    test "a solo human finishes a turn with no Force Turn, because the Computer never blocks all_done?" do
      game_id =
        Games.create_game(%{map_name: :original, is_training: true, minimum_armies: 3})

      {:ok, 1} = Games.join(game_id, 101, "Alice")
      {:ok, 2} = Games.join(game_id, 1, "Computer")
      :ok = Games.start_game(game_id, 101)

      {:playing, before_turn} = Games.player_view(game_id, 101)
      assert before_turn.turn == 1

      :ok = Games.set_done(game_id, 101)

      {:playing, after_turn} = Games.player_view(game_id, 101)
      assert after_turn.turn == 2

      computer = Enum.find(after_turn.players, &(&1.name == "Computer"))
      assert computer.done
    end
  end

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

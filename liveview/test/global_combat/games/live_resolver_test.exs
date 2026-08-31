defmodule GlobalCombat.Games.LiveResolverTest do
  use GlobalCombat.DataCase, async: true

  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.Game.{Area, Player}
  alias GlobalCombat.Engine.Wire
  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Game
  alias GlobalCombat.Games.Live, as: GamesLive
  alias GlobalCombat.Games.LiveResolver
  alias GlobalCombat.Games.Scheduling
  alias GlobalCombat.Games.Server
  alias GlobalCombat.GrpcHost

  describe "resolve_turn/1 — a live GlobalCombat.Games.Server is running for this game" do
    test "hands the claimed turn to Server.run_scheduled_turn/2 instead of resolving it separately" do
      game_id = GamesLive.create_game(%{max_players: 2, turn_length_minutes: 60})
      assert {:ok, 1} = GamesLive.join(game_id, 101, "Alice")
      assert {:ok, 2} = GamesLive.join(game_id, 102, "Bob")
      assert :ok = GamesLive.start_game(game_id, 101)

      game = GamesDb.get_game!(game_id)
      assert {:ok, claimed} = Scheduling.claim_turn(game)

      assert :ok = LiveResolver.resolve_turn(claimed)

      persisted = GamesDb.get_game!(game_id)
      assert persisted.turn == 2

      decoded = GrpcHost.Game.decode(persisted.serialized)
      assert Map.fetch!(decoded, :Turn) == 2
    end
  end

  describe "resolve_turn/1 — no live process for this game (offline rehydrate + run)" do
    test "rehydrates from games.serialized, runs the turn directly, and persists the result" do
      game = active_game_fixture()
      # Server.alive?/1, not GamesLive.game_exists?/1 — the latter now rehydrates on demand
      # (GIF-119), which would defeat this test's "no live process yet" precondition by
      # starting one as a side effect of merely checking it.
      refute Server.alive?(game.id)

      assert :ok = LiveResolver.resolve_turn(game)

      persisted = GamesDb.get_game!(game.id)
      assert persisted.status == :active

      decoded = GrpcHost.Game.decode(persisted.serialized)
      assert Map.fetch!(decoded, :Turn) == 2
    end

    test "marks the game :finished once run_turn/1 ends it (one player left)" do
      game = active_game_fixture(down_to_last_player: true)

      assert :ok = LiveResolver.resolve_turn(game)

      persisted = GamesDb.get_game!(game.id)
      assert persisted.status == :finished

      decoded = GrpcHost.Game.decode(persisted.serialized)
      assert Map.fetch!(decoded, :Ended) == true
    end

    test "errors instead of raising when there's no persisted state to rehydrate from" do
      game = %Game{status: :new, private: false, turn_length: 60} |> Repo.insert!()
      {:ok, game} = GamesDb.mark_active(game)

      assert {:error, {:no_persisted_state, id}} = LiveResolver.resolve_turn(game)
      assert id == game.id
    end
  end

  # Builds and persists a `games` row whose `serialized` blob is a real, runnable engine state
  # (two players each owning one area on the :original map) — enough for
  # `GlobalCombat.Engine.Game.run_turn/1` to complete a full reinforcement/elimination pass, not
  # just decode. `down_to_last_player: true` starts player 2 already at zero areas, so this
  # turn's `resolve_reinforcements_and_eliminations/1` eliminates them and ends the game.
  defp active_game_fixture(opts \\ []) do
    down_to_last_player? = Keyword.get(opts, :down_to_last_player, false)

    engine = %Engine{
      map_name: :original,
      rng: DotnetRandom.new(7),
      turn: 1,
      is_non_random: true,
      reverse_attack_order: false,
      minimum_armies: 3,
      is_training: true,
      ended: false,
      areas: %{
        1 => %Area{number: 1, owner_number: 1, armies: 5, assigned_armies: 0, command: :none},
        2 => %Area{number: 2, owner_number: 2, armies: 5, assigned_armies: 0, command: :none}
      },
      players: %{
        1 => %Player{number: 1, account_id: 101, name: "Alice", areas: 1, armies: 5},
        2 => %Player{
          number: 2,
          account_id: 102,
          name: "Bob",
          areas: if(down_to_last_player?, do: 0, else: 1),
          armies: if(down_to_last_player?, do: 0, else: 5)
        }
      }
    }

    wire =
      Wire.to_wire_game(engine,
        game_id: 0,
        turn_length_minutes: 60,
        max_players: 2,
        is_fogged: false
      )

    game =
      %Game{
        status: :active,
        private: false,
        turn_length: 60,
        serialized: GrpcHost.Game.encode(wire)
      }
      |> Repo.insert!()

    {:ok, game} = GamesDb.mark_active(game)
    game
  end
end

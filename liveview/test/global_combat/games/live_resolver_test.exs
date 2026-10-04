defmodule GlobalCombat.Games.LiveResolverTest do
  use GlobalCombat.DataCase, async: true

  alias GlobalCombat.Accounts
  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.Game.{Area, Player}
  alias GlobalCombat.Engine.MapInfo
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
      # Server.alive?/1, not GamesLive.game_exists?/1 — the latter now rehydrates on demand,
      # which would defeat this test's "no live process yet" precondition by
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

    test "in a training game, the Computer queues its orders for the next turn and is done" do
      game = active_game_fixture(computer_opponent: true)

      assert :ok = LiveResolver.resolve_turn(game)

      persisted = GamesDb.get_game!(game.id)
      wire = GrpcHost.Game.decode(persisted.serialized)
      %{engine: engine} = Wire.from_wire_snapshot(wire, DotnetRandom.new(1))

      computer = Engine.player!(engine, 2)
      assert computer.done
      # The reinforcements it just received went straight onto its only area.
      assert computer.unassigned_armies == 0
      assert Engine.area!(engine, 2).assigned_armies > 0
      refute Engine.player!(engine, 1).done
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

    computer_opponent? = Keyword.get(opts, :computer_opponent, false)
    bob_account_id = if computer_opponent?, do: Accounts.computer_account_id(), else: 102

    # The Computer's `RandomAi` picks targets from real map neighbours, so that variant needs a
    # whole board: Bob keeps area 2, Alice holds every other area.
    alice_areas =
      if computer_opponent?,
        do: for(n <- 1..MapInfo.num_areas(:original), n != 2, do: n),
        else: [1]

    areas =
      Map.new([{2, 2} | Enum.map(alice_areas, &{&1, 1})], fn {number, owner} ->
        {number,
         %Area{number: number, owner_number: owner, armies: 5, assigned_armies: 0, command: :none}}
      end)

    engine = %Engine{
      map_name: :original,
      rng: DotnetRandom.new(7),
      turn: 1,
      is_non_random: true,
      reverse_attack_order: false,
      minimum_armies: 3,
      is_training: true,
      ended: false,
      areas: areas,
      players: %{
        1 => %Player{
          number: 1,
          account_id: 101,
          name: "Alice",
          areas: length(alice_areas),
          armies: 5 * length(alice_areas)
        },
        2 => %Player{
          number: 2,
          account_id: bob_account_id,
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

defmodule GlobalCombat.Games.ServerTest do
  use GlobalCombat.DataCase, async: true

  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.Game.{Area, Player}
  alias GlobalCombat.Engine.Wire
  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Game
  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombat.Games.Server
  alias GlobalCombat.GrpcHost
  alias GlobalCombat.Tourneys

  describe "GIF-116: engine.ended wires into Tourneys.finish_game/2" do
    test "a tourney game ending through the live Server advances the winner into the next round" do
      {:ok, tourney} =
        Tourneys.create_tourney(%{
          "name" => "GIF-116 Cup #{System.unique_integer([:positive])}",
          "initial_games" => 2,
          "game_size" => 2,
          "winners" => 1,
          "auto_start" => true
        })

      {tourney, :started} =
        Enum.reduce(for(_ <- 1..4, do: account_fixture()), {tourney, nil}, fn account,
                                                                               {tourney, _} ->
          {:ok, outcome} = Tourneys.join_tournament(tourney, account.id)
          {Tourneys.get_tourney!(tourney.id), outcome}
        end)

      [round_one_game | _] =
        tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 1))

      [loser, winner] = round_one_game.game.game_players

      end_game_through_server(round_one_game.game_id,
        winner_account_id: winner.account_id,
        loser_account_id: loser.account_id
      )

      # Confirmed live on a real bracket (GIF-116): before this fix, nothing outside tests
      # ever called Tourneys.finish_game/2, so a finished round-1 game left round 2 sitting at
      # `:new` with zero seated game_players forever. `run_turn/2`'s `engine.ended` branch now
      # calls it, so the winner should already be seated once the turn that ends the game
      # finishes running -- no manual `Tourneys.finish_game/2` call from the test.
      round_two = tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 2))
      assert [round_two_game] = round_two

      seated = round_two_game.game.game_players |> Enum.map(& &1.account_id) |> MapSet.new()
      assert MapSet.member?(seated, winner.account_id)
      refute MapSet.member?(seated, loser.account_id)

      persisted_game = GamesDb.get_game!(round_one_game.game_id)
      assert persisted_game.status == :finished
    end
  end

  # Rigs a 2-player engine one turn away from ending (the loser already at 0 areas) inside the
  # `Games.Server` the tourney bracket seeding (GIF-115) already started for `game_id` — a real
  # fought-out game would exercise the same `run_turn/2` `engine.ended` branch, just via many
  # more turns of combat RNG this doesn't need to reproduce to prove the bracket-advancement
  # wiring itself.
  defp end_game_through_server(game_id, winner_account_id: winner_id, loser_account_id: loser_id) do
    engine = %Engine{
      map_name: :original,
      rng: DotnetRandom.new(1),
      turn: 3,
      minimum_armies: 3,
      areas: %{1 => %Area{number: 1, owner_number: 1, armies: 5}},
      players: %{
        1 => %Player{number: 1, account_id: winner_id, name: "winner", areas: 1, armies: 5},
        2 => %Player{
          number: 2,
          account_id: loser_id,
          name: "loser",
          areas: 0,
          armies: 0,
          done: true
        }
      }
    }

    :sys.replace_state(Server.via(game_id), fn state ->
      %{
        state
        | status: :playing,
          engine: engine,
          players: [
            {1, %{account_id: winner_id, name: "winner"}},
            {2, %{account_id: loser_id, name: "loser"}}
          ],
          turn_started_at: DateTime.utc_now(),
          db_last_turn_time: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    end)

    :ok = Server.set_done(game_id, winner_id)
    # Synchronizes on the cast above: a GenServer processes messages from the same sender in
    # the order they were sent, so this call only returns once `set_done`'s `run_turn/2` (and
    # therefore the `Tourneys.finish_game/2` call under test) has already completed.
    assert {:playing, view} = Server.player_view(game_id, winner_id)
    assert view.turn == 4
  end

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

  describe "new_engine/1 — initial reinforcement bonus (GIF-105)" do
    test "a fresh turn-1 engine folds the unplaced reinforcement pool into Player.armies, matching .NET's Start()" do
      state = %Server{
        map_name: :original,
        is_training: true,
        is_non_random: false,
        reverse_attack_order: false,
        minimum_armies: 3,
        players: [
          {1, %{account_id: 101, name: "qatestlv1"}},
          {2, %{account_id: nil, name: "Computer"}}
        ]
      }

      engine = Server.new_engine(state)

      # :original has 42 areas, so both players of 2 split evenly (21 each) and both
      # qualify for Game.cs Start()'s "didn't get an extra area" +5 bonus: 20 base + 5 =
      # 25 unassigned, folded into armies as 21 * 5 + 25 = 130 — the .NET total from the
      # issue's Game #751211 repro, not the pre-fix 105 (areas * 5 with no pool folded in).
      for player <- Engine.players_in_order(engine) do
        assert player.areas == 21
        assert player.unassigned_armies == 25
        assert player.armies == 130
      end
    end

    test "a player who lands only the base per-player share (no remainder area) still gets the +5 bonus, others don't" do
      state = %Server{
        map_name: :original,
        is_training: false,
        is_non_random: false,
        reverse_attack_order: false,
        minimum_armies: 3,
        players: for(n <- 1..4, do: {n, %{account_id: n, name: "p#{n}"}})
      }

      engine = Server.new_engine(state)

      # 42 areas / 4 players = 10 base each with 2 left over; round-robin dealing hands
      # those 2 extras to players 1 and 2 (11 areas, no bonus), leaving 3 and 4 at the
      # base 10 areas (bonus applies).
      by_number = Map.new(Engine.players_in_order(engine), &{&1.number, &1})

      assert by_number[1].areas == 11
      assert by_number[1].unassigned_armies == 20
      assert by_number[1].armies == 11 * 5 + 20

      assert by_number[3].areas == 10
      assert by_number[3].unassigned_armies == 25
      assert by_number[3].armies == 10 * 5 + 25
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

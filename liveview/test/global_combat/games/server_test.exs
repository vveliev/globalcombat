defmodule GlobalCombat.Games.ServerTest do
  use GlobalCombat.DataCase, async: true

  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Accounts
  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.Game.{Area, Player}
  alias GlobalCombat.Engine.Wire
  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Game
  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombat.Games.Server
  alias GlobalCombat.Games.Supervisor, as: GamesSupervisor
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

  # deal_areas/2's round-robin on :original (42 areas) gives a 2-player game player 1
  # every odd-numbered area, player 2 every even one. Area 1 links to [2, 3, 37]
  # (`MapInfo.areas(:original)`), so area 1 <-> area 3 is an owned-adjacent pair for
  # transfer, area 1 <-> area 2 is an owned-vs-enemy adjacent pair for attack, and
  # area 1 <-> area 4 is an owned-vs-enemy *non-adjacent* pair for the fog/adjacency
  # no-op cases below.
  describe "order setters — assign/unassign/transfer/attack (GIF-111)" do
    defp start_two_player_original(opts \\ %{}) do
      game_id =
        Games.create_game(Map.merge(%{map_name: :original, max_players: 2}, opts))

      {:ok, 1} = Games.join(game_id, 101, "Alice")
      {:ok, 2} = Games.join(game_id, 102, "Bob")
      :ok = Games.start_game(game_id, 101)
      game_id
    end

    defp area(view, number), do: Enum.find(view.areas, &(&1.number == number))
    defp player(view, number), do: Enum.find(view.players, &(&1.number == number))

    test "assign moves armies from the caller's unassigned pool onto an owned area" do
      game_id = start_two_player_original()

      {:playing, before} = Games.player_view(game_id, 101)
      assert area(before, 1).armies == 5
      assert player(before, 1).unassigned_armies == 25

      Games.assign(game_id, 101, 1, 5)

      {:playing, view} = Games.player_view(game_id, 101)
      assert area(view, 1).armies == 10
      assert area(view, 1).pending_armies == 5
      assert player(view, 1).unassigned_armies == 20
    end

    test "assign is a silent no-op on an area the caller doesn't own" do
      game_id = start_two_player_original()
      {:playing, before} = Games.player_view(game_id, 101)
      assert area(before, 2).owner_number == 2

      Games.assign(game_id, 101, 2, 5)

      {:playing, view} = Games.player_view(game_id, 101)
      assert area(view, 2) == area(before, 2)
      assert player(view, 1).unassigned_armies == player(before, 1).unassigned_armies
    end

    test "unassign returns a pending assignment to the caller's pool" do
      game_id = start_two_player_original()
      Games.assign(game_id, 101, 1, 5)

      Games.unassign(game_id, 101, 1)

      {:playing, view} = Games.player_view(game_id, 101)
      assert area(view, 1).armies == 5
      assert area(view, 1).pending_armies == 0
      assert player(view, 1).unassigned_armies == 25
    end

    test "transfer queues armies to move between two owned, adjacent areas, resolved on turn run" do
      game_id = start_two_player_original()

      Games.transfer(game_id, 101, 1, 3, 2)
      :ok = Games.set_done(game_id, 101)
      :ok = Games.set_done(game_id, 102)

      {:playing, view} = Games.player_view(game_id, 101)
      assert view.turn == 2
      assert area(view, 1).armies == 3
      assert area(view, 3).armies == 7
    end

    test "transfer is a silent no-op when the caller doesn't own both areas" do
      game_id = start_two_player_original()

      Games.transfer(game_id, 101, 1, 2, 2)
      :ok = Games.set_done(game_id, 101)
      :ok = Games.set_done(game_id, 102)

      {:playing, view} = Games.player_view(game_id, 101)
      assert area(view, 1).armies == 5
      assert area(view, 2).owner_number == 2
    end

    test "attack queues a strike against an adjacent enemy area, resolved deterministically (IsNonRandom) on turn run" do
      game_id = start_two_player_original(%{is_non_random: true})

      Games.attack(game_id, 101, 1, 2, 4)
      :ok = Games.set_done(game_id, 101)
      :ok = Games.set_done(game_id, 102)

      {:playing, view} = Games.player_view(game_id, 101)
      assert view.turn == 2
      # attack_damage = trunc(4 * 0.6) = 2, defend_damage = trunc(5 * 0.75) = 3;
      # not decisive (2 < defender's 5 armies), so both sides take their damage.
      assert area(view, 1).armies == 2
      assert area(view, 2).armies == 3
      assert area(view, 2).owner_number == 2
    end

    test "attack is a silent no-op against a target the caller already owns" do
      game_id = start_two_player_original()

      Games.attack(game_id, 101, 1, 3, 2)
      :ok = Games.set_done(game_id, 101)
      :ok = Games.set_done(game_id, 102)

      {:playing, view} = Games.player_view(game_id, 101)
      assert area(view, 1).armies == 5
      assert area(view, 3).armies == 5
    end

    test "attack is a silent no-op against a non-adjacent enemy area" do
      game_id = start_two_player_original()
      {:playing, before} = Games.player_view(game_id, 101)
      refute 4 in area(before, 1).adjacent

      Games.attack(game_id, 101, 1, 4, 2)
      :ok = Games.set_done(game_id, 101)
      :ok = Games.set_done(game_id, 102)

      {:playing, view} = Games.player_view(game_id, 101)
      assert area(view, 1).armies == 5
      assert area(view, 4).armies == 5
      assert area(view, 4).owner_number == 2
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

  describe "game completion persists wins/games/rating to account (GIF-120)" do
    test "ending a non-training game updates the winner's wins/games and both players' rating, matching GameServer.OnEnd" do
      winner_account = account_fixture()
      loser_account = account_fixture()

      serialized =
        serialized_elimination_engine(winner_account.id, loser_account.id, is_training: false)

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

      # Player 2 already owns no areas going into this turn, so `resolve_reinforcements_and_
      # eliminations/1` eliminates them and — since only one player then remains alive — ends
      # the game in the same turn (mirrors `Game.EliminatePlayer`'s `Place <= 2` -> `End()`).
      assert :ok = Server.run_scheduled_turn(game.id, game.last_turn_time)

      persisted = GamesDb.get_game!(game.id)
      decoded = GrpcHost.Game.decode(persisted.serialized)
      assert Map.fetch!(decoded, :Ended)

      winner = Repo.get!(Accounts.Account, winner_account.id)
      loser = Repo.get!(Accounts.Account, loser_account.id)

      assert winner.wins == winner_account.wins + 1
      assert winner.games == winner_account.games + 1
      # The loser's `games` bump comes from `GameServer.OnEliminated`'s branch, not `OnEnd`'s —
      # they're eliminated (and their `games` incremented) the instant they hit 0 areas, which
      # in this two-player fixture happens in the same turn the game ends.
      assert loser.games == loser_account.games + 1
      assert loser.wins == loser_account.wins

      # Both players started at the same default rating (1200), so the Elo swing is symmetric.
      assert winner.rating == winner_account.rating + 75
      assert loser.rating == loser_account.rating - 75
    end

    test "a training game's completion leaves wins/games/rating untouched, matching GameServer's IsTraining gate" do
      winner_account = account_fixture()
      loser_account = account_fixture()

      serialized =
        serialized_elimination_engine(winner_account.id, loser_account.id, is_training: true)

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

      winner = Repo.get!(Accounts.Account, winner_account.id)
      loser = Repo.get!(Accounts.Account, loser_account.id)

      assert winner.wins == winner_account.wins
      assert winner.games == winner_account.games
      assert winner.rating == winner_account.rating
      assert loser.games == loser_account.games
      assert loser.rating == loser_account.rating
    end
  end

  describe "on-demand rehydration of a :finished game whose Server has died (GIF-124)" do
    test "ensure_started/1 rehydrates from games.serialized instead of reporting :not_found, and the read-only view still shows the final board" do
      winner_account = account_fixture()
      loser_account = account_fixture()

      serialized =
        serialized_elimination_engine(winner_account.id, loser_account.id, is_training: false)

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

      # Resolving this turn eliminates player 2 and, with only one player then left alive,
      # ends the game in the same turn — same fixture the GIF-120 tests above use.
      assert :ok = Server.run_scheduled_turn(game.id, game.last_turn_time)
      assert %{status: :finished} = GamesDb.get_game!(game.id)

      kill_server!(game.id)
      refute Server.alive?(game.id)

      assert :ok = GamesSupervisor.ensure_started(game.id)
      assert {:playing, view} = Server.player_view(game.id, winner_account.id)
      assert view.ended
      assert Enum.find(view.players, &(&1.number == 1)).place == 1
    end

    test "a :new (never-started) game with no persisted snapshot still reports not found" do
      game = %Game{status: :new, private: false} |> Repo.insert!()
      assert {:error, :not_found} = GamesSupervisor.ensure_started(game.id)
    end
  end

  # Unlike GlobalCombat.Games.LiveTest's same-named helper, this file's Server processes are
  # started directly via Server.start_link/1 (to exercise rehydrate_from: below the DynamicSupervisor
  # layer), not as GamesSupervisor children — so there's no supervised child to terminate_child/2,
  # just the bare pid to kill.
  defp kill_server!(game_id) do
    [{pid, _}] = Registry.lookup(GlobalCombat.Games.Registry, game_id)
    ref = Process.monitor(pid)
    # start_link/1 above links the Server to this test process, so an unlinked kill is needed
    # here — a plain Process.exit(pid, :kill) would otherwise take the test process down with it.
    Process.unlink(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    wait_until_deregistered(game_id)
  end

  defp wait_until_deregistered(game_id) do
    unless Registry.lookup(GlobalCombat.Games.Registry, game_id) == [] do
      wait_until_deregistered(game_id)
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

  # A two-player engine one turn from ending: player 2 already owns no areas, so running this
  # turn eliminates them (`Game.EliminatePlayer`) and, with only one player then left alive,
  # ends the game in the same turn (`Place <= 2` -> `End()`) — exercises both the winner's
  # wins/games bump and the rating award in one turn.
  defp serialized_elimination_engine(winner_account_id, loser_account_id, opts) do
    engine = %Engine{
      map_name: :original,
      rng: DotnetRandom.new(3),
      turn: 5,
      is_non_random: true,
      is_training: Keyword.get(opts, :is_training, false),
      minimum_armies: 3,
      areas: %{1 => %Area{number: 1, owner_number: 1, armies: 8}},
      players: %{
        1 => %Player{number: 1, account_id: winner_account_id, name: "Alice", areas: 1, armies: 8},
        2 => %Player{number: 2, account_id: loser_account_id, name: "Bob", areas: 0, armies: 0}
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

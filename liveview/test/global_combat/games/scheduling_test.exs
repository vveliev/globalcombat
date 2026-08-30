defmodule GlobalCombat.Games.SchedulingTest do
  use GlobalCombat.DataCase, async: true

  import GlobalCombat.GamesFixtures

  alias GlobalCombat.Games.Scheduling

  describe "list_due/1" do
    test "excludes a game with no turn_length (not scheduler-managed)" do
      game_fixture(%{status: :active, last_turn_time: minutes_ago(10)})

      assert Scheduling.list_due() == []
    end

    test "excludes a game that has never run a turn (no last_turn_time)" do
      game_fixture(%{status: :active, turn_length: 5})

      assert Scheduling.list_due() == []
    end

    test "excludes a non-active game even if its window has elapsed" do
      for status <- [:new, :finished] do
        game_fixture(%{status: status, turn_length: 5, last_turn_time: minutes_ago(10)})
      end

      assert Scheduling.list_due() == []
    end

    test "excludes an active game whose window has not elapsed" do
      game_fixture(%{status: :active, turn_length: 60, last_turn_time: minutes_ago(1)})

      assert Scheduling.list_due() == []
    end

    test "includes an active, scheduler-managed game past its turn window" do
      due = game_fixture(%{status: :active, turn_length: 5, last_turn_time: minutes_ago(10)})
      _not_due = game_fixture(%{status: :active, turn_length: 60, last_turn_time: minutes_ago(1)})

      assert [%{id: id}] = Scheduling.list_due()
      assert id == due.id
    end

    test "a game exactly at its deadline counts as due" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      last_turn_time = DateTime.add(now, -300, :second)
      game = game_fixture(%{status: :active, turn_length: 5, last_turn_time: last_turn_time})

      assert [%{id: id}] = Scheduling.list_due(now)
      assert id == game.id
    end
  end

  describe "claim_turn/2" do
    test "advances turn/prev_turn_time/last_turn_time and reports the winning claim" do
      last_turn_time = minutes_ago(10)

      game =
        game_fixture(%{
          status: :active,
          turn_length: 5,
          last_turn_time: last_turn_time,
          db_turn: 3
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      assert {:ok, claimed} = Scheduling.claim_turn(game, now)

      assert claimed.turn == 4
      assert claimed.prev_turn_time == last_turn_time
      assert claimed.last_turn_time == now

      reloaded = Repo.get!(GlobalCombat.Games.Game, game.id)
      assert reloaded.turn == 4
      assert reloaded.prev_turn_time == last_turn_time
      assert reloaded.last_turn_time == now
    end

    test "a second claim against the same stale struct is rejected (double-resolve guard)" do
      game = game_fixture(%{status: :active, turn_length: 5, last_turn_time: minutes_ago(10)})

      assert {:ok, _claimed} = Scheduling.claim_turn(game)
      assert {:error, :already_claimed} = Scheduling.claim_turn(game)
    end

    test "claiming with the freshly-returned struct succeeds again once its window elapses" do
      game = game_fixture(%{status: :active, turn_length: 5, last_turn_time: minutes_ago(10)})

      assert {:ok, claimed} = Scheduling.claim_turn(game, minutes_ago(6))
      assert {:ok, reclaimed} = Scheduling.claim_turn(claimed, minutes_ago(1))
      assert reclaimed.turn == claimed.turn + 1
    end
  end

  defp minutes_ago(n) do
    DateTime.utc_now() |> DateTime.add(-n * 60, :second) |> DateTime.truncate(:second)
  end
end

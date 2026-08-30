defmodule GlobalCombat.GamesTest do
  use GlobalCombat.DataCase, async: true

  import GlobalCombat.AccountsFixtures
  import GlobalCombat.GamesFixtures

  alias GlobalCombat.Games

  describe "list_new_games/0" do
    test "ports GameServer.GetNewGames — open, public games, most recent first" do
      open = game_fixture(%{game_name: "Open Game"})
      _private = game_fixture(%{game_name: "Private", is_private: true})
      _running = game_fixture(%{game_name: "Running", started: true})

      assert [%{id: id, name: "Open Game", status: :open}] = Games.list_new_games()
      assert id == open.id
    end
  end

  describe "list_player_games/2" do
    setup do
      %{account: account_fixture()}
    end

    test "default lists the account's accepted, still-open seats", %{account: account} do
      current = game_fixture(%{game_name: "Current", started: true}, [{account.id, []}])

      _finished =
        game_fixture(%{game_name: "Finished", started: true, ended: true}, [{account.id, []}])

      _not_mine = game_fixture(%{game_name: "Not mine"}, [{account_fixture().id, []}])

      assert [%{id: id, name: "Current"}] = Games.list_player_games(account.id)
      assert id == current.id
    end

    test "invites: true lists pending invites only", %{account: account} do
      invited = game_fixture(%{game_name: "Invited"}, [{account.id, [is_invite: true]}])
      _joined = game_fixture(%{game_name: "Joined"}, [{account.id, [is_invite: false]}])

      assert [%{id: id, name: "Invited"}] = Games.list_invited_games(account.id)
      assert id == invited.id
    end

    test "all_games: true includes finished games", %{account: account} do
      game_fixture(%{game_name: "Current", started: true}, [{account.id, []}])
      game_fixture(%{game_name: "Finished", started: true, ended: true}, [{account.id, []}])

      names = Games.list_player_games(account.id, all_games: true) |> Enum.map(& &1.name)
      assert Enum.sort(names) == ["Current", "Finished"]
    end
  end

  describe "GameSummary.from_row/1 status derivation" do
    test "mirrors Game.cs's Status computed property (not-started/running/ended)" do
      assert %{status: :open} = game_fixture() |> GlobalCombat.Games.GameSummary.from_row()

      assert %{status: :running} =
               game_fixture(%{started: true}) |> GlobalCombat.Games.GameSummary.from_row()

      assert %{status: :finished} =
               game_fixture(%{started: true, ended: true})
               |> GlobalCombat.Games.GameSummary.from_row()
    end

    test "falls back to 'Game #<id>' when GameName is blank, matching Game.Load's fallback" do
      game = game_fixture(%{game_name: ""})
      assert %{name: name} = GlobalCombat.Games.GameSummary.from_row(game)
      assert name == "Game ##{game.id}"
    end
  end

  describe "get_game!/1" do
    test "returns the row for a real id" do
      game = game_fixture()
      assert %{id: id} = Games.get_game!(game.id)
      assert id == game.id
    end

    test "raises for a missing id" do
      assert_raise Ecto.NoResultsError, fn -> Games.get_game!(-1) end
    end
  end

  describe "list_active_games/0" do
    test "only returns :active rows, for GIF-74 boot-time rehydration" do
      active = game_fixture(%{status: :active})
      _new = game_fixture(%{status: :new})
      _finished = game_fixture(%{status: :finished})

      assert [%{id: id}] = Games.list_active_games()
      assert id == active.id
    end
  end

  describe "persist_serialized/2" do
    test "overwrites serialized for the given game_id only" do
      game = game_fixture()
      other = game_fixture()

      assert :ok = Games.persist_serialized(game.id, "new-blob")

      assert Games.get_game!(game.id).serialized == "new-blob"
      assert Games.get_game!(other.id).serialized != "new-blob"
    end
  end

  describe "advance_turn/4" do
    test "sets turn/prev_turn_time/last_turn_time on the given row" do
      game = game_fixture(%{db_turn: 1, last_turn_time: minutes_ago(10)})
      prev = game.last_turn_time
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert :ok = Games.advance_turn(game.id, 2, prev, now)

      updated = Games.get_game!(game.id)
      assert updated.turn == 2
      assert updated.prev_turn_time == prev
      assert updated.last_turn_time == now
    end
  end

  describe "finish_game/1" do
    test "marks an active game :finished" do
      game = game_fixture(%{status: :active})
      assert :ok = Games.finish_game(game.id)
      assert Games.get_game!(game.id).status == :finished
    end

    test "is a no-op once already :finished (idempotent)" do
      game = game_fixture(%{status: :finished})
      assert :ok = Games.finish_game(game.id)
      assert Games.get_game!(game.id).status == :finished
    end
  end

  defp minutes_ago(n) do
    DateTime.utc_now() |> DateTime.add(-n * 60, :second) |> DateTime.truncate(:second)
  end
end

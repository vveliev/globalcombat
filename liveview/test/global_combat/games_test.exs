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
end

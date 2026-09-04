defmodule GlobalCombat.Games.LobbyPersistenceTest do
  @moduledoc """
  A lobby (a `Games.Server` before `start_game/2`) used to live only in process memory: a
  dev-server restart or a deploy left every open game as a `games` row with `serialized: nil`
  that rendered as "Game #N — 0/ players" on Home and answered "Game not found" on click.
  These tests pin the fix: the roster is mirrored into `games.serialized` (`Started: false`)
  and `game_players` on every change, rehydrates on demand, and an emptied lobby is deleted
  (port of `GameServer.KillGame`).
  """

  use GlobalCombat.DataCase, async: true

  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombat.Games.Registry, as: GamesRegistry
  alias GlobalCombat.Games.Supervisor, as: GamesSupervisor

  # Unique fixture names on purpose: `account.name` is unique, and two async test modules
  # inserting the same name at once deadlock on that index under MySQL (a real 1213 seen when
  # this file also used "Alice"/"Bob" alongside GameLiveTest).
  setup do
    %{alice: account_fixture(), bob: account_fixture()}
  end

  describe "a lobby is persisted from its first seat" do
    test "list_new_games/0 shows a real n/m player count for a joined lobby", %{alice: alice} do
      game_id = Games.create_game(%{max_players: 4, is_fogged: true})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)

      assert [%{id: ^game_id, status: :open, current_players: 1, max_players: 4, is_fogged: true}] =
               Enum.filter(GamesDb.list_new_games(), &(&1.id == game_id))
    end

    test "a lobby with no snapshot yet (mid-creation or a pre-fix orphan) is not listed" do
      {:ok, orphan} = GamesDb.create_game(%{status: :new, private: false})
      refute Enum.any?(GamesDb.list_new_games(), &(&1.id == orphan.id))
    end

    test "joining writes a game_players seat so the lobby is in the account's current games",
         %{alice: alice} do
      game_id = Games.create_game(%{max_players: 2})
      assert GamesDb.list_player_games(alice.id) == []

      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      assert [%{id: ^game_id}] = GamesDb.list_player_games(alice.id)
    end
  end

  describe "rehydrating a lobby after its process died" do
    test "player_view/2 comes back as the same :lobby with roster, options and invites intact",
         %{alice: alice, bob: bob} do
      game_id =
        Games.create_game(%{
          max_players: 3,
          map_name: :elements,
          is_fogged: true,
          minimum_armies: 5,
          is_private: true
        })

      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, _} = Games.invite(game_id, alice.id, bob.name)

      kill_server!(game_id)
      assert Games.game_exists?(game_id)

      assert {:lobby, view} = Games.player_view(game_id, alice.id)
      assert view.max_players == 3
      assert view.map_name == :elements
      assert view.is_fogged == true
      assert view.viewer_number == 1
      assert [%{number: 1, name: alice_name}] = view.players
      assert alice_name == alice.name

      # The pending invite survived too: Bob can join the private lobby, a stranger cannot.
      stranger = account_fixture()
      assert {:error, :not_invited} = Games.join(game_id, stranger.id, stranger.name)
      assert {:ok, 2} = Games.join(game_id, bob.id, bob.name)
    end

    test "a rehydrated lobby can still be started and played", %{alice: alice, bob: bob} do
      game_id = Games.create_game(%{max_players: 2, minimum_armies: 4})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)

      kill_server!(game_id)

      assert :ok = Games.start_game(game_id, alice.id)
      assert {:playing, view} = Games.player_view(game_id, alice.id)
      assert view.turn == 1
      assert %{status: :active} = GamesDb.get_game(game_id)
    end
  end

  describe "an emptied lobby is deleted (port of GameServer.KillGame)" do
    test "the last player quitting removes the games row, its seats, and the process",
         %{alice: alice, bob: bob} do
      game_id = Games.create_game(%{max_players: 2})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)

      :ok = Games.quit(game_id, bob.id)
      assert GamesDb.list_player_games(bob.id) == []

      assert [%{id: ^game_id, current_players: 1}] =
               Enum.filter(GamesDb.list_new_games(), &(&1.id == game_id))

      [{pid, _}] = Registry.lookup(GamesRegistry, game_id)
      ref = Process.monitor(pid)
      :ok = Games.quit(game_id, alice.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert GamesDb.get_game(game_id) == nil
      assert GamesDb.list_player_games(alice.id) == []
      assert {:error, :not_found} = Games.player_view(game_id, alice.id)
    end

    test "kicking a player drops their seat row but keeps the lobby", %{alice: alice, bob: bob} do
      game_id = Games.create_game(%{max_players: 2})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)

      :ok = Games.kick(game_id, alice.id, 2)
      assert GamesDb.list_player_games(bob.id) == []
      assert [%{id: ^game_id}] = GamesDb.list_player_games(alice.id)

      kill_server!(game_id)
      assert {:lobby, %{players: [%{name: remaining}]}} = Games.player_view(game_id, alice.id)
      assert remaining == alice.name
    end
  end

  defp kill_server!(game_id) do
    [{pid, _}] = Registry.lookup(GamesRegistry, game_id)
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(GamesSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    wait_until_deregistered(game_id)
  end

  defp wait_until_deregistered(game_id) do
    unless Registry.lookup(GamesRegistry, game_id) == [] do
      Process.sleep(5)
      wait_until_deregistered(game_id)
    end
  end
end

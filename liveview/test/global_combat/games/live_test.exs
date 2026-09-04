defmodule GlobalCombat.Games.LiveTest do
  # GIF-74: create_game/1 now inserts a real `games` row (GamesDb.create_game/1), so this needs
  # the Ecto Sandbox checkout DataCase provides — a plain ExUnit.Case has none.
  use GlobalCombat.DataCase, async: true

  import GlobalCombat.AccountsFixtures
  import GlobalCombat.GamesTestHelpers

  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombat.Games.PubSub, as: GamePubSub

  setup do
    game_id = Games.create_game(%{max_players: 3})
    %{game_id: game_id}
  end

  describe "invite/3 (GIF-114)" do
    test "a seated player can invite an existing account by name, and it shows up as a pending invite",
         %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      Games.join(game_id, alice.id, alice.name)

      assert {:ok, invitee} = Games.invite(game_id, alice.id, bob.name)
      assert invitee.id == bob.id
      assert [%{id: ^game_id}] = GamesDb.list_invited_games(bob.id)
    end

    test "invite works by email too", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      Games.join(game_id, alice.id, alice.name)

      assert {:ok, invitee} = Games.invite(game_id, alice.id, bob.email)
      assert invitee.id == bob.id
    end

    test "an account not seated in the game can't invite anyone", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()

      assert {:error, :not_playing} = Games.invite(game_id, alice.id, bob.name)
    end

    test "inviting an unknown login errors", %{game_id: game_id} do
      alice = account_fixture()
      Games.join(game_id, alice.id, alice.name)

      assert {:error, :account_not_found} = Games.invite(game_id, alice.id, "nobody-like-this")
    end

    test "can't invite yourself", %{game_id: game_id} do
      alice = account_fixture()
      Games.join(game_id, alice.id, alice.name)

      assert {:error, :cannot_invite_self} = Games.invite(game_id, alice.id, alice.name)
    end

    test "can't invite someone already playing", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      Games.join(game_id, alice.id, alice.name)
      Games.join(game_id, bob.id, bob.name)

      assert {:error, :already_playing} = Games.invite(game_id, alice.id, bob.name)
    end

    test "can't invite the same account twice", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      Games.join(game_id, alice.id, alice.name)

      assert {:ok, _} = Games.invite(game_id, alice.id, bob.name)
      assert {:error, :already_invited} = Games.invite(game_id, alice.id, bob.name)
    end

    test "invites are refused once the game has started", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      carl = account_fixture()
      Games.join(game_id, alice.id, alice.name)
      Games.join(game_id, bob.id, bob.name)
      :ok = Games.start_game(game_id, alice.id)

      assert {:error, :not_in_lobby} = Games.invite(game_id, alice.id, carl.name)
    end

    test "an invited account can join a private game; an uninvited account can't" do
      game_id = Games.create_game(%{max_players: 3, is_private: true})
      alice = account_fixture()
      bob = account_fixture()
      carl = account_fixture()

      Games.join(game_id, alice.id, alice.name)
      assert {:error, :not_invited} = Games.join(game_id, bob.id, bob.name)

      assert {:ok, _} = Games.invite(game_id, alice.id, bob.name)
      assert {:ok, 2} = Games.join(game_id, bob.id, bob.name)

      assert {:error, :not_invited} = Games.join(game_id, carl.id, carl.name)
    end

    test "joining clears the pending invite so it stops showing up as an invite", %{
      game_id: game_id
    } do
      alice = account_fixture()
      bob = account_fixture()
      Games.join(game_id, alice.id, alice.name)
      Games.invite(game_id, alice.id, bob.name)

      Games.join(game_id, bob.id, bob.name)

      assert GamesDb.list_invited_games(bob.id) == []
    end
  end

  describe "quit/2 (GIF-114)" do
    test "a seated player quitting the lobby is removed and remaining players are renumbered", %{
      game_id: game_id
    } do
      alice = account_fixture()
      bob = account_fixture()
      carl = account_fixture()
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)
      {:ok, 3} = Games.join(game_id, carl.id, carl.name)

      assert :ok = Games.quit(game_id, bob.id)

      assert {:lobby, view} = Games.player_view(game_id, alice.id)
      assert Enum.map(view.players, & &1.name) == [alice.name, carl.name]

      # renumbering means the next join lands on 3, not colliding with Carl's existing seat
      dana = account_fixture()
      assert {:ok, 3} = Games.join(game_id, dana.id, dana.name)
    end

    test "an account not seated in the game can't quit", %{game_id: game_id} do
      alice = account_fixture()
      assert {:error, :not_playing} = Games.quit(game_id, alice.id)
    end

    test "quitting mid-play eliminates the player via the engine, without ending the game early",
         %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      carl = account_fixture()
      Games.join(game_id, alice.id, alice.name)
      Games.join(game_id, bob.id, bob.name)
      Games.join(game_id, carl.id, carl.name)
      :ok = Games.start_game(game_id, alice.id)

      assert :ok = Games.quit(game_id, bob.id)

      {:playing, view} = Games.player_view(game_id, alice.id)
      quit_player = Enum.find(view.players, &(&1.name == bob.name))
      assert quit_player.eliminated
      refute view.ended
    end

    test "quitting mid-play twice is refused the second time", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      Games.join(game_id, alice.id, alice.name)
      Games.join(game_id, bob.id, bob.name)
      :ok = Games.start_game(game_id, alice.id)

      assert :ok = Games.quit(game_id, bob.id)
      assert {:error, :already_eliminated} = Games.quit(game_id, bob.id)
    end
  end

  describe "kick/3 (GIF-114)" do
    test "the host can kick a player from the lobby before start", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)

      assert :ok = Games.kick(game_id, alice.id, 2)

      {:lobby, view} = Games.player_view(game_id, alice.id)
      assert Enum.map(view.players, & &1.name) == [alice.name]
    end

    test "a non-host player can't kick anyone", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      carl = account_fixture()
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)
      {:ok, 3} = Games.join(game_id, carl.id, carl.name)

      assert {:error, :not_host} = Games.kick(game_id, bob.id, 3)

      {:lobby, view} = Games.player_view(game_id, alice.id)
      assert length(view.players) == 3
    end

    test "kicking an unknown player number errors", %{game_id: game_id} do
      alice = account_fixture()
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)

      assert {:error, :not_found} = Games.kick(game_id, alice.id, 99)
    end

    test "kicking is refused once the game has started", %{game_id: game_id} do
      alice = account_fixture()
      bob = account_fixture()
      Games.join(game_id, alice.id, alice.name)
      Games.join(game_id, bob.id, bob.name)
      :ok = Games.start_game(game_id, alice.id)

      assert {:error, :not_in_lobby} = Games.kick(game_id, alice.id, 2)
    end
  end

  describe "lobby" do
    test "joining assigns seats in join order, host is always player 1", %{game_id: game_id} do
      assert {:ok, 1} = Games.join(game_id, 101, "Alice")
      assert {:ok, 2} = Games.join(game_id, 102, "Bob")
    end

    test "the same account can't join twice", %{game_id: game_id} do
      assert {:ok, 1} = Games.join(game_id, 101, "Alice")
      assert {:error, :already_joined} = Games.join(game_id, 101, "Alice")
    end

    test "join fails once the lobby is full", %{game_id: game_id} do
      Games.join(game_id, 101, "Alice")
      Games.join(game_id, 102, "Bob")
      Games.join(game_id, 103, "Carl")
      assert {:error, :full} = Games.join(game_id, 104, "Dana")
    end

    test "only player 1 (the host) can start, and only with at least 2 players", %{
      game_id: game_id
    } do
      Games.join(game_id, 101, "Alice")
      assert {:error, :cannot_start} = Games.start_game(game_id, 101)

      Games.join(game_id, 102, "Bob")
      assert {:error, :cannot_start} = Games.start_game(game_id, 102)
      assert :ok = Games.start_game(game_id, 101)
    end

    test "player_view/2 reports :lobby before start_game/2", %{game_id: game_id} do
      Games.join(game_id, 101, "Alice")
      assert {:lobby, view} = Games.player_view(game_id, 101)
      assert view.viewer_number == 1
      assert Enum.map(view.players, & &1.name) == ["Alice"]
    end
  end

  describe "gameplay — turns resolve and broadcast like the old GameHub events" do
    setup %{game_id: game_id} do
      Games.join(game_id, 101, "Alice")
      Games.join(game_id, 102, "Bob")
      :ok = Games.start_game(game_id, 101)
      GamePubSub.subscribe_game(game_id)
      %{game_id: game_id}
    end

    test "player_view/2 reports :playing with a fog-filtered board once started", %{
      game_id: game_id
    } do
      assert {:playing, view} = Games.player_view(game_id, 101)
      assert view.turn == 1
      assert length(view.players) == 2
    end

    test "chat broadcasts an :add_message event to the game topic (GameHub.Say)", %{
      game_id: game_id
    } do
      Games.send_chat(game_id, 101, "Alice", "gl hf")
      assert_receive {:add_message, %{source_id: 101, source_name: "Alice", text: "gl hf"}}
    end

    test "Done for one of two players broadcasts :set_done without resolving the turn (GameHub.SetDone)",
         %{game_id: game_id} do
      Games.set_done(game_id, 101)
      assert_receive {:set_done, 1}
      refute_receive :reload

      {:playing, view} = Games.player_view(game_id, 101)
      assert view.turn == 1
    end

    test "Done for every player resolves the turn and broadcasts :reload (GameHub.Refresh) — the turn actually running live",
         %{game_id: game_id} do
      Games.set_done(game_id, 101)
      assert_receive {:set_done, 1}

      Games.set_done(game_id, 102)
      assert_receive :reload

      {:playing, view} = Games.player_view(game_id, 101)
      assert view.turn == 2
    end

    test "a turn resolution notifies every seated account privately (GameHub.SendNotification)",
         %{game_id: game_id} do
      GamePubSub.subscribe_account(101)
      GamePubSub.subscribe_account(102)

      Games.set_done(game_id, 101)
      Games.set_done(game_id, 102)

      assert_receive {:notification, "Turn 2 Run", _summary, "/Game-" <> _}
      assert_receive {:notification, "Turn 2 Run", _summary, "/Game-" <> _}
    end

    test "an account that isn't seated in the game can't mark anyone done", %{game_id: game_id} do
      Games.set_done(game_id, 999)
      refute_receive {:set_done, _}, 50
    end
  end

  describe "on-demand rehydration when the Server process has died (GIF-119)" do
    test "game_exists?/1 transparently restarts the Server from games.serialized", %{
      game_id: game_id
    } do
      Games.join(game_id, 101, "Alice")
      Games.join(game_id, 102, "Bob")
      :ok = Games.start_game(game_id, 101)

      kill_server!(game_id)
      assert Games.game_exists?(game_id)

      {:playing, view} = Games.player_view(game_id, 101)
      assert view.turn == 1
      assert Enum.map(view.players, & &1.name) |> Enum.sort() == ["Alice", "Bob"]
    end

    test "with_game/2 (via player_view/2, set_done/2, ...) rehydrates instead of reporting :not_found",
         %{game_id: game_id} do
      Games.join(game_id, 101, "Alice")
      Games.join(game_id, 102, "Bob")
      :ok = Games.start_game(game_id, 101)

      kill_server!(game_id)

      assert :ok = Games.set_done(game_id, 101)
      assert :ok = Games.set_done(game_id, 102)

      {:playing, view} = Games.player_view(game_id, 101)
      assert view.turn == 2
    end

    test "a game with no Server and no persisted state (created, never joined) still reports not found" do
      # A lobby is snapshotted on its first join (see LobbyPersistenceTest), so the only row with
      # nothing to rehydrate from is one nobody ever joined.
      game_id = Games.create_game(%{max_players: 3})

      kill_server!(game_id)

      refute Games.game_exists?(game_id)
      assert {:error, :not_found} = Games.player_view(game_id, 101)
    end

    test "a joined-but-unstarted lobby rehydrates as a lobby, not as not found" do
      game_id = Games.create_game(%{max_players: 3})
      Games.join(game_id, 101, "Alice")

      kill_server!(game_id)

      assert Games.game_exists?(game_id)
      assert {:lobby, %{players: [%{name: "Alice"}]}} = Games.player_view(game_id, 101)
    end

    test "a game id with no games row at all reports not found" do
      refute Games.game_exists?(-1)
      assert {:error, :not_found} = Games.player_view(-1, 101)
    end
  end

  describe "private messages (GameHub.SendMessage)" do
    test "broadcast_receive_message/4 reaches a subscriber of the target account's topic" do
      GamePubSub.subscribe_account(201)
      GamePubSub.broadcast_receive_message(201, 555, "Carl", "hey")
      assert_receive {:receive_message, 555, "Carl", "hey"}
    end

    test "broadcast_receive_message/4 does not reach a different account's topic" do
      GamePubSub.subscribe_account(202)
      GamePubSub.broadcast_receive_message(201, 555, "Carl", "hey")
      refute_receive {:receive_message, 555, "Carl", "hey"}, 50
    end
  end
end

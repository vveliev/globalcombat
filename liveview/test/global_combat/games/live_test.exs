defmodule GlobalCombat.Games.LiveTest do
  # GIF-74: create_game/1 now inserts a real `games` row (GamesDb.create_game/1), so this needs
  # the Ecto Sandbox checkout DataCase provides — a plain ExUnit.Case has none.
  use GlobalCombat.DataCase, async: true

  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombat.Games.PubSub, as: GamePubSub
  alias GlobalCombat.Games.Registry, as: GamesRegistry
  alias GlobalCombat.Games.Supervisor, as: GamesSupervisor

  setup do
    game_id = Games.create_game(%{max_players: 3})
    %{game_id: game_id}
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

    test "a game with no Server and no persisted state (never started) still reports not found" do
      game_id = Games.create_game(%{max_players: 3})
      Games.join(game_id, 101, "Alice")

      kill_server!(game_id)

      refute Games.game_exists?(game_id)
      assert {:error, :not_found} = Games.player_view(game_id, 101)
    end

    test "a game id with no games row at all reports not found" do
      refute Games.game_exists?(-1)
      assert {:error, :not_found} = Games.player_view(-1, 101)
    end
  end

  defp kill_server!(game_id) do
    [{pid, _}] = Registry.lookup(GamesRegistry, game_id)
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(GamesSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    # Registry's own de-registration runs off a *separate* monitor on `pid` than the one
    # above, so our :DOWN landing first doesn't guarantee its ETS entry is gone yet — without
    # this, ensure_started/1 can still see the dead pid via Server.alive?/1 and skip rehydrating.
    wait_until_deregistered(game_id)
  end

  defp wait_until_deregistered(game_id) do
    unless Registry.lookup(GamesRegistry, game_id) == [] do
      wait_until_deregistered(game_id)
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

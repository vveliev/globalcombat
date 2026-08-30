defmodule GlobalCombatWeb.GameLiveTest do
  @moduledoc """
  Proves GIF-30's "done when": two browser sessions in one game see a turn resolve
  live on both (`GameHub.Refresh`'s `:reload` equivalent), plus one test per
  remaining SignalR event equivalent (`addMessage`, `setDone`, `receiveMessage`,
  `sendNotification`), plus a fog-of-war leak regression at the rendered-HTML level
  (the concrete failure mode the issue calls out: "a careless assign of full game
  state").
  """

  use GlobalCombatWeb.ConnCase, async: true

  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombat.Games.PubSub, as: GamePubSub

  # Two-session PubSub delivery to a LiveView's own process is inherently async —
  # there's no synchronous call that proves handle_info/2 already ran. Polling
  # render/1 for the expected content is the standard way to wait it out without
  # coupling the test to exact message-ordering internals.
  defp wait_for(view, text, attempts \\ 100)

  defp wait_for(_view, text, 0), do: flunk("gave up waiting for #{inspect(text)} to render")

  defp wait_for(view, text, attempts) do
    html = render(view)

    if html =~ text do
      html
    else
      Process.sleep(10)
      wait_for(view, text, attempts - 1)
    end
  end

  defp start_two_player_game(conn1, conn2) do
    alice = account_fixture(%{"name" => "Alice"})
    bob = account_fixture(%{"name" => "Bob"})

    game_id = Games.create_game(%{max_players: 2})
    {:ok, 1} = Games.join(game_id, alice.id, alice.name)
    {:ok, 2} = Games.join(game_id, bob.id, bob.name)
    :ok = Games.start_game(game_id, alice.id)

    {:ok, alice_view, _html} = conn1 |> log_in_account(alice) |> live(~p"/Game-#{game_id}")
    {:ok, bob_view, _html} = conn2 |> log_in_account(bob) |> live(~p"/Game-#{game_id}")

    %{game_id: game_id, alice: alice, bob: bob, alice_view: alice_view, bob_view: bob_view}
  end

  test "a turn resolving on one session shows up live on the other (GameHub.Refresh -> :reload)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view, bob_view: bob_view} = start_two_player_game(conn1, conn2)

    assert render(alice_view) =~ "Turn 1"
    assert render(bob_view) =~ "Turn 1"

    # Neither click's own handle_event updates assigns synchronously — both views
    # only learn the turn resolved via the async :reload broadcast, same as neither
    # browser tab reloading itself under SignalR; the server pushed it to both.
    render_click(alice_view, "done")
    render_click(bob_view, "done")

    assert wait_for(alice_view, "Turn 2") =~ "Turn 2"
    assert wait_for(bob_view, "Turn 2") =~ "Turn 2"
  end

  test "the lobby renders a just-joined player without crashing (GIF-94 regression)", %{
    conn: conn
  } do
    alice = account_fixture(%{"name" => "Alice"})

    game_id = Games.create_game(%{max_players: 6})
    {:ok, 1} = Games.join(game_id, alice.id, alice.name)

    {:ok, _view, html} = conn |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

    assert html =~ "Alice"
    assert html =~ "Waiting for players"
  end

  test "a chat message from one session appears live on the other (GameHub.Say -> addMessage)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view, bob_view: bob_view} = start_two_player_game(conn1, conn2)

    render_submit(alice_view, "send_chat", %{"text" => "good luck!"})

    assert wait_for(bob_view, "good luck!") =~ "Alice"
  end

  test "one player marking done shows up on the other session without a full reload (GameHub.SetDone -> setDone)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view, bob_view: bob_view} = start_two_player_game(conn1, conn2)

    render_click(alice_view, "done")

    assert wait_for(bob_view, "Done") =~ "Done"
    # the turn hasn't resolved — only Bob is still owed a turn, Alice's Done marker
    # updated in place.
    assert render(bob_view) =~ "Turn 1"
  end

  test "a private message is delivered only to its target account's session (GameHub.SendMessage -> receiveMessage)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()

    %{alice: alice, alice_view: alice_view, bob_view: bob_view} =
      start_two_player_game(conn1, conn2)

    GamePubSub.broadcast_receive_message(alice.id, 999, "Carl", "hey Alice")

    assert wait_for(alice_view, "hey Alice") =~ "Carl"
    refute render(bob_view) =~ "hey Alice"
  end

  test "a turn-run notification is delivered privately to a seated account (GameHub.SendNotification -> sendNotification)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view, bob_view: bob_view} = start_two_player_game(conn1, conn2)

    render_click(alice_view, "done")
    render_click(bob_view, "done")

    assert wait_for(alice_view, "Turn 2 Run") =~ "Turn 2 Run"
    assert wait_for(bob_view, "Turn 2 Run") =~ "Turn 2 Run"
  end

  test "each territory's img carries alt text naming the area and its owner (WCAG 1.1.1, GIF-79)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()

    %{alice_view: alice_view, alice: alice, game_id: game_id} =
      start_two_player_game(conn1, conn2)

    {:playing, alice_state} = Games.player_view(game_id, alice.id)
    owned_by_alice = Enum.find(alice_state.areas, &(&1.owner_number == 1))
    assert owned_by_alice

    html = render(alice_view)

    assert html =~ "alt=\"#{owned_by_alice.tech_name}, owned by Alice\""
  end

  test "the status strip and chat log are wired as polite live regions (WCAG 4.1.3, GIF-80)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

    html = render(alice_view)

    # :status carries turn-advance/game-ended announcements (the :reload broadcast);
    # the chat <ul> carries :add_message. Both are "polite" (not "assertive") so a
    # screen reader finishes the player's current sentence before interrupting —
    # per GIF-80's fix direction, mid-input chat/turn updates shouldn't cut in.
    assert html =~ ~r/aria-label="Game status"[^>]*aria-live="polite"/
    assert html =~ ~r/<ul aria-live="polite"/
  end

  test "the game board carries a focus-management hook targeting a focusable status landmark (WCAG 2.4.3, GIF-82)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

    html = render(alice_view)

    # Join/Start/End Turn/Force Turn all remove the clicked control from the DOM
    # (lobby -> board swap, done/1's conditional) — without explicit focus
    # management, LiveView's morphdom patch drops focus to <body>. The
    # ".FocusManager" hook (game_live.ex) restores focus to this landmark once
    # it notices its previously-focused element is gone; ExUnit's LiveViewTest
    # renders no real DOM/JS, so this asserts the two static contracts the
    # client-side behavior depends on rather than the focus move itself.
    #
    # ColocatedHook rewrites the ".FocusManager" name at compile time to the
    # fully-qualified manifest key (`GlobalCombatWeb.GameLive.FocusManager`) in
    # both the emitted `phx-hook` attribute and the `phoenix-colocated/*`
    # manifest `app.js` imports — asserting the literal ".FocusManager" here
    # would never match the real render output.
    assert html =~ ~r/id="game-board"[^>]*phx-hook="GlobalCombatWeb\.GameLive\.FocusManager"/
    assert html =~ ~r/aria-label="Game status"[^>]*tabindex="-1"[^>]*data-focus-landmark/
  end

  test "the board has a visually-hidden table equivalent listing territory, owner, armies, and adjacency (WCAG 1.3.1, GIF-81)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()

    %{alice_view: alice_view, alice: alice, game_id: game_id} =
      start_two_player_game(conn1, conn2)

    {:playing, alice_state} = Games.player_view(game_id, alice.id)
    owned_by_alice = Enum.find(alice_state.areas, &(&1.owner_number == 1))
    assert owned_by_alice

    html = render(alice_view)

    # LiveView tags a function component's root element with `phx-r=""` (visible
    # throughout this render, e.g. the outer `<div phx-r="" id="game-board" ...>`)
    # ahead of its own attributes — `board_table/1`'s `<table>` is one such root,
    # so the attribute order isn't `<table class="sr-only">` verbatim.
    assert html =~ ~r/<table[^>]*class="sr-only"[^>]*>/
    assert html =~ ~r/<th scope="row">#{owned_by_alice.name}<\/th>\s*<td>Alice<\/td>/

    [first_neighbor | _] = owned_by_alice.adjacent
    neighbor_name = Enum.find(alice_state.areas, &(&1.number == first_neighbor)).name
    assert html =~ neighbor_name
  end

  test "army-count overlays carry a dark outline independent of the owner_color tile (WCAG 1.4.3, GIF-83)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

    html = render(alice_view)

    # text-white alone measures 1.27:1 against owner_color 3 (#FFE45F) and
    # 3.91:1 against owner_color 4 (#D45D00) -- both below WCAG thresholds.
    # The outline is background-color-independent by construction, so any
    # rendered army-count span having it is sufficient evidence (no need to
    # force a specific owner_color onto a territory here).
    assert html =~
             ~r/class="absolute top-1\/2 left-1\/2 -translate-x-1\/2 -translate-y-1\/2 text-white font-bold \[text-shadow:-1px_-1px_0_#000,1px_-1px_0_#000,-1px_1px_0_#000,1px_1px_0_#000\]"/
  end

  describe "fog of war (leak regression)" do
    # deal_areas/2's round-robin can leave every area adjacent to some opponent (e.g. a
    # 2-way alternating deal on a densely-linked map) — that's a property of the demo
    # dealer, not of the fog rule under test, so this searches (deterministically, no
    # RNG involved) for a player count that actually produces a hidden area instead of
    # assuming any particular one does.
    defp scenario_with_a_hidden_area(map_name) do
      num_areas = GlobalCombat.Engine.MapInfo.num_areas(map_name)

      Enum.find_value(2..8, fn player_count ->
        dealt = Map.new(GlobalCombat.Games.Server.deal_areas(num_areas, player_count))

        hidden =
          Enum.find(dealt, fn {area_number, owner} ->
            owner != 1 and
              not Enum.any?(GlobalCombat.Engine.MapInfo.inbounds(map_name, area_number), fn n ->
                Map.get(dealt, n) == 1
              end)
          end)

        hidden && {player_count, elem(hidden, 0), elem(hidden, 1)}
      end)
    end

    test "a fogged opponent's true army count for a non-adjacent area never reaches the other player's rendered HTML",
         %{conn: conn1} do
      map_name = :original
      {player_count, hidden_area_number, true_owner} = scenario_with_a_hidden_area(map_name)

      accounts = for n <- 1..player_count, do: account_fixture(%{"name" => "Player#{n}"})
      [alice | _] = accounts

      game_id =
        Games.create_game(%{max_players: player_count, is_fogged: true, map_name: map_name})

      accounts
      |> Enum.with_index(1)
      |> Enum.each(fn {account, number} ->
        assert {:ok, ^number} = Games.join(game_id, account.id, account.name)
      end)

      :ok = Games.start_game(game_id, alice.id)

      {:playing, alice_state} = Games.player_view(game_id, alice.id)
      hidden_area = Enum.find(alice_state.areas, &(&1.number == hidden_area_number))
      refute hidden_area.visible
      refute hidden_area.armies

      {:ok, alice_view, html} = conn1 |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

      # The true owner's color-suffixed sprite for this area must never appear anywhere
      # in Alice's rendered markup, on first render or after a reload — this is
      # GameLive's whole reason for going through GlobalCombat.Games.PlayerView instead
      # of assigning canonical state.
      true_sprite = "#{hidden_area.tech_name}#{rem(true_owner, 9)}.gif"
      refute html =~ true_sprite
      refute render(alice_view) =~ true_sprite

      # Same leak, via the alt text (GIF-79): a hidden area's owner name must never
      # reach a non-owner's markup either, even though the plain-text owner name is a
      # much easier thing to accidentally source from unfiltered state than the sprite
      # filename is.
      true_owner_name = Enum.find(alice_state.players, &(&1.number == true_owner)).name
      refute html =~ "alt=\"#{hidden_area.tech_name}, owned by #{true_owner_name}\""
      assert html =~ "alt=\"#{hidden_area.tech_name}, owned by unclaimed\""

      # Same leak, via the sr-only board table (GIF-81): the hidden area's row must
      # report "unclaimed" too, never the true owner's name or army count — the
      # table is built from the same fog-filtered PlayerView data as the sprite/alt
      # text, so it must fail the exact same way if someone ever wires it to raw
      # engine state instead.
      refute html =~ ~r/<th scope="row">#{hidden_area.name}<\/th>\s*<td>#{true_owner_name}<\/td>/
      assert html =~ ~r/<th scope="row">#{hidden_area.name}<\/th>\s*<td>unclaimed<\/td>/
    end
  end
end

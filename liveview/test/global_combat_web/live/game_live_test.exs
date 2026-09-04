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
  import GlobalCombat.GamesTestHelpers

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

  describe "end of game (GIF-122)" do
    test "a finished game shows a Game Over banner naming the winner and drops the in-progress controls",
         %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()

      %{game_id: game_id, bob: bob, alice_view: alice_view, bob_view: bob_view} =
        start_two_player_game(conn1, conn2)

      assert has_element?(alice_view, "#turn-controls button", "End Turn")
      assert has_element?(alice_view, "#turn-controls button", "Force Turn")
      refute has_element?(alice_view, "#game-over")

      # Bob quitting mid-play eliminates him, which ends a two-player game with Alice in place 1.
      # quit/2 is a call, and the :reload broadcast is sent before it replies, so syncing each
      # LiveView's mailbox is enough — no polling.
      :ok = Games.quit(game_id, bob.id)
      sync_game(game_id, alice_view)
      sync_game(game_id, bob_view)

      assert has_element?(alice_view, "#game-over-heading", "Game Over — Alice wins")
      assert has_element?(alice_view, "#game-over-outcome", "You win!")
      assert has_element?(alice_view, "#game-over-standings li", "1. Alice")
      assert has_element?(alice_view, "#game-over-standings li", "2. Bob")
      assert has_element?(alice_view, "#game-over-home")
      refute has_element?(alice_view, "#turn-controls")
      refute has_element?(alice_view, "button", "End Turn")
      refute has_element?(alice_view, "button", "Force Turn")

      assert has_element?(bob_view, "#game-over-outcome", "You finished in place 2.")
      refute has_element?(bob_view, "button", "Force Turn")
    end

    test "a spectator sees the banner without a personal outcome line", %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()
      %{game_id: game_id, bob: bob} = start_two_player_game(conn1, conn2)
      :ok = Games.quit(game_id, bob.id)

      {:ok, spectator, _html} = Phoenix.ConnTest.build_conn() |> live(~p"/Game-#{game_id}")
      assert has_element?(spectator, "#game-over-heading", "Game Over — Alice wins")
      refute has_element?(spectator, "#game-over-outcome")
    end
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

  test "the board keeps the site chrome (header + left nav) visible during play (GIF-102)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

    html = render(alice_view)

    # GameLive used to render inside a bare GameLayout with no site_chrome, so a
    # player mid-game lost the "GLOBAL COMBAT" wordmark/header and every nav link
    # (Home, Game Manual, New Game, Messages, Settings, Log Off) — leaving browser
    # navigation as the only way back to the rest of the site, unlike every other
    # page (and unlike .NET's equivalent in-progress game view).
    assert html =~ "GLOBAL COMBAT"
    assert html =~ ~r/aria-label="Sidebar"/
    assert html =~ "Game Manual"
    assert html =~ "Log Off"
    # the board itself must still be present, nested inside that chrome.
    assert html =~ ~r/id="game-board"/
  end

  test "the lobby (pre-Start-Game) also keeps the site chrome visible (GIF-102)", %{conn: conn} do
    alice = account_fixture(%{"name" => "Alice"})

    game_id = Games.create_game(%{max_players: 6})
    {:ok, 1} = Games.join(game_id, alice.id, alice.name)

    {:ok, _view, html} = conn |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

    assert html =~ "GLOBAL COMBAT"
    assert html =~ ~r/aria-label="Sidebar"/
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

  test "each territory carries an accessible name giving the area, its owner and its armies (WCAG 1.1.1, GIF-79)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()

    %{alice_view: alice_view, alice: alice, game_id: game_id} =
      start_two_player_game(conn1, conn2)

    {:playing, alice_state} = Games.player_view(game_id, alice.id)
    owned_by_alice = Enum.find(alice_state.areas, &(&1.owner_number == 1))
    assert owned_by_alice

    # The SVG board's territory is a role="button" group (SVG has no <button>),
    # so the name lives in aria-label rather than an <img alt>; it uses the
    # display name ("South Africa"), not the sprite tech_name ("southAfrica").
    assert has_element?(
             alice_view,
             ~s(g#territory-#{owned_by_alice.number}[role="button"][aria-label^="#{owned_by_alice.name}, owned by Alice, "])
           )
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

  test "army-count overlays carry a dark outline independent of the owner colour (WCAG 1.4.3, GIF-83)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

    # A light number alone fails contrast on the yellow and orange owner fills.
    # On the SVG board the outline is a dark stroke painted *under* the glyphs —
    # `paint-order="stroke"` is a presentation attribute on every count, so the
    # contract is visible in the rendered markup, background-independent by
    # construction; the stroke/fill colours come from `.world-map-count` in
    # app.css. The counts live in a pointer-events-free layer above the
    # territories (GIF-111), so clicking the digits still selects the territory
    # underneath.
    assert has_element?(alice_view, ~s(text.world-map-count[paint-order="stroke"]))
  end

  test "the board shows a Region Bonuses panel listing every continent's control bonus (GIF-103)",
       %{conn: conn1} do
    conn2 = Phoenix.ConnTest.build_conn()
    %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

    html = render(alice_view)

    assert html =~ "Region Bonuses"

    # start_two_player_game/2 doesn't pin :map_name, so this asserts against
    # whatever map the game actually started on (Server.create_game/1 defaults
    # to :original) rather than hardcoding its regions — same
    # sourced-from-MapInfo contract the fix itself relies on.
    for {_number, name, _num_areas, army_bonus} <- GlobalCombat.Engine.MapInfo.regions(:original) do
      assert html =~ ~r/#{Regex.escape(name)}[\s\S]*?#{army_bonus}/
    end
  end

  describe "territory click-to-order composition (GIF-111)" do
    # `start_two_player_game/2` deals :original's 42 areas round-robin over 2 players
    # (`Games.Server.deal_areas/2`): Alice (player 1) gets every odd area, Bob (player
    # 2) every even one. Area 1 links to [2, 3, 37] (`MapInfo.areas(:original)`), so
    # area 1 <-> 3 is an owned-adjacent pair (transfer), area 1 <-> 2 is an
    # owned-vs-enemy adjacent pair (attack), and area 1 <-> 4 is enemy but
    # non-adjacent.

    test "clicking an owned territory opens the panel in assign mode, prefilled with the unassigned pool",
         %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()
      %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

      html = render_click(alice_view, "select_area", %{"area" => "1"})

      assert html =~ "Assign new armies or select a target area"
      assert html =~ ~r/<input[^>]*name="amount"[^>]*value="25"/
    end

    test "selecting an area marks its territory pressed and draws the highlight outline above the board",
         %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()
      %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

      render_click(alice_view, "select_area", %{"area" => "1"})

      # The SVG board's territory is a role="button" <g>; its selected state is
      # both announced (aria-pressed) and drawn as a second <use> of the same
      # outline in the highlights layer, painted above every neighbour so the
      # selected coastline is never half-covered by the territory drawn after it.
      assert has_element?(alice_view, ~s(g#territory-1[aria-pressed="true"]))
      assert has_element?(alice_view, ~s(use.world-map-highlight--selected[href="#gc-area-1"]))

      render_click(alice_view, "select_area", %{"area" => "2"})

      assert has_element?(alice_view, ~s(g#territory-2[aria-pressed="true"]))
      assert has_element?(alice_view, ~s(use.world-map-highlight--target[href="#gc-area-2"]))
    end

    test "clicking an enemy territory first does nothing (no panel, matching .NET hiding the click for a non-owner)",
         %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()
      %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

      html = render_click(alice_view, "select_area", %{"area" => "2"})

      refute html =~ "Assign new armies"
      refute html =~ "Transfer how many"
      refute html =~ "Attack"
    end

    test "a second click on an adjacent owned territory switches the panel to transfer mode",
         %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()

      %{alice_view: alice_view, alice: alice, game_id: game_id} =
        start_two_player_game(conn1, conn2)

      {:playing, view} = Games.player_view(game_id, alice.id)
      area_three_name = Enum.find(view.areas, &(&1.number == 3)).name

      render_click(alice_view, "select_area", %{"area" => "1"})
      html = render_click(alice_view, "select_area", %{"area" => "3"})

      assert html =~ "Transfer how many armies to #{area_three_name}?"
      assert html =~ ~r/<button[^>]*type="submit"[^>]*>\s*Transfer\s*<\/button>/
    end

    test "a second click on an adjacent enemy territory switches the panel to attack mode",
         %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()

      %{alice_view: alice_view, alice: alice, game_id: game_id} =
        start_two_player_game(conn1, conn2)

      {:playing, view} = Games.player_view(game_id, alice.id)
      area_two_name = Enum.find(view.areas, &(&1.number == 2)).name

      render_click(alice_view, "select_area", %{"area" => "1"})
      html = render_click(alice_view, "select_area", %{"area" => "2"})

      assert html =~ "Attack #{area_two_name} with how many armies?"
      assert html =~ ~r/<button[^>]*type="submit"[^>]*>\s*Attack\s*<\/button>/
    end

    test "a second click on a non-adjacent enemy territory is a no-op (order panel stays in assign mode)",
         %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()
      %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

      render_click(alice_view, "select_area", %{"area" => "1"})
      html = render_click(alice_view, "select_area", %{"area" => "4"})

      assert html =~ "Assign new armies or select a target area"
    end

    test "submitting an assign order moves armies onto the area and closes the panel", %{
      conn: conn1
    } do
      conn2 = Phoenix.ConnTest.build_conn()
      %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

      render_click(alice_view, "select_area", %{"area" => "1"})
      html = render_submit(alice_view, "submit_order", %{"amount" => "5"})

      refute html =~ "Assign new armies or select a target area"

      # `Games.assign/4` is a cast processed by a different process (the game's
      # GenServer) than this test's own — the resulting :reload broadcast, not the
      # `render_submit/3` return value, is what actually carries the updated army
      # count back to this view, hence polling rather than asserting on `html` above.
      assert wait_for(
               alice_view,
               ~r/<th scope="row">Alaska<\/th>\s*<td>Alice<\/td>\s*<td>10<\/td>/
             )
    end

    test "cancel_order closes the panel without changing any state", %{conn: conn1} do
      conn2 = Phoenix.ConnTest.build_conn()
      %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

      render_click(alice_view, "select_area", %{"area" => "1"})
      html = render_click(alice_view, "cancel_order", %{})

      refute html =~ "Assign new armies or select a target area"
      assert html =~ ~r/<th scope="row">Alaska<\/th>\s*<td>Alice<\/td>\s*<td>5<\/td>/
    end

    test "unassign_order returns a pending assignment to the pool and closes the panel", %{
      conn: conn1
    } do
      conn2 = Phoenix.ConnTest.build_conn()
      %{alice_view: alice_view} = start_two_player_game(conn1, conn2)

      render_click(alice_view, "select_area", %{"area" => "1"})
      render_submit(alice_view, "submit_order", %{"amount" => "5"})
      wait_for(alice_view, ~r/<th scope="row">Alaska<\/th>\s*<td>Alice<\/td>\s*<td>10<\/td>/)

      render_click(alice_view, "select_area", %{"area" => "1"})
      html = render_click(alice_view, "unassign_order", %{})

      refute html =~ "Assign new armies or select a target area"

      assert wait_for(
               alice_view,
               ~r/<th scope="row">Alaska<\/th>\s*<td>Alice<\/td>\s*<td>5<\/td>/
             )
    end
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

      # The true owner's colour slot for this area must never appear anywhere in
      # Alice's rendered markup, on first render or after a reload — this is
      # GameLive's whole reason for going through GlobalCombat.Games.PlayerView instead
      # of assigning canonical state. On the SVG board the owner reaches the markup
      # only as the territory's `data-owner` slot (the CSS fill hangs off it), so a
      # fogged territory must carry no `data-owner` at all.
      territory = "g#territory-#{hidden_area_number}"
      refute html =~ ~r/id="territory-#{hidden_area_number}"[^>]*data-owner=/
      refute has_element?(alice_view, "#{territory}[data-owner]")
      assert has_element?(alice_view, "#{territory}[data-fog]")

      # Same leak, via the accessible name (GIF-79): a hidden area's owner name must
      # never reach a non-owner's markup either, even though the plain-text owner
      # name is a much easier thing to accidentally source from unfiltered state
      # than a colour slot is. GIF-121: a fogged area no longer reuses the
      # neutral/unclaimed "unclaimed" wording — it gets its own distinct "hidden by
      # fog of war" treatment so it can't be mistaken for a genuinely-unclaimed tile.
      true_owner_name = Enum.find(alice_state.players, &(&1.number == true_owner)).name

      refute has_element?(
               alice_view,
               ~s(#{territory}[aria-label^="#{hidden_area.name}, owned by #{true_owner_name}"])
             )

      refute has_element?(
               alice_view,
               ~s(#{territory}[aria-label^="#{hidden_area.name}, unclaimed"])
             )

      assert has_element?(
               alice_view,
               ~s(#{territory}[aria-label="#{hidden_area.name}, hidden by fog of war"])
             )

      # Same leak, via the sr-only board table (GIF-81): the hidden area's row must
      # report "hidden by fog of war", never the true owner's name/army count nor
      # the "unclaimed" wording a genuinely-unowned area gets — the table is built
      # from the same fog-filtered PlayerView data as the sprite/alt text, so it
      # must fail the exact same way if someone ever wires it to raw engine state
      # instead.
      refute html =~ ~r/<th scope="row">#{hidden_area.name}<\/th>\s*<td>#{true_owner_name}<\/td>/
      refute html =~ ~r/<th scope="row">#{hidden_area.name}<\/th>\s*<td>unclaimed<\/td>/

      assert html =~
               ~r/<th scope="row">#{hidden_area.name}<\/th>\s*<td>hidden by fog of war<\/td>/
    end

    test "a fogged area's tile is visually distinct from a genuinely-unclaimed one (GIF-121)",
         %{conn: conn1} do
      map_name = :original
      {player_count, hidden_area_number, _true_owner} = scenario_with_a_hidden_area(map_name)

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

      {:ok, alice_view, _html} = conn1 |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

      # A fogged territory renders no owner colour slot at all — not even the "0"
      # neutral/unclaimed one every genuinely-unowned (visible) area uses — and is
      # instead marked `data-fog`, which the stylesheet turns into the hatch fill.
      refute has_element?(alice_view, ~s(g#territory-#{hidden_area_number}[data-owner="0"]))
      assert has_element?(alice_view, ~s(g#territory-#{hidden_area_number}[data-fog]))
    end
  end

  describe "elements map board" do
    test "an :elements game renders the same SVG board with per-element textures instead of sprites",
         %{conn: conn1} do
      alice = account_fixture(%{"name" => "Alice"})
      bob = account_fixture(%{"name" => "Bob"})

      game_id = Games.create_game(%{max_players: 2, map_name: :elements})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)
      :ok = Games.start_game(game_id, alice.id)

      {:ok, alice_view, html} = conn1 |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

      # Same WorldMap component, keyed by map: the board announces itself as the
      # elements map, uses the elements defs (its own cropped viewBox), and every
      # element territory carries a data-element the CSS textures hang off. Fire
      # Corner (area 1) is fire; Smoke Bridge (area 5) belongs to no element.
      assert has_element?(alice_view, ~s(.world-map[data-map="elements"]))
      assert has_element?(alice_view, ~s(g#territory-1[data-element="fire"]))
      assert has_element?(alice_view, ~s(g#territory-1 use.world-map-texture))
      refute has_element?(alice_view, ~s(g#territory-5[data-element]))
      assert has_element?(alice_view, ~s(g#territory-38[data-element="earth"]))

      # No sprite <img> survives for either map.
      refute html =~ ~r/<img[^>]*src="\/maps\//
    end
  end

  describe "Invite/Quit/Kick (GIF-114)" do
    test "a seated player inviting an existing account by name lands it on the invitee's pending invites",
         %{conn: conn} do
      alice = account_fixture(%{"name" => "Alice"})
      bob = account_fixture(%{"name" => "Bob"})

      game_id = Games.create_game(%{max_players: 4})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)

      {:ok, view, _html} = conn |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

      html = render_submit(view, "invite", %{"login" => bob.name})

      assert html =~ "Invited Bob."
      assert [%{id: ^game_id}] = GlobalCombat.Games.list_invited_games(bob.id)
    end

    test "inviting an unknown login shows an error instead of crashing", %{conn: conn} do
      alice = account_fixture(%{"name" => "Alice"})

      game_id = Games.create_game(%{max_players: 4})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)

      {:ok, view, _html} = conn |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

      html = render_submit(view, "invite", %{"login" => "no-such-account"})

      assert html =~ "No account found for &quot;no-such-account&quot;."
    end

    test "an invited account can join a private game; a stranger is refused (GIF-93 gap this closes)" do
      conn2 = Phoenix.ConnTest.build_conn()
      conn3 = Phoenix.ConnTest.build_conn()

      alice = account_fixture(%{"name" => "Alice"})
      bob = account_fixture(%{"name" => "Bob"})
      carl = account_fixture(%{"name" => "Carl"})

      game_id = Games.create_game(%{max_players: 4, is_private: true})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, _invitee} = Games.invite(game_id, alice.id, bob.name)

      {:ok, bob_view, _html} = conn2 |> log_in_account(bob) |> live(~p"/Game-#{game_id}")
      render_click(bob_view, "join")
      assert wait_for(bob_view, "Bob") =~ "Bob"

      {:ok, carl_view, _html} = conn3 |> log_in_account(carl) |> live(~p"/Game-#{game_id}")
      html = render_click(carl_view, "join")
      refute html =~ "Carl"
      assert html =~ ~r/phx-click="join"/
    end

    test "the host can kick a player from the lobby, and it's reflected live for everyone", %{
      conn: conn1
    } do
      conn2 = Phoenix.ConnTest.build_conn()

      alice = account_fixture(%{"name" => "Alice"})
      bob = account_fixture(%{"name" => "Bob"})

      game_id = Games.create_game(%{max_players: 4})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)

      {:ok, alice_view, html} = conn1 |> log_in_account(alice) |> live(~p"/Game-#{game_id}")
      {:ok, bob_view, _html} = conn2 |> log_in_account(bob) |> live(~p"/Game-#{game_id}")

      assert html =~ "Kick"

      render_click(alice_view, "kick", %{"player_number" => "2"})

      refute wait_for(alice_view, "Waiting for players") =~ "Bob"
      refute render(bob_view) =~ ~r/Kick/
    end

    test "a non-host player has no Kick control and a direct kick attempt is refused", %{
      conn: conn1
    } do
      conn2 = Phoenix.ConnTest.build_conn()

      alice = account_fixture(%{"name" => "Alice"})
      bob = account_fixture(%{"name" => "Bob"})

      game_id = Games.create_game(%{max_players: 4})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)

      {:ok, _alice_view, _html} = conn1 |> log_in_account(alice) |> live(~p"/Game-#{game_id}")
      {:ok, bob_view, html} = conn2 |> log_in_account(bob) |> live(~p"/Game-#{game_id}")

      refute html =~ "Kick"

      assert {:error, :not_host} = Games.kick(game_id, bob.id, 1)
      assert render(bob_view) =~ "Alice"
    end

    test "a player quitting the lobby leaves and can rejoin as a fresh Join click", %{conn: conn} do
      alice = account_fixture(%{"name" => "Alice"})
      bob = account_fixture(%{"name" => "Bob"})

      game_id = Games.create_game(%{max_players: 4})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)
      {:ok, 2} = Games.join(game_id, bob.id, bob.name)

      {:ok, view, _html} = conn |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

      html = render_click(view, "quit")

      assert html =~ ~r/phx-click="join"/
      refute html =~ ~r/phx-click="quit"/
      assert {:lobby, lobby_view} = Games.player_view(game_id, bob.id)
      assert Enum.map(lobby_view.players, & &1.name) == ["Bob"]
    end

    test "the last player quitting an empty lobby is navigated home", %{conn: conn} do
      alice = account_fixture(%{"name" => "Alice"})

      game_id = Games.create_game(%{max_players: 4})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)

      {:ok, view, _html} = conn |> log_in_account(alice) |> live(~p"/Game-#{game_id}")

      render_click(view, "quit")
      assert_redirect(view, "/")
    end

    test "a spectator of a lobby whose last player quits is sent home too, not crashed", %{
      conn: conn
    } do
      alice = account_fixture(%{"name" => "Alice"})

      game_id = Games.create_game(%{max_players: 4})
      {:ok, 1} = Games.join(game_id, alice.id, alice.name)

      {:ok, spectator, _html} = Phoenix.ConnTest.build_conn() |> live(~p"/Game-#{game_id}")
      assert has_element?(spectator, "#lobby-players li", "Player 1: Alice")

      {:ok, alice_view, _html} = conn |> log_in_account(alice) |> live(~p"/Game-#{game_id}")
      render_click(alice_view, "quit")
      assert_redirect(alice_view, "/")

      # The lobby row is gone (port of KillGame); the spectator's :reload finds no game and is
      # navigated home instead of hitting a dead process.
      assert_redirect(spectator, "/")
      assert GlobalCombat.Games.get_game(game_id) == nil
    end

    test "a player quitting mid-play is eliminated live, and can no longer quit again", %{
      conn: conn1
    } do
      conn2 = Phoenix.ConnTest.build_conn()

      %{alice_view: alice_view, bob_view: bob_view, bob: bob, game_id: game_id} =
        start_two_player_game(conn1, conn2)

      render_click(bob_view, "quit")

      assert wait_for(alice_view, "place") =~ "place"
      assert {:error, :already_eliminated} = Games.quit(game_id, bob.id)
    end
  end
end

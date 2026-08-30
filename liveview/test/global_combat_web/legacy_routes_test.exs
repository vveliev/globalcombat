defmodule GlobalCombatWeb.LegacyRoutesTest do
  @moduledoc """
  GIF-31: globalcombat.com has been live since 2001-01-22, and every path
  below is a real inbound link, bookmark, or search result. Asserts that
  every explicit route in `Web/Program.cs` still resolves in the Phoenix
  router, with the same capitalised-hyphenated shape and the same ids
  (`game.AUTO_INCREMENT` is at 684316 — ids are never renumbered).

  Originally a pure router-shape test against thin GIF-31 stubs, where most controllers echoed
  back the id/action they resolved -- enough to prove the route matched the right controller
  with the right params. Several surfaces have since grown real behavior and their assertions
  were upgraded to match: `Tournament-:id` (`TourneyController` is a real port as of GIF-32, so
  those cases assert against a real tourney fixture instead of a stub echo), the `Home`-routed
  paths (GIF-33 replaced `HomeController`'s stubs with real behavior, so those assertions check
  the real, often auth-gated, response instead of an echoed placeholder string), and the bare
  `/Game-:id` / `/Create-Game` routes (GIF-30 turned them into LiveViews, so those tests no
  longer assert stub text at a hardcoded historical id — `GlobalCombat.Games.Live` games are
  ephemeral and id-generated, not the fixed `game.AUTO_INCREMENT` row 684316 the stub echoed
  back; what's still very much a router-shape concern, and still asserted there, is that the
  same URL shape resolves, the same id survives, and casing normalization still applies — it's
  just a LiveView mount/redirect on the other end now instead of a stub controller action).
  `/Game-:id/:action` (Join/Invite/Kick/etc.) is still a stub, out of both issues' scope.
  """

  use GlobalCombatWeb.ConnCase

  import GlobalCombat.AccountsFixtures

  defp tourney_fixture(attrs \\ %{}) do
    {:ok, tourney} =
      %{"name" => "Legacy Route Cup", "initial_games" => 2, "game_size" => 2, "winners" => 1}
      |> Map.merge(attrs)
      |> GlobalCombat.Tourneys.create_tourney()

    tourney
  end

  describe "Game-{id:int}/{action=Index}" do
    test "GET /Game-:id mounts the board LiveView for a real game", %{conn: conn} do
      game_id = GlobalCombat.Games.Live.create_game(%{max_players: 2})
      conn = get(conn, "/Game-#{game_id}")
      assert html_response(conn, 200) =~ "Game #{game_id}"
    end

    test "GET /Game-:id/:action resolves an arbitrary action", %{conn: conn} do
      conn = get(conn, "/Game-684316/Stats")
      assert text_response(conn, 200) == "Game 684316 action=Stats"
    end

    test "GET /Game-:id redirects home instead of 404ing on a non-integer id (LiveView mount, not a plug 404)",
         %{conn: conn} do
      conn = get(conn, "/Game-abc")
      assert redirected_to(conn) == "/"
    end

    test "GET /Game-:id redirects home for a well-formed id that doesn't exist", %{conn: conn} do
      conn = get(conn, "/Game-999999999")
      assert redirected_to(conn) == "/"
    end

    test "GET /Game-:id/ resolves with a trailing slash, as the old app's own links used", %{
      conn: conn
    } do
      game_id = GlobalCombat.Games.Live.create_game(%{max_players: 2})
      conn = get(conn, "/Game-#{game_id}/")
      assert html_response(conn, 200) =~ "Game #{game_id}"
    end
  end

  describe "Player-Info-{id:int}" do
    import GlobalCombat.AccountsFixtures

    test "GET /Player-Info-:id resolves the id and renders that account (GIF-33)", %{
      conn: conn
    } do
      account = account_fixture()
      conn = get(conn, "/Player-Info-#{account.id}")
      assert html_response(conn, 200) =~ account.name
    end

    test "GET /Player-Info-:id 404s when no such account exists, same as the legacy action's null-row guard",
         %{conn: conn} do
      conn = get(conn, "/Player-Info-684316")
      assert conn.status == 404
    end

    test "GET /Player-Info-:id 404s on a non-integer id", %{conn: conn} do
      conn = get(conn, "/Player-Info-abc")
      assert conn.status == 404
    end
  end

  describe "Tournament-{id:int}" do
    test "GET /Tournament-:id resolves the id", %{conn: conn} do
      tourney = tourney_fixture()
      conn = get(conn, "/Tournament-#{tourney.id}")
      assert html_response(conn, 200) =~ tourney.name
    end

    test "GET /Tournament-:id 404s on a non-integer id", %{conn: conn} do
      conn = get(conn, "/Tournament-abc")
      assert conn.status == 404
    end

    test "GET /Tournament-:id 404s on an id with no matching tourney", %{conn: conn} do
      conn = get(conn, "/Tournament-99999999")
      assert conn.status == 404
    end

    test "GET /Tournament-:id/ resolves with a trailing slash, as the old app's own links used",
         %{conn: conn} do
      tourney = tourney_fixture()
      conn = get(conn, "/Tournament-#{tourney.id}/")
      assert html_response(conn, 200) =~ tourney.name
    end
  end

  describe "Create-Game / Create-Tournament" do
    test "GET /Create-Game redirects home when logged out (GameCreateLive, GIF-30)", %{
      conn: conn
    } do
      conn = get(conn, "/Create-Game")
      assert redirected_to(conn) == "/"
    end

    test "GET /Create-Game renders the create form when logged in", %{conn: conn} do
      conn = conn |> log_in_account(account_fixture()) |> get(~p"/Create-Game")
      assert html_response(conn, 200) =~ "Create a New Game"
    end

    test "GET /Create-Tournament redirects an anonymous visitor (admin-only, GIF-32)", %{
      conn: conn
    } do
      conn = get(conn, "/Create-Tournament")
      assert redirected_to(conn) == "/"
    end

    test "GET /Create-Tournament renders the form for an admin", %{conn: conn} do
      admin =
        account_fixture() |> Ecto.Changeset.change(admin: true) |> GlobalCombat.Repo.update!()

      conn = conn |> log_in_account(admin) |> get("/Create-Tournament")
      assert html_response(conn, 200) =~ "Create a New Tourney"
    end
  end

  describe "Game-Manual / Send-Message (hyphenated literals, not swallowed by Game-:id)" do
    test "GET /Game-Manual renders the real manual (GIF-33)", %{conn: conn} do
      conn = get(conn, "/Game-Manual")
      assert html_response(conn, 200) =~ "Game Manual"
    end

    test "POST /Send-Message redirects anonymous visitors home (GIF-33: requires login)", %{
      conn: conn
    } do
      conn = post(conn, "/Send-Message", %{"AccountId" => "1", "Message" => "hi"})
      assert redirected_to(conn) == "/"
    end
  end

  describe "{action} shortcut set: Messages|Stats|IpAddresses|GameManual|OptOut|PlayerInfo|Chat|LoadChatMessages|CloseChatWindow|SendMessage" do
    test "GET /Messages redirects anonymous visitors home (GIF-33: requires login)", %{
      conn: conn
    } do
      conn = get(conn, "/Messages")
      assert redirected_to(conn) == "/"
    end

    test "GET /Stats redirects non-admins home (GIF-33: admin-only)", %{conn: conn} do
      conn = get(conn, "/Stats")
      assert redirected_to(conn) == "/"
    end

    test "GET /IpAddresses redirects non-admins home (GIF-33 admin-hardening)",
         %{conn: conn} do
      conn = get(conn, "/IpAddresses")
      assert redirected_to(conn) == "/"
    end

    test "GET /GameManual", %{conn: conn} do
      conn = get(conn, "/GameManual")
      assert html_response(conn, 200) =~ "Game Manual"
    end

    test "GET /OptOut with no Account/Key shows the missing-key error (GIF-33)", %{conn: conn} do
      conn = get(conn, "/OptOut")
      assert html_response(conn, 200) =~ "Missing account or opt out key."
    end

    test "GET /PlayerInfo with no id 404s (GIF-33: same `id <= 0` guard as the legacy action)",
         %{conn: conn} do
      conn = get(conn, "/PlayerInfo")
      assert conn.status == 404
    end

    test "GET /Chat redirects anonymous visitors home (GIF-33: requires login)", %{conn: conn} do
      conn = get(conn, "/Chat")
      assert redirected_to(conn) == "/"
    end

    test "GET /LoadChatMessages redirects anonymous visitors home (GIF-33: requires login)", %{
      conn: conn
    } do
      conn = get(conn, "/LoadChatMessages")
      assert redirected_to(conn) == "/"
    end

    test "GET /CloseChatWindow redirects anonymous visitors home (GIF-33: requires login)", %{
      conn: conn
    } do
      conn = get(conn, "/CloseChatWindow")
      assert redirected_to(conn) == "/"
    end

    test "GET /SendMessage redirects anonymous visitors home (GIF-33: requires login)", %{
      conn: conn
    } do
      conn = get(conn, "/SendMessage")
      assert redirected_to(conn) == "/"
    end
  end

  describe "case-insensitive matching (ASP.NET Core's default routing behavior)" do
    test "GET /game-:id resolves like /Game-:id (LiveView mount, GIF-30)", %{conn: conn} do
      game_id = GlobalCombat.Games.Live.create_game(%{max_players: 2})
      conn = get(conn, "/game-#{game_id}")
      assert html_response(conn, 200) =~ "Game #{game_id}"
    end

    test "GET /GAME-:id resolves like /Game-:id (LiveView mount, GIF-30)", %{conn: conn} do
      game_id = GlobalCombat.Games.Live.create_game(%{max_players: 2})
      conn = get(conn, "/GAME-#{game_id}")
      assert html_response(conn, 200) =~ "Game #{game_id}"
    end

    test "GET /player-info-684316 resolves like /Player-Info-684316 (404: no such account)", %{
      conn: conn
    } do
      conn = get(conn, "/player-info-684316")
      assert conn.status == 404
    end

    test "GET /tournament-:id resolves like /Tournament-:id", %{conn: conn} do
      tourney = tourney_fixture()
      conn = get(conn, "/tournament-#{tourney.id}")
      assert html_response(conn, 200) =~ tourney.name
    end

    test "GET /game-manual resolves like /Game-Manual", %{conn: conn} do
      conn = get(conn, "/game-manual")
      assert html_response(conn, 200) =~ "Game Manual"
    end

    test "GET /playerinfo resolves like /PlayerInfo (404: no id)", %{conn: conn} do
      conn = get(conn, "/playerinfo")
      assert conn.status == 404
    end

    test "GET /OPTOUT resolves like /OptOut", %{conn: conn} do
      conn = get(conn, "/OPTOUT")
      assert html_response(conn, 200) =~ "Missing account or opt out key."
    end

    test "a bare segment shorter than a legacy prefix 404s cleanly instead of crashing the casing normalizer",
         %{conn: conn} do
      for path <- ["/tournament", "/player-info", "/game", "/t"] do
        assert get(conn, path).status == 404
      end
    end

    test "/game-manua normalizes to Game-manua and hits the board LiveView, which redirects home on a bad id (not a router 404)",
         %{conn: conn} do
      conn = get(conn, "/game-manua")
      assert redirected_to(conn) == "/"
    end
  end

  describe "default {controller=Home}/{action=Index}/{id?} — only its existing concrete instantiations" do
    test "GET /Home renders the same home page as / (GIF-33: real content, not the Phoenix placeholder)",
         %{conn: conn} do
      conn = get(conn, "/Home")
      assert html_response(conn, 200) =~ "GLOBAL COMBAT"
    end

    test "GET /Home/Index renders the same home page as /", %{conn: conn} do
      conn = get(conn, "/Home/Index")
      assert html_response(conn, 200) =~ "GLOBAL COMBAT"
    end

    test "GET /home/index (both segments lowercase) still resolves", %{conn: conn} do
      conn = get(conn, "/home/index")
      assert html_response(conn, 200) =~ "GLOBAL COMBAT"
    end
  end

  describe "id sourced from a query string on the id-less /PlayerInfo shortcut" do
    import GlobalCombat.AccountsFixtures

    test "GET /PlayerInfo?id=<id> resolves the id, same as the model-bound int on the old HomeController.PlayerInfo(int id)",
         %{conn: conn} do
      account = account_fixture()
      conn = get(conn, "/PlayerInfo?id=#{account.id}")
      assert html_response(conn, 200) =~ account.name
    end

    test "GET /PlayerInfo?id=684316 404s when no such account exists, same as the legacy action's null-row guard",
         %{conn: conn} do
      conn = get(conn, "/PlayerInfo?id=684316")
      assert conn.status == 404
    end

    test "GET /PlayerInfo?id=abc 404s on a non-integer id, same as /Player-Info-abc", %{
      conn: conn
    } do
      conn = get(conn, "/PlayerInfo?id=abc")
      assert conn.status == 404
    end
  end
end

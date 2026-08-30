defmodule GlobalCombatWeb.LegacyRoutesTest do
  @moduledoc """
  GIF-31: globalcombat.com has been live since 2001-01-22, and every path
  below is a real inbound link, bookmark, or search result. Asserts that
  every explicit route in `Web/Program.cs` still resolves in the Phoenix
  router, with the same capitalised-hyphenated shape and the same ids
  (`game.AUTO_INCREMENT` is at 684316 — ids are never renumbered).

  This is deliberately a router-shape test, not a feature test: most of the
  controllers below are still thin stubs (GIF-31 only covers the router)
  that echo back the id/action they resolved, which is enough to prove the
  route matched the right controller with the right params. `Tournament-:id`
  is the exception -- `TourneyController` is a real port as of GIF-32, so
  those cases assert against a real tourney fixture instead of a stub echo.
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
    test "GET /Game-:id defaults action to Index", %{conn: conn} do
      conn = get(conn, "/Game-684316")
      assert text_response(conn, 200) == "Game 684316 action=Index"
    end

    test "GET /Game-:id/:action resolves an arbitrary action", %{conn: conn} do
      conn = get(conn, "/Game-684316/Stats")
      assert text_response(conn, 200) == "Game 684316 action=Stats"
    end

    test "GET /Game-:id 404s on a non-integer id", %{conn: conn} do
      conn = get(conn, "/Game-abc")
      assert conn.status == 404
    end

    test "GET /Game-:id/ resolves with a trailing slash, as the old app's own links used", %{
      conn: conn
    } do
      conn = get(conn, "/Game-684316/")
      assert text_response(conn, 200) == "Game 684316 action=Index"
    end
  end

  describe "Player-Info-{id:int}" do
    test "GET /Player-Info-:id resolves the id", %{conn: conn} do
      conn = get(conn, "/Player-Info-684316")
      assert text_response(conn, 200) == "PlayerInfo 684316"
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
    test "GET /Create-Game", %{conn: conn} do
      conn = get(conn, "/Create-Game")
      assert text_response(conn, 200) == "Create Game"
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
    test "GET /Game-Manual", %{conn: conn} do
      conn = get(conn, "/Game-Manual")
      assert text_response(conn, 200) == "GameManual"
    end

    test "GET /Send-Message", %{conn: conn} do
      conn = get(conn, "/Send-Message")
      assert text_response(conn, 200) == "SendMessage"
    end
  end

  describe "{action} shortcut set constrained to Messages|Stats|IpAddresses|GameManual|OptOut|PlayerInfo|Chat|LoadChatMessages|CloseChatWindow|SendMessage" do
    test "GET /Messages", %{conn: conn} do
      conn = get(conn, "/Messages")
      assert text_response(conn, 200) == "Messages"
    end

    test "GET /Stats", %{conn: conn} do
      conn = get(conn, "/Stats")
      assert text_response(conn, 200) == "Stats"
    end

    test "GET /IpAddresses (moderation tooling, load-bearing)", %{conn: conn} do
      conn = get(conn, "/IpAddresses")
      assert text_response(conn, 200) == "IpAddresses"
    end

    test "GET /GameManual", %{conn: conn} do
      conn = get(conn, "/GameManual")
      assert text_response(conn, 200) == "GameManual"
    end

    test "GET /OptOut (email-preference endpoint, load-bearing)", %{conn: conn} do
      conn = get(conn, "/OptOut")
      assert text_response(conn, 200) == "OptOut"
    end

    test "GET /PlayerInfo (no id — optional on the shortcut route)", %{conn: conn} do
      conn = get(conn, "/PlayerInfo")
      assert text_response(conn, 200) == "PlayerInfo"
    end

    test "GET /Chat", %{conn: conn} do
      conn = get(conn, "/Chat")
      assert text_response(conn, 200) == "Chat"
    end

    test "GET /LoadChatMessages", %{conn: conn} do
      conn = get(conn, "/LoadChatMessages")
      assert text_response(conn, 200) == "LoadChatMessages"
    end

    test "GET /CloseChatWindow", %{conn: conn} do
      conn = get(conn, "/CloseChatWindow")
      assert text_response(conn, 200) == "CloseChatWindow"
    end

    test "GET /SendMessage", %{conn: conn} do
      conn = get(conn, "/SendMessage")
      assert text_response(conn, 200) == "SendMessage"
    end
  end

  describe "case-insensitive matching (ASP.NET Core's default routing behavior)" do
    test "GET /game-684316 resolves like /Game-684316", %{conn: conn} do
      conn = get(conn, "/game-684316")
      assert text_response(conn, 200) == "Game 684316 action=Index"
    end

    test "GET /GAME-684316 resolves like /Game-684316", %{conn: conn} do
      conn = get(conn, "/GAME-684316")
      assert text_response(conn, 200) == "Game 684316 action=Index"
    end

    test "GET /player-info-684316 resolves like /Player-Info-684316", %{conn: conn} do
      conn = get(conn, "/player-info-684316")
      assert text_response(conn, 200) == "PlayerInfo 684316"
    end

    test "GET /tournament-:id resolves like /Tournament-:id", %{conn: conn} do
      tourney = tourney_fixture()
      conn = get(conn, "/tournament-#{tourney.id}")
      assert html_response(conn, 200) =~ tourney.name
    end

    test "GET /game-manual resolves like /Game-Manual", %{conn: conn} do
      conn = get(conn, "/game-manual")
      assert text_response(conn, 200) == "GameManual"
    end

    test "GET /playerinfo resolves like /PlayerInfo", %{conn: conn} do
      conn = get(conn, "/playerinfo")
      assert text_response(conn, 200) == "PlayerInfo"
    end

    test "GET /OPTOUT resolves like /OptOut", %{conn: conn} do
      conn = get(conn, "/OPTOUT")
      assert text_response(conn, 200) == "OptOut"
    end

    test "a bare segment shorter than a legacy prefix 404s cleanly instead of crashing the casing normalizer",
         %{conn: conn} do
      for path <- ["/tournament", "/player-info", "/game", "/game-manua", "/t"] do
        assert get(conn, path).status == 404
      end
    end
  end

  describe "default {controller=Home}/{action=Index}/{id?} — only its existing concrete instantiations" do
    test "GET /Home renders the same home page as /", %{conn: conn} do
      conn = get(conn, "/Home")
      assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
    end

    test "GET /Home/Index renders the same home page as /", %{conn: conn} do
      conn = get(conn, "/Home/Index")
      assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
    end

    test "GET /home/index (both segments lowercase) still resolves", %{conn: conn} do
      conn = get(conn, "/home/index")
      assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
    end
  end

  describe "id sourced from a query string on the id-less /PlayerInfo shortcut" do
    test "GET /PlayerInfo?id=684316 resolves the id, same as the model-bound int on the old HomeController.PlayerInfo(int id)",
         %{conn: conn} do
      conn = get(conn, "/PlayerInfo?id=684316")
      assert text_response(conn, 200) == "PlayerInfo 684316"
    end

    test "GET /PlayerInfo?id=abc 404s on a non-integer id, same as /Player-Info-abc", %{
      conn: conn
    } do
      conn = get(conn, "/PlayerInfo?id=abc")
      assert conn.status == 404
    end
  end
end

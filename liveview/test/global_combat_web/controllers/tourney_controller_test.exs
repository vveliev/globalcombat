defmodule GlobalCombatWeb.TourneyControllerTest do
  use GlobalCombatWeb.ConnCase, async: true

  alias GlobalCombat.{Repo, Tourneys}
  alias GlobalCombat.Tourneys.Tourney

  import GlobalCombat.AccountsFixtures

  defp admin_fixture do
    account_fixture() |> Ecto.Changeset.change(admin: true) |> Repo.update!()
  end

  defp tourney_fixture(attrs \\ %{}) do
    {:ok, tourney} =
      %{"name" => "Cup", "initial_games" => 2, "game_size" => 2, "winners" => 1}
      |> Map.merge(attrs)
      |> Tourneys.create_tourney()

    tourney
  end

  test "GET /Tournament-:id 404s for an unknown tourney", %{conn: conn} do
    conn = get(conn, "/Tournament-99999999")
    assert conn.status == 404
  end

  test "GET /Tournament-:id renders the bracket for a fresh tourney", %{conn: conn} do
    tourney = tourney_fixture(%{"name" => "Fresh Cup"})
    conn = get(conn, "/Tournament-#{tourney.id}")
    assert html_response(conn, 200) =~ "Fresh Cup"
    assert html_response(conn, 200) =~ "Round 1"
  end

  test "GET /Create-Tournament redirects anonymous visitors", %{conn: conn} do
    conn = get(conn, "/Create-Tournament")
    assert redirected_to(conn) == "/"
  end

  test "GET /Create-Tournament renders the form for an admin", %{conn: conn} do
    conn = conn |> log_in_account(admin_fixture()) |> get("/Create-Tournament")
    assert html_response(conn, 200) =~ "Create a New Tourney"
  end

  test "POST /Create-Tournament creates a tourney and redirects to it", %{conn: conn} do
    conn =
      conn
      |> log_in_account(admin_fixture())
      |> post("/Create-Tournament", %{
        "tourney" => %{
          "name" => "New Cup",
          "initial_games" => "4",
          "game_size" => "2",
          "winners" => "1"
        }
      })

    assert redirected_to(conn) =~ ~r{^/Tournament-\d+$}
    assert Repo.get_by(Tourney, name: "New Cup")
  end

  test "POST /Create-Tournament re-renders the form with errors", %{conn: conn} do
    conn =
      conn
      |> log_in_account(admin_fixture())
      |> post("/Create-Tournament", %{
        "tourney" => %{
          "name" => "Bad Cup",
          "initial_games" => "3",
          "game_size" => "2",
          "winners" => "1"
        }
      })

    assert html_response(conn, 200) =~ "must be a power of two"
  end

  test "join then quit round-trips through the bracket view", %{conn: conn} do
    tourney = tourney_fixture()
    account = account_fixture()
    conn = log_in_account(conn, account)

    conn = post(conn, "/Tournament-#{tourney.id}/Join")
    assert html_response(conn, 200) =~ "You have joined this tournament."
    assert Tourneys.playing?(tourney, account.id)

    conn = post(conn, "/Tournament-#{tourney.id}/Quit")
    assert html_response(conn, 200) =~ "You quit this tournament."
    refute Tourneys.playing?(tourney, account.id)
  end

  test "the last join auto-starts the tourney", %{conn: conn} do
    tourney = tourney_fixture()

    [a, b, c, d] = for _ <- 1..4, do: account_fixture()

    for account <- [a, b, c] do
      conn |> log_in_account(account) |> post("/Tournament-#{tourney.id}/Join")
    end

    conn = conn |> log_in_account(d) |> post("/Tournament-#{tourney.id}/Join")
    assert html_response(conn, 200) =~ "Tournament Started"
    assert Tourneys.get_tourney!(tourney.id).status == :running
  end

  defp fill(tourney, count) do
    for _ <- 1..count, do: Tourneys.join_tournament(tourney, account_fixture().id)
  end

  test "admin POST Start starts a full tourney", %{conn: conn} do
    tourney = tourney_fixture(%{"auto_start" => false})
    fill(tourney, 4)

    conn = conn |> log_in_account(admin_fixture()) |> post("/Tournament-#{tourney.id}/Start")

    assert html_response(conn, 200) =~ "Tournament Started"
    assert Tourneys.get_tourney!(tourney.id).status == :running
  end

  test "admin POST Start refuses a partly filled tourney", %{conn: conn} do
    tourney = tourney_fixture(%{"auto_start" => false})
    fill(tourney, 1)

    conn = conn |> log_in_account(admin_fixture()) |> post("/Tournament-#{tourney.id}/Start")

    assert html_response(conn, 200) =~ "every seat is filled"
    assert Tourneys.get_tourney!(tourney.id).status == :new
  end

  test "a second Start shows an error instead of crashing", %{conn: conn} do
    tourney = tourney_fixture(%{"auto_start" => false})
    fill(tourney, 4)
    conn = log_in_account(conn, admin_fixture())

    post(conn, "/Tournament-#{tourney.id}/Start")
    conn = post(conn, "/Tournament-#{tourney.id}/Start")

    assert html_response(conn, 200) =~ "already started"
  end

  test "admin POST Kill deletes the tourney", %{conn: conn} do
    tourney = tourney_fixture()

    conn = conn |> log_in_account(admin_fixture()) |> post("/Tournament-#{tourney.id}/Kill")

    assert redirected_to(conn) == "/"
    assert Tourneys.get_tourney(tourney.id) == nil
  end

  test "non-admin POST Start/Kill do nothing", %{conn: conn} do
    tourney = tourney_fixture(%{"auto_start" => false})
    fill(tourney, 4)
    conn = log_in_account(conn, account_fixture())

    post(conn, "/Tournament-#{tourney.id}/Start")
    post(conn, "/Tournament-#{tourney.id}/Kill")

    assert Tourneys.get_tourney!(tourney.id).status == :new
  end

  test "GET requests to the old state-changing URLs change nothing", %{conn: conn} do
    tourney = tourney_fixture(%{"auto_start" => false})
    fill(tourney, 3)
    account = account_fixture()
    admin_conn = log_in_account(conn, admin_fixture())

    assert_error_sent 404, fn ->
      get(log_in_account(conn, account), "/Tournament-#{tourney.id}/Join")
    end

    assert_error_sent 404, fn ->
      get(log_in_account(conn, account), "/Tournament-#{tourney.id}/Quit")
    end

    get(admin_conn, "/Tournament-#{tourney.id}?StartTourney=1")
    get(admin_conn, "/Tournament-#{tourney.id}?KillTourney=1")

    assert Tourneys.get_tourney!(tourney.id).status == :new
    assert Tourneys.current_players(tourney) == 3
  end
end

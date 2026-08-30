defmodule GlobalCombatWeb.GameCreateLiveTest do
  @moduledoc """
  GIF-93: proves the Create-Game form exposes and submits all 9 legacy settings
  (`Views/Game/Create.cshtml`/`GameController.Create`), not just the 5 that shipped
  with GIF-30 — Training Mode, Turn Timeout Length, Minimum Army Bonus, and Private
  Invite Only were missing entirely.
  """

  use GlobalCombatWeb.ConnCase, async: true

  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Games.Live, as: Games

  test "renders all 9 legacy fields", %{conn: conn} do
    account = account_fixture()
    {:ok, _view, html} = conn |> log_in_account(account) |> live(~p"/Create-Game")

    assert html =~ "Training Mode"
    assert html =~ "Max Number of Players"
    assert html =~ "Map"
    assert html =~ "Turn Timeout Length"
    assert html =~ "Fog of War"
    assert html =~ "Minimum Army Bonus"
    assert html =~ "Reverse Attack Order"
    assert html =~ "Non-Random Attacks"
    assert html =~ "Private Invite Only"
  end

  test "submitting the form creates a game with the chosen settings and seats the creator as player 1",
       %{conn: conn} do
    account = account_fixture()
    {:ok, view, _html} = conn |> log_in_account(account) |> live(~p"/Create-Game")

    assert {:error, {:live_redirect, %{to: "/Game-" <> game_id_str}}} =
             view
             |> form("form[phx-submit=create]", %{
               "map_name" => "elements",
               "max_players" => "4",
               "turn_length_minutes" => "60",
               "is_fogged" => "true",
               "minimum_armies" => "1",
               "reverse_attack_order" => "true",
               "is_non_random" => "true",
               "is_private" => "true"
             })
             |> render_submit()

    game_id = String.to_integer(game_id_str)

    {:lobby, view_state} = Games.player_view(game_id, account.id)
    assert view_state.viewer_number == 1
    assert view_state.map_name == :elements
    assert view_state.max_players == 4
    assert length(view_state.players) == 1
  end

  test "training mode forces 2 players and auto-joins the reserved Computer account as player 2",
       %{conn: conn} do
    account = account_fixture()
    {:ok, view, _html} = conn |> log_in_account(account) |> live(~p"/Create-Game")

    assert {:error, {:live_redirect, %{to: "/Game-" <> game_id_str}}} =
             view
             |> form("form[phx-submit=create]", %{"is_training" => "true", "max_players" => "6"})
             |> render_submit()

    game_id = String.to_integer(game_id_str)

    {:lobby, view_state} = Games.player_view(game_id, account.id)
    assert view_state.max_players == 2
    assert Enum.map(view_state.players, & &1.name) == [account.name, "Computer"]
  end
end

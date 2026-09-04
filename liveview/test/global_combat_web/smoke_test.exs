defmodule GlobalCombatWeb.SmokeTest do
  @moduledoc """
  One end-to-end pass through the player-facing path, the way a new visitor meets it:
  register -> Create Game (Training Mode) -> Start -> click two territories to queue an attack
  -> End Turn -> turn 2 resolves -> the game shows up under "Your Current Games" on Home.

  Every bug GIF-107/GIF-108's hands-on QA found (GIF-111 clicks did nothing, GIF-114 stubbed
  actions, GIF-118 the AI ordering the human's armies, GIF-122 no end state) was a wiring gap
  between surfaces that each had their own green unit tests. This is the test that fails when
  the seams come apart, so it deliberately drives the real controller, LiveView events and
  `Games.Server` together instead of any one of them in isolation.
  """

  use GlobalCombatWeb.ConnCase, async: true

  import GlobalCombat.GamesTestHelpers

  alias GlobalCombat.Accounts
  alias GlobalCombat.Games.Live, as: Games

  test "a new player can register, create a training game, attack, and see turn 2 resolve",
       %{conn: conn} do
    name = "smoke#{System.unique_integer([:positive])}"

    # --- register (plain controller form, logs the account in) ---------------------------
    conn =
      post(conn, ~p"/account/register", %{
        "account" => %{
          "name" => name,
          "email" => "#{name}@example.com",
          "password" => "correcthorse",
          "password_confirmation" => "correcthorse"
        }
      })

    assert redirected_to(conn) == ~p"/"
    account = Accounts.get_account_by_login(name)
    assert account

    # --- Create Game (LiveView form) -------------------------------------------------------
    {:ok, create_view, _html} = live(conn, ~p"/Create-Game")

    assert {:error, {:live_redirect, %{to: "/Game-" <> id}}} =
             create_view
             |> form("main form", %{
               "is_training" => "true",
               "max_players" => "2",
               "map_name" => "original",
               "turn_length_minutes" => "1",
               "minimum_armies" => "3"
             })
             |> render_submit()

    game_id = String.to_integer(id)

    # --- lobby: the creator is seated with the Computer opponent ---------------------------
    {:ok, game_view, _html} = live(conn, ~p"/Game-#{game_id}")
    assert has_element?(game_view, "#game-status", "Waiting for players")
    assert has_element?(game_view, "#game-status", "2/2 joined")
    assert has_element?(game_view, "#lobby-players li", "Player 1: #{name}")
    assert has_element?(game_view, "#lobby-players li", "Player 2: Computer")

    # --- start: turn 1, the human is Thinking and the Computer has already moved -----------
    render_click(game_view, "start")
    sync_game(game_id, game_view)
    assert has_element?(game_view, "#game-status", "Turn 1")
    assert has_element?(game_view, "#game-status", "In progress")
    assert has_element?(game_view, "#game-board", "Region Bonuses")
    assert has_element?(game_view, "#turn-controls button", "End Turn")

    # --- queue an attack by clicking an owned territory, then an adjacent enemy one -------
    {:playing, view} = Games.player_view(game_id, account.id)
    {source, target} = attackable_pair(view)

    render_click(game_view, "select_area", %{"area" => to_string(source.number)})
    assert has_element?(game_view, "#order-form")
    assert has_element?(game_view, "#game-board", "Assign new armies or select a target area")

    render_click(game_view, "select_area", %{"area" => to_string(target.number)})
    assert has_element?(game_view, "#game-board", "Attack #{target.name} with how many armies?")

    game_view
    |> form("#order-form", %{"amount" => to_string(source.armies - 1)})
    |> render_submit()

    # --- end turn: with the Computer already Done, the turn resolves right away ------------
    render_click(game_view, "done")
    sync_game(game_id, game_view)
    assert has_element?(game_view, "#game-status", "Turn 2")
    refute has_element?(game_view, "#game-over")

    # The attack actually resolved: the source territory spent its armies.
    {:playing, after_view} = Games.player_view(game_id, account.id)
    assert Enum.find(after_view.areas, &(&1.number == source.number)).armies < source.armies

    # --- Home lists it under the player's current games ------------------------------------
    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ "Your Current Games"
    assert home =~ "Game ##{game_id}"
  end

  # An owned, visible territory with at least 2 armies and an adjacent enemy territory —
  # both always exist on turn 1 of a two-player World War I map deal.
  defp attackable_pair(view) do
    owned = Enum.filter(view.areas, &(&1.owner_number == view.viewer_number and &1.armies >= 2))

    Enum.find_value(owned, fn source ->
      target =
        Enum.find(view.areas, fn a ->
          a.number in source.adjacent and a.owner_number != view.viewer_number
        end)

      target && {source, target}
    end) || flunk("no owned territory with an adjacent enemy on turn 1")
  end
end

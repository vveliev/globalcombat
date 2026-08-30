defmodule GlobalCombat.Games.PlayerViewTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Games.PlayerView

  # Map :original: area 1 (Alaska) links to [2, 3, 37]; area 5 (Quebec) links to
  # [2, 4, 6, 7, 9] — not adjacent to area 1. Used throughout to exercise both the
  # "adjacent to an owned area" and "nowhere near anything I own" fog cases.
  defp game(opts \\ []) do
    is_fogged = Keyword.get(opts, :is_fogged, true)

    # A real Engine.Game always carries every area on the map, even ones no test
    # assertion cares about — owns_adjacent?/3 walks inbound neighbors regardless of
    # which areas the test is actually exercising, so a partial area map here would
    # KeyError instead of testing anything.
    areas =
      for number <- 1..GlobalCombat.Engine.MapInfo.num_areas(:original), into: %{} do
        {number, %Engine.Area{number: number, owner_number: nil, armies: 5}}
      end
      |> Map.merge(%{
        1 => %Engine.Area{number: 1, owner_number: 1, armies: 5, assigned_armies: 3},
        2 => %Engine.Area{number: 2, owner_number: 2, armies: 7, assigned_armies: 2},
        5 => %Engine.Area{number: 5, owner_number: 2, armies: 9, assigned_armies: 4}
      })

    players = %{
      1 => %Engine.Player{number: 1, account_id: 101, name: "Alice", areas: 1, armies: 8},
      2 => %Engine.Player{number: 2, account_id: 102, name: "Bob", areas: 2, armies: 16}
    }

    engine = %Engine{map_name: :original, turn: 3, areas: areas, players: players}
    {engine, is_fogged}
  end

  describe "fog of war" do
    test "the owner always sees their own area's real owner and armies (base + assigned)" do
      {engine, is_fogged} = game()
      view = PlayerView.build(engine, 1, game_id: 1, is_fogged: is_fogged)

      area1 = Enum.find(view.areas, &(&1.number == 1))
      assert area1.visible
      assert area1.owner_number == 1
      assert area1.armies == 5 + 3
    end

    test "a non-owner adjacent to a fogged area sees its real owner/armies, but not the owner's queued assignment" do
      {engine, is_fogged} = game()
      view = PlayerView.build(engine, 1, game_id: 1, is_fogged: is_fogged)

      area2 = Enum.find(view.areas, &(&1.number == 2))
      assert area2.visible
      assert area2.owner_number == 2
      # base armies only (7), not 7 + 2 assigned_armies — that bonus is owner-only.
      assert area2.armies == 7
    end

    test "a non-owner with no adjacency to a fogged area sees neither its owner nor its armies" do
      {engine, is_fogged} = game()
      view = PlayerView.build(engine, 1, game_id: 1, is_fogged: is_fogged)

      area5 = Enum.find(view.areas, &(&1.number == 5))
      refute area5.visible
      assert area5.owner_number == nil
      assert area5.armies == nil
    end

    test "a spectator (viewer_number: nil) sees exactly what a fogged non-owner sees" do
      {engine, is_fogged} = game()
      view = PlayerView.build(engine, nil, game_id: 1, is_fogged: is_fogged)

      area5 = Enum.find(view.areas, &(&1.number == 5))
      refute area5.visible
      assert area5.owner_number == nil
      assert area5.armies == nil
    end

    test "a non-fogged game reveals every area's owner/armies to everyone, but still hides another owner's queued assignment" do
      {engine, is_fogged} = game(is_fogged: false)
      view = PlayerView.build(engine, 1, game_id: 1, is_fogged: is_fogged)

      area5 = Enum.find(view.areas, &(&1.number == 5))
      assert area5.visible
      assert area5.owner_number == 2
      # base armies only (9), not 9 + 4 — the assignment bonus is still owner-only
      # even when fog of war is off entirely.
      assert area5.armies == 9
    end
  end

  describe "player roll-ups" do
    test "are never fog-gated — every player's totals are visible to every viewer, including spectators" do
      {engine, is_fogged} = game()
      view = PlayerView.build(engine, nil, game_id: 1, is_fogged: is_fogged)

      bob = Enum.find(view.players, &(&1.number == 2))
      assert bob.armies == 16
      assert bob.areas == 2
    end
  end
end

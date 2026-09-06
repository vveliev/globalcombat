defmodule GlobalCombat.Games.PlayerViewTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Games.PlayerView
  alias GlobalCombat.Games.TurnLog

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

  # Turn-resolution event-visibility fixtures: a full 1..42 area map (same reasoning as `game/1` above —
  # `MapInfo.inbounds/2` walks real map topology regardless of which areas a test cares about) with
  # only the given `overrides` non-default, plus a minimal two-player roster.
  defp full_areas(overrides) do
    base =
      for number <- 1..GlobalCombat.Engine.MapInfo.num_areas(:original), into: %{} do
        {number, %Engine.Area{number: number, owner_number: nil, armies: 5}}
      end

    Map.merge(base, overrides)
  end

  defp owners(areas), do: Map.new(areas, fn {number, area} -> {number, area.owner_number} end)

  defp engine_with(area_overrides) do
    %Engine{
      map_name: :original,
      turn: 3,
      areas: full_areas(area_overrides),
      players: %{
        1 => %Engine.Player{number: 1, account_id: 101, name: "Alice"},
        2 => %Engine.Player{number: 2, account_id: 102, name: "Bob"}
      }
    }
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

  describe "orders (pending-orders overlay fog boundary)" do
    test "the owner sees their own queued attack/transfer" do
      {engine, is_fogged} = game()

      engine =
        put_in(engine.areas[1], %Engine.Area{
          number: 1,
          owner_number: 1,
          armies: 5,
          command: :attack,
          target_number: 2,
          amount: 12
        })

      view = PlayerView.build(engine, 1, game_id: 1, is_fogged: is_fogged)
      area1 = Enum.find(view.areas, &(&1.number == 1))

      assert area1.order == %{command: :attack, target: 2, amount: 12}
    end

    test "a non-owner never sees another player's queued order, even when the area itself is visible" do
      {engine, is_fogged} = game()

      engine =
        put_in(engine.areas[2], %Engine.Area{
          number: 2,
          owner_number: 2,
          armies: 7,
          command: :transfer,
          target_number: 5,
          amount: 3
        })

      view = PlayerView.build(engine, 1, game_id: 1, is_fogged: is_fogged)
      area2 = Enum.find(view.areas, &(&1.number == 2))

      assert area2.visible
      assert area2.order == nil
    end

    test "a spectator never sees anyone's queued order" do
      {engine, is_fogged} = game()

      engine =
        put_in(engine.areas[1], %Engine.Area{
          number: 1,
          owner_number: 1,
          armies: 5,
          command: :attack,
          target_number: 2,
          amount: 12
        })

      view = PlayerView.build(engine, nil, game_id: 1, is_fogged: is_fogged)
      area1 = Enum.find(view.areas, &(&1.number == 1))

      assert area1.order == nil
    end

    test "an owned area with no queued command has a nil order, not a :none sentinel" do
      {engine, is_fogged} = game()
      view = PlayerView.build(engine, 1, game_id: 1, is_fogged: is_fogged)

      area1 = Enum.find(view.areas, &(&1.number == 1))
      assert area1.order == nil
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

  describe "name/adjacent (GIF-81 accessible board table)" do
    test "every area carries its display name and full map-topology adjacency, regardless of fog" do
      {engine, is_fogged} = game()
      view = PlayerView.build(engine, 1, game_id: 1, is_fogged: is_fogged)

      area1 = Enum.find(view.areas, &(&1.number == 1))
      assert area1.name == "Alaska"
      assert Enum.sort(area1.adjacent) == [2, 3, 37]

      # area 5 (Quebec) is fog-hidden from viewer 1 — adjacency is still full,
      # unlike owner_number/armies, because map topology isn't secret.
      area5 = Enum.find(view.areas, &(&1.number == 5))
      refute area5.visible
      assert area5.name == "Quebec"
      assert Enum.sort(area5.adjacent) == [2, 4, 6, 7, 9]
    end
  end

  describe "turn-resolution event visibility" do
    test "an attack between two areas invisible to the viewer, before and after, is omitted" do
      # Areas 5 (Quebec) and 9 (Greenland) are both owned by player 2 and neither is adjacent
      # to anything player 1 owns — the same "nowhere near anything I own" case the
      # area-visibility tests above cover, applied to an event instead of a single area.
      engine =
        engine_with(%{
          5 => %Engine.Area{number: 5, owner_number: 2, armies: 5},
          9 => %Engine.Area{number: 9, owner_number: 2, armies: 5}
        })

      before_owners = owners(engine.areas)

      view =
        PlayerView.build(engine, 1,
          game_id: 1,
          is_fogged: true,
          last_turn_log: %TurnLog{
            turn: 3,
            events: [{:attack, 5, 9, 10, 1, 5, true}],
            before_owners: before_owners
          }
        )

      assert view.last_turn_events == []
    end

    test "an attack whose attacker area the viewer owns is exposed" do
      engine =
        engine_with(%{
          1 => %Engine.Area{number: 1, owner_number: 1, armies: 5},
          3 => %Engine.Area{number: 3, owner_number: 2, armies: 5}
        })

      before_owners = owners(engine.areas)
      event = {:attack, 1, 3, 4, 0, 4, false}

      view =
        PlayerView.build(engine, 1,
          game_id: 1,
          is_fogged: true,
          last_turn_log: %TurnLog{turn: 3, events: [event], before_owners: before_owners}
        )

      assert view.last_turn_events == [event]
    end

    test "an event visible only through pre-turn ownership (an adjacency lost this turn) is still exposed" do
      # Player 1 owned area 4 (adjacent to area 5) going into the turn but not anymore by the
      # time this render reads `engine` — the log's `before_owners` is what still remembers it.
      engine = engine_with(%{5 => %Engine.Area{number: 5, owner_number: 2, armies: 5}})
      before_owners = engine.areas |> owners() |> Map.put(4, 1)
      event = {:assign, 5, 3}

      view =
        PlayerView.build(engine, 1,
          game_id: 1,
          is_fogged: true,
          last_turn_log: %TurnLog{turn: 3, events: [event], before_owners: before_owners}
        )

      assert view.last_turn_events == [event]
    end

    test "an event visible only through post-turn ownership (an adjacency gained this turn) is still exposed" do
      engine =
        engine_with(%{
          4 => %Engine.Area{number: 4, owner_number: 1, armies: 5},
          5 => %Engine.Area{number: 5, owner_number: 2, armies: 5}
        })

      before_owners = engine.areas |> owners() |> Map.put(4, nil)
      event = {:assign, 5, 3}

      view =
        PlayerView.build(engine, 1,
          game_id: 1,
          is_fogged: true,
          last_turn_log: %TurnLog{turn: 3, events: [event], before_owners: before_owners}
        )

      assert view.last_turn_events == [event]
    end

    test ":eliminated and :ended touch no area and are exposed regardless of fog or ownership" do
      engine = engine_with(%{})
      before_owners = owners(engine.areas)
      events = [{:eliminated, 2}, {:ended, 1}]

      view =
        PlayerView.build(engine, nil,
          game_id: 1,
          is_fogged: true,
          last_turn_log: %TurnLog{turn: 3, events: events, before_owners: before_owners}
        )

      assert view.last_turn_events == events
    end

    test "a non-fogged game exposes every event unfiltered" do
      engine =
        engine_with(%{
          5 => %Engine.Area{number: 5, owner_number: 2, armies: 5},
          9 => %Engine.Area{number: 9, owner_number: 2, armies: 5}
        })

      event = {:attack, 5, 9, 10, 1, 5, true}

      view =
        PlayerView.build(engine, 1,
          game_id: 1,
          is_fogged: false,
          last_turn_log: %TurnLog{turn: 3, events: [event], before_owners: %{}}
        )

      assert view.last_turn_events == [event]
    end

    test "a log stamped for a different turn than the engine's current one is dropped entirely" do
      # Simulates a stale log surviving a partial write or a pre-column rehydrate — the events
      # would otherwise pass the fog rule below (viewer 1 owns both endpoints), so only the
      # turn-stamp check protects against describing the wrong turn.
      engine =
        engine_with(%{
          1 => %Engine.Area{number: 1, owner_number: 1, armies: 5},
          3 => %Engine.Area{number: 3, owner_number: 1, armies: 5}
        })

      before_owners = owners(engine.areas)
      event = {:transfer, 1, 3, 2}

      view =
        PlayerView.build(engine, 1,
          game_id: 1,
          is_fogged: true,
          last_turn_log: %TurnLog{turn: 2, events: [event], before_owners: before_owners}
        )

      assert view.last_turn_events == []
    end

    test "a fogged game with an empty before_owners snapshot omits rather than raises" do
      # Guards `before_owners_lookup/1`'s `Map.get/3` default: a log whose turn does match (so it
      # isn't dropped by the check above) but whose `before_owners` has no entry for an event's
      # area used to `Map.fetch!/2` and crash instead of just hiding the event.
      engine =
        engine_with(%{
          5 => %Engine.Area{number: 5, owner_number: 2, armies: 5},
          9 => %Engine.Area{number: 9, owner_number: 2, armies: 5}
        })

      event = {:attack, 5, 9, 10, 1, 5, true}

      view =
        PlayerView.build(engine, 1,
          game_id: 1,
          is_fogged: true,
          last_turn_log: %TurnLog{turn: 3, events: [event], before_owners: %{}}
        )

      assert view.last_turn_events == []
    end

    test "a spectator's fogged, empty-before_owners log omits an owned hidden area's event rather than raising" do
      # Same guard as above, but for `viewer_number: nil` (a spectator) specifically — the
      # sentinel `before_owners_lookup/1` defaults to must not compare equal to `nil`, or a
      # spectator would spuriously "match" every area missing from `before_owners`.
      engine =
        engine_with(%{
          5 => %Engine.Area{number: 5, owner_number: 2, armies: 5},
          9 => %Engine.Area{number: 9, owner_number: 2, armies: 5}
        })

      event = {:attack, 5, 9, 10, 1, 5, true}

      view =
        PlayerView.build(engine, nil,
          game_id: 1,
          is_fogged: true,
          last_turn_log: %TurnLog{turn: 3, events: [event], before_owners: %{}}
        )

      assert view.last_turn_events == []
    end
  end
end

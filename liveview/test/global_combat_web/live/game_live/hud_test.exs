defmodule GlobalCombatWeb.GameLive.HudTest do
  use ExUnit.Case, async: true

  alias GlobalCombatWeb.GameLive.Hud

  defp area(number, owner, pending, order \\ nil) do
    %{
      number: number,
      owner_number: owner,
      visible: true,
      armies: 5 + pending,
      pending_armies: pending,
      order: order
    }
  end

  defp view(areas, me \\ %{}) do
    player =
      Map.merge(%{number: 1, done: false, eliminated: false, unassigned_armies: 0}, me)

    %{viewer_number: 1, areas: areas, players: [player]}
  end

  describe "reconcile_history/2" do
    test "keeps entries that match what is queued" do
      view = view([area(1, 1, 3), area(2, 1, 5)])
      assert Hud.reconcile_history([{2, 5}, {1, 2}, {1, 1}], view) == [{2, 5}, {1, 2}, {1, 1}]
    end

    test "trims, newest first, to what is really queued and drops areas with nothing left" do
      view = view([area(1, 1, 2), area(2, 1, 0)])
      assert Hud.reconcile_history([{2, 5}, {1, 5}, {1, 1}], view) == [{1, 2}]
    end

    test "adds what the history doesn't account for as its oldest entries" do
      view = view([area(1, 1, 4), area(3, 1, 2), area(2, 2, 0)])
      assert Hud.reconcile_history([{1, 1}], view) == [{1, 1}, {1, 3}, {3, 2}]
    end

    test "is empty once nothing is queued" do
      assert Hud.reconcile_history([{1, 5}], view([area(1, 1, 0)])) == []
    end
  end

  describe "turn_phase/2" do
    test "walks watching, placing, ordering and done" do
      order = %{command: :attack, target: 2, amount: 3}
      removed = %{order | amount: 0}
      view = view([area(1, 1, 0, order), area(3, 1, 0, removed)])
      [me] = view.players

      assert Hud.turn_phase(view, nil) == :watching
      assert Hud.turn_phase(view, %{me | eliminated: true}) == :watching
      assert Hud.turn_phase(view, %{me | unassigned_armies: 4}) == {:place, 4}
      assert Hud.turn_phase(view, me) == {:orders, 1}
      assert Hud.turn_phase(view, %{me | done: true}) == :done
    end
  end

  describe "placement/4" do
    test "clamps a request to 1..hold_amount and to the pool" do
      view = view([area(1, 1, 0)], %{unassigned_armies: 3})
      [me] = view.players

      assert Hud.placement(view, me, 1, 1) == {:ok, 1}
      assert Hud.placement(view, me, 1, 50) == {:ok, 3}
      assert Hud.placement(view, %{me | unassigned_armies: 9}, 1, 50) == {:ok, Hud.hold_amount()}
      assert Hud.placement(view, me, 1, 0) == {:ok, 1}
    end

    test "refuses someone else's land, an empty pool and a player who is done" do
      view = view([area(1, 1, 0), area(2, 2, 0)], %{unassigned_armies: 3})
      [me] = view.players

      assert Hud.placement(view, me, 2, 1) == :error
      assert Hud.placement(view, %{me | unassigned_armies: 0}, 1, 1) == :error
      assert Hud.placement(view, %{me | done: true}, 1, 1) == :error
    end
  end

  describe "undo_plan/3" do
    test "keeps what came before and restores as much of the order as can still go" do
      order = %{command: :attack, target: 2, amount: 6}
      # 5 standing + 2 queued = 7 armies, order 6; undoing 1 leaves 6, so 5 can go.
      view = view([area(1, 1, 2, order)])
      [me] = view.players

      assert {:ok, %{area: 1, undone: 1, keep: 1, order: {2, 5}}} =
               Hud.undo_plan(view, me, {1, 1})
    end

    test "never undoes more than is queued, and has no order to restore when none is queued" do
      view = view([area(1, 1, 2)])
      [me] = view.players

      assert {:ok, %{undone: 2, keep: 0, order: nil}} = Hud.undo_plan(view, me, {1, 5})
    end
  end

  describe "drag_plan/4" do
    defp board(order \\ nil) do
      view([
        %{area(1, 1, 0, order) | armies: 5} |> Map.put(:adjacent, [2, 3]),
        area(2, 2, 0) |> Map.put(:adjacent, [1]),
        area(3, 1, 0) |> Map.put(:adjacent, [1]),
        area(4, 2, 0) |> Map.put(:adjacent, [])
      ])
    end

    test "queues an attack or transfer at everything the source can spare when nothing is queued" do
      view = board()
      [me] = view.players
      assert Hud.drag_plan(view, me, 1, 2) == {:queue, %{command: :attack, target: 2, amount: 4}}

      assert Hud.drag_plan(view, me, 1, 3) ==
               {:queue, %{command: :transfer, target: 3, amount: 4}}
    end

    test "reopens the same order untouched, and only drafts a different one" do
      view = board(%{command: :attack, target: 2, amount: 2})
      [me] = view.players
      assert Hud.drag_plan(view, me, 1, 2) == {:reopen, 2}
      assert Hud.drag_plan(view, me, 1, 3) == {:draft, 4}
    end

    test "refuses a non-neighbour, a foreign source and a player who is done" do
      view = board()
      [me] = view.players
      assert Hud.drag_plan(view, me, 1, 4) == :error
      assert Hud.drag_plan(view, me, 2, 1) == :error
      assert Hud.drag_plan(view, %{me | done: true}, 1, 2) == :error
    end
  end

  test "coach_line/3 words the same step for each size" do
    view = view([area(1, 1, 0)], %{unassigned_armies: 4})
    [me] = view.players

    assert Hud.coach_line(view, me, :phone) == "Tap a territory of yours to place 4 armies there"
    assert Hud.coach_line(view, me, :desktop) == "Click your territories to place 4 armies"
  end

  test "placement/4 places the whole pool for :all" do
    view = view([area(1, 1, 0)], %{unassigned_armies: 12})
    [me] = view.players
    assert Hud.placement(view, me, 1, :all) == {:ok, 12}
  end

  describe "tap_plan/3" do
    defp tap_board do
      view([
        area(1, 1, 0) |> Map.put(:adjacent, [2, 3]),
        area(2, 2, 0) |> Map.put(:adjacent, [1]),
        area(3, 1, 0) |> Map.put(:adjacent, [1]),
        area(4, 2, 0) |> Map.put(:adjacent, [])
      ])
    end

    test "selects your own territory, even a neighbour of the selected one" do
      assert Hud.tap_plan(tap_board(), nil, 1) == {:select, 1}
      assert Hud.tap_plan(tap_board(), 1, 3) == {:select, 3}
    end

    test "targets an enemy neighbour of the selection, and otherwise clears or ignores" do
      assert Hud.tap_plan(tap_board(), 1, 2) == {:target, 2}
      assert Hud.tap_plan(tap_board(), 1, 4) == :clear
      assert Hud.tap_plan(tap_board(), nil, 2) == :none
    end
  end

  describe "income/2" do
    test "is half the territories plus every region held outright" do
      # Australia is region 6 on the world map: areas 39-42.
      areas = for n <- 1..42, do: area(n, if(n in [1, 2, 39, 40, 41, 42], do: 1, else: 2), 0)
      view = %{view(areas, %{armies: 30}) | areas: areas} |> Map.put(:map_name, :original)
      [me] = view.players

      assert %{territories: 6, base: 3, bonuses: [%{name: "Australia", bonus: 2}], total: 5} =
               Hud.income(view, Map.put(me, :armies, 30))
    end

    test "never drops below the game's minimum" do
      areas = for n <- 1..42, do: area(n, if(n == 1, do: 1, else: 2), 0)
      view = view(areas) |> Map.put(:map_name, :original) |> Map.put(:minimum_armies, 3)
      [me] = view.players

      assert %{base: 0, bonuses: [], minimum: 3, total: 3} =
               Hud.income(view, Map.put(me, :armies, 5))
    end
  end

  test "next_lens/1 steps owner, region, frontier and back" do
    assert Enum.map([:owner, :region, :frontier], &Hud.next_lens/1) == [
             :region,
             :frontier,
             :owner
           ]
  end
end

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

  test "next_lens/1 steps owner, region, frontier and back" do
    assert Enum.map([:owner, :region, :frontier], &Hud.next_lens/1) == [
             :region,
             :frontier,
             :owner
           ]
  end
end

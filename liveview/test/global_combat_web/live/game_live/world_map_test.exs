defmodule GlobalCombatWeb.GameLive.WorldMapTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.GameLive.WorldMap

  # Australia on the :original map (region 6, bonus 2): a small, real region
  # (areas 39-42) rather than a synthetic one, so this exercises the actual
  # `MapInfo.areas/1` region grouping alongside the fill logic.
  @australia [39, 40, 41, 42]

  defp area(number, owner_number, visible \\ true) do
    %{number: number, owner_number: owner_number, visible: visible}
  end

  defp board_area(number, opts \\ []) do
    %{
      number: number,
      name: "Area #{number}",
      visible: true,
      owner_number: 1,
      armies: nil,
      pending_armies: 0,
      adjacent: [],
      order: nil
    }
    |> Map.merge(Map.new(opts))
  end

  defp players, do: [%{number: 1, name: "Alice"}]

  defp territory(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query_by_id("territory-1")
  end

  defp order_arrow(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query_by_id("order-1")
  end

  describe "interactive attr" do
    # Once a game has ended there is nothing left to click, so a territory
    # must stop being a focus/click target entirely rather than staying an
    # unresponsive `role="button"`. This covers `interactive={false}` actually
    # dropping the interactive attributes; `GameLiveTest` covers the
    # end-to-end "clicking one after Game Over is a no-op" behaviour.

    test "interactive (default) territories are focusable role=button click/keyboard targets" do
      assigns = %{areas: [board_area(1)], players: players()}

      html =
        rendered_to_string(~H"""
        <WorldMap.world_map map_name={:original} areas={@areas} players={@players} />
        """)

      territory = territory(html)

      assert territory |> LazyHTML.filter(~s([role="button"])) |> Enum.any?()
      assert territory |> LazyHTML.filter(~s([tabindex="0"])) |> Enum.any?()
      assert territory |> LazyHTML.filter(~s([phx-click="select_area"])) |> Enum.any?()
      assert territory |> LazyHTML.filter(".world-map-territory--interactive") |> Enum.any?()
    end

    test "interactive={false} territories have no role, tabindex, click or keyboard hook" do
      assigns = %{areas: [board_area(1)], players: players()}

      html =
        rendered_to_string(~H"""
        <WorldMap.world_map map_name={:original} areas={@areas} players={@players} interactive={false} />
        """)

      territory = territory(html)

      assert territory |> LazyHTML.filter("[role]") |> Enum.empty?()
      assert territory |> LazyHTML.filter("[tabindex]") |> Enum.empty?()
      assert territory |> LazyHTML.filter("[phx-click]") |> Enum.empty?()
      assert territory |> LazyHTML.filter("[phx-hook]") |> Enum.empty?()
      assert territory |> LazyHTML.filter(".world-map-territory--interactive") |> Enum.empty?()
    end
  end

  describe "order_arrow interactive attr" do
    # An order arrow must take the same interactive gate as a territory: once a
    # game has ended there is nothing left to edit, so the arrow must stop being
    # a focus/click/keyboard target entirely rather than staying an unresponsive
    # `role="button"` (`GameLiveTest` already covers this for territories; queued
    # orders don't normally survive a resolved turn, but the gate is unconditional
    # defense-in-depth, same as the territory one).
    defp attacking_areas do
      [
        board_area(1, order: %{command: :attack, target: 2, amount: 4}),
        board_area(2, owner_number: 2)
      ]
    end

    test "interactive (default) order arrows are focusable, keyboard-reachable role=button click targets" do
      assigns = %{areas: attacking_areas(), players: players()}

      html =
        rendered_to_string(~H"""
        <WorldMap.world_map map_name={:original} areas={@areas} players={@players} />
        """)

      arrow = order_arrow(html)

      assert arrow |> LazyHTML.filter(~s([role="button"])) |> Enum.any?()
      assert arrow |> LazyHTML.filter(~s([tabindex="0"])) |> Enum.any?()
      assert arrow |> LazyHTML.filter(~s([phx-click="select_order"])) |> Enum.any?()
      assert arrow |> LazyHTML.filter(~s([phx-hook=".TerritoryKeyboard"])) |> Enum.any?()
      assert arrow |> LazyHTML.filter(~s([data-select-event="select_order"])) |> Enum.any?()
      assert arrow |> LazyHTML.filter(".world-map-order--interactive") |> Enum.any?()
    end

    test "interactive={false} order arrows have no role, tabindex, click or keyboard hook" do
      assigns = %{areas: attacking_areas(), players: players()}

      html =
        rendered_to_string(~H"""
        <WorldMap.world_map map_name={:original} areas={@areas} players={@players} interactive={false} />
        """)

      arrow = order_arrow(html)

      assert arrow |> LazyHTML.filter("[role]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter("[tabindex]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter("[phx-click]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter("[phx-hook]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter("[data-select-event]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter(".world-map-order--interactive") |> Enum.empty?()

      # Non-interactive doesn't mean invisible — the arrow itself, its label,
      # and the amount it carries must still render.
      assert arrow |> LazyHTML.filter(~s([aria-label])) |> Enum.any?()
    end
  end

  describe "region_owner/1" do
    test "returns the shared owner when every area in the region is visible and one-owned" do
      areas = Enum.map(@australia, &area(&1, 3))
      assert WorldMap.region_owner(areas) == 3
    end

    test "returns nil when the region is split between owners (contested)" do
      areas = [area(39, 1), area(40, 1), area(41, 2), area(42, 1)]
      assert WorldMap.region_owner(areas) == nil
    end

    test "returns nil when any area in the region is fogged, even if the visible areas agree" do
      areas = [area(39, 3), area(40, 3), area(41, 3), area(42, 3, false)]
      assert WorldMap.region_owner(areas) == nil
    end

    test "returns nil when the region has an unowned area" do
      areas = [area(39, nil), area(40, 1), area(41, 1), area(42, 1)]
      assert WorldMap.region_owner(areas) == nil
    end
  end

  describe "region_owners/2" do
    test "maps every region of the map to its holder, keyed off MapInfo.areas/1" do
      areas =
        for {number, _name, _region, _links} <- GlobalCombat.Engine.MapInfo.areas(:original) do
          # Own every area except Australia's, so Australia alone reads as held.
          owner = if number in @australia, do: 5, else: number
          area(number, owner)
        end

      region_owners = WorldMap.region_owners(:original, areas)

      assert region_owners[6] == 5

      # Every other region is contested here (each area got a distinct owner_number),
      # so region_owner/1 must read every one of them as nil, not leak a single area's
      # owner through as the region's.
      for region_number <- 1..5 do
        assert region_owners[region_number] == nil
      end
    end
  end

  describe "fills/4 with the :region lens" do
    test "every area of a fully-held region fills with that owner's slot" do
      areas =
        for {number, _name, _region, _links} <- GlobalCombat.Engine.MapInfo.areas(:original) do
          owner = if number in @australia, do: 5, else: number
          area(number, owner)
        end

      fills = WorldMap.fills(:region, areas, :original, nil)

      for number <- @australia do
        assert fills[number].owner == WorldMap.owner_slot(5)
        assert fills[number].dim == false
        assert fills[number].delta == nil
      end
    end

    # Every area outside Australia gets its own distinct owner_number (irrelevant to
    # the assertion, just distinguishable) so only Australia's four areas matter here.
    defp areas_with_australia_as(australia_owners) do
      for {number, _name, _region, _links} <- GlobalCombat.Engine.MapInfo.areas(:original) do
        case Enum.find_index(@australia, &(&1 == number)) do
          nil -> area(number, number)
          index -> area(number, Enum.fetch!(australia_owners, index))
        end
      end
    end

    test "a contested region fills with the neutral owner-0 slot, not any single area's true owner" do
      areas = areas_with_australia_as([1, 2, 1, 1])

      fills = WorldMap.fills(:region, areas, :original, nil)

      for number <- @australia do
        assert fills[number].owner == WorldMap.owner_slot(nil)
      end
    end

    test "a fogged area anywhere in the region keeps the whole region neutral" do
      areas =
        areas_with_australia_as([5, 5, 5, 5])
        |> Enum.map(fn
          %{number: 41} = a -> %{a | visible: false}
          a -> a
        end)

      fills = WorldMap.fills(:region, areas, :original, nil)

      for number <- @australia do
        assert fills[number].owner == WorldMap.owner_slot(nil)
      end
    end
  end
end

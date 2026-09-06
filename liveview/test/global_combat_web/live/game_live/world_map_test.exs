defmodule GlobalCombatWeb.GameLive.WorldMapTest do
  use ExUnit.Case, async: true

  alias GlobalCombatWeb.GameLive.WorldMap

  # Australia on the :original map (region 6, bonus 2): a small, real region
  # (areas 39-42) rather than a synthetic one, so this exercises the actual
  # `MapInfo.areas/1` region grouping alongside the fill logic.
  @australia [39, 40, 41, 42]

  defp area(number, owner_number, visible \\ true) do
    %{number: number, owner_number: owner_number, visible: visible}
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

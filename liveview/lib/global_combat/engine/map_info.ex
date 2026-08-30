defmodule GlobalCombat.Engine.MapInfo do
  @moduledoc """
  Port of `GlobalCombat.Core/MapInfo.cs`'s two hardcoded maps (`original`,
  `elements`). Area/region data is transcribed programmatically from the C#
  source (parsed out of `GlobalCombat.Core/MapInfo.cs` field-for-field, not
  retyped by hand) to keep it byte-for-byte faithful to the oracle's map —
  this data has no rule logic to "port," it just has to match exactly.

  Unlike `AreaInfo.Linkup` in the original (which walks every area at load
  time to build an `Inbounds` list), inbound areas here are computed lazily
  by `inbounds/2` from the same `links` data — same result, no separate
  cached list to keep in sync.
  """

  # {number, name, region, links} — `links` is the variable-length list of
  # area numbers this area connects to (the C# source pads to a fixed 6 with
  # trailing 0s; those are dropped here since 0 is never a valid area number).
  @original_areas [
    {1, "Alaska", 1, [2, 3, 37]},
    {2, "Northern Territories", 1, [1, 3, 4, 5, 9]},
    {3, "Alberta", 1, [1, 2, 4, 6]},
    {4, "Ontario", 1, [2, 3, 5, 6, 7]},
    {5, "Quebec", 1, [2, 4, 6, 7, 9]},
    {6, "West United States", 1, [3, 4, 5, 7, 8]},
    {7, "East United States", 1, [4, 5, 6, 8]},
    {8, "Mexico", 1, [6, 7, 10]},
    {9, "Greenland", 1, [2, 5, 20]},
    {10, "Columbia", 2, [8, 11, 12]},
    {11, "Peru", 2, [10, 12, 13]},
    {12, "Brazil", 2, [10, 11, 13, 14]},
    {13, "Argentina", 2, [11, 12]},
    {14, "Algeria", 3, [12, 15, 16, 22]},
    {15, "Egypt", 3, [14, 16, 17, 27, 25]},
    {16, "Congo", 3, [14, 15, 17, 18]},
    {17, "Tanzania", 3, [15, 16, 18, 19]},
    {18, "South Africa", 3, [16, 17, 19]},
    {19, "Madagascar", 3, [17, 18]},
    {20, "Iceland", 4, [9, 21, 24]},
    {21, "United Kingdom", 4, [20, 22, 23, 24]},
    {22, "Western Europe", 4, [14, 21, 23]},
    {23, "Austria", 4, [21, 22, 24, 25]},
    {24, "Scandinavia", 4, [20, 21, 23, 25, 26]},
    {25, "Eastern Europe", 4, [15, 23, 24, 26, 27, 28]},
    {26, "Ukraine", 4, [24, 25, 28, 30]},
    {27, "Middle East", 5, [15, 25, 28, 29]},
    {28, "Iran", 5, [25, 26, 27, 29, 30]},
    {29, "India", 5, [27, 28, 30, 33]},
    {30, "Kazakhstan", 5, [26, 28, 29, 31, 32, 33]},
    {31, "Ural", 5, [30, 32, 34, 35]},
    {32, "China", 5, [30, 31, 33, 34, 38]},
    {33, "Thailand", 5, [29, 30, 32, 39]},
    {34, "Mongolia", 5, [31, 32, 35, 36, 37, 38]},
    {35, "Siberia", 5, [31, 34, 36]},
    {36, "Chersky", 5, [35, 34, 37]},
    {37, "Pevek", 5, [34, 36, 1]},
    {38, "Japan", 5, [32, 34]},
    {39, "Indonesia", 6, [40, 41, 42, 33]},
    {40, "Outback", 6, [39, 41, 42]},
    {41, "Queensland", 6, [39, 40, 42]},
    {42, "New Guinea", 6, [39, 40, 41]}
  ]

  @original_regions [
    {1, "North America", 9, 6},
    {2, "South America", 4, 3},
    {3, "Africa", 6, 4},
    {4, "Europe", 7, 7},
    {5, "Asia", 12, 9},
    {6, "Australia", 4, 2}
  ]

  @elements_areas [
    {1, "Fire Corner", 1, [5, 10, 11, 12, 13, 14]},
    {2, "Wind Corner", 1, [5, 26, 27, 28, 29, 30]},
    {3, "Earth Corner", 1, [6, 34, 35, 36, 37, 38]},
    {4, "Water Corner", 1, [6, 18, 19, 20, 21, 22]},
    {5, "Smoke Bridge", 2, [6, 1, 2]},
    {6, "Mud Bridge", 2, [5, 3, 4]},
    {7, "Steam", 3, [8, 17]},
    {8, "Carbon Oxidization", 3, [9, 11, 12, 9]},
    {9, "Flame", 3, [13, 14, 23, 8]},
    {10, "Hydrogen", 3, [1, 18]},
    {11, "Burn", 3, [1, 8, 12]},
    {12, "Torch", 3, [1, 8, 11]},
    {13, "Blaze", 3, [1, 9, 14]},
    {14, "Spark", 3, [1, 9, 13]},
    {15, "Water 1", 4, [16]},
    {16, "Water 2", 4, [15, 19, 20, 17]},
    {17, "Water 3", 4, [7, 21, 22, 16]},
    {18, "Water to Fire", 4, [4, 10]},
    {19, "Water 5", 4, [4, 16, 20]},
    {20, "Water 6", 4, [4, 16, 19]},
    {21, "Water 7", 4, [4, 17, 22]},
    {22, "Water 8", 4, [4, 17, 21]},
    {23, "Wind 1", 5, [24]},
    {24, "Wind 2", 5, [23, 27, 28, 25]},
    {25, "Wind 3", 5, [29, 30, 31, 24]},
    {26, "Wind to Earth", 5, [2, 34]},
    {27, "Wind 5", 5, [2, 24, 28]},
    {28, "Wind 6", 5, [2, 24, 27]},
    {29, "Wind 7", 5, [2, 25, 30]},
    {30, "Wind 8", 5, [2, 25, 29]},
    {31, "Earth 1", 6, [25, 32]},
    {32, "Earth 2", 6, [35, 36, 33]},
    {33, "Earth 3", 6, [37, 38, 32, 15]},
    {34, "Earth to Wind", 6, [3, 26]},
    {35, "Earth 5", 6, [3, 32, 36]},
    {36, "Earth 6", 6, [3, 32, 35]},
    {37, "Earth 7", 6, [3, 33, 38]},
    {38, "Earth 8", 6, [3, 33, 37]}
  ]

  @elements_regions [
    {1, "Four Corners", 4, 7},
    {2, "Twin Bridges", 2, 3},
    {3, "Fire", 8, 5},
    {4, "Water", 8, 4},
    {5, "Earth", 8, 5},
    {6, "Wind", 8, 4}
  ]

  @doc "Area tuples `{number, name, region, links}` for `:original` or `:elements`, in area-number order."
  def areas(:original), do: @original_areas
  def areas(:elements), do: @elements_areas

  @doc "Region tuples `{number, name, num_areas, army_bonus}` for `:original` or `:elements`, in region-number order."
  def regions(:original), do: @original_regions
  def regions(:elements), do: @elements_regions

  @doc "Total area count for the map — `MapInfo.NumAreas`."
  def num_areas(map_name), do: length(areas(map_name))

  @doc "The area tuple for `number` — `MapInfo.GetArea`."
  def area(map_name, number), do: Enum.find(areas(map_name), fn {n, _, _, _} -> n == number end)

  @doc "The region tuple for `number` — `MapInfo.GetRegion`."
  def region(map_name, number),
    do: Enum.find(regions(map_name), fn {n, _, _, _} -> n == number end)

  @doc """
  Area numbers whose `links` include `area_number` — `AreaInfo.Inbounds`,
  computed on demand instead of cached at load time.
  """
  def inbounds(map_name, area_number) do
    for {number, _name, _region, links} <- areas(map_name), area_number in links, do: number
  end

  @doc "True when `a`'s links include `b` — `AreaInfo.LinksTo`."
  def links_to?(map_name, a, b) do
    {_number, _name, _region, links} = area(map_name, a)
    b in links
  end
end

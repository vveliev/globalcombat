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

  # --- render geometry (GIF-30) -----------------------------------------
  #
  # `AreaInfo`'s `TechName`/`X`/`Y`/`Width`/`Height` fields (`GlobalCombat.Core/MapInfo.cs`)
  # never had rule logic attached — they're purely where GameLive positions each area's
  # sprite — but the LiveView board still needs them to render without the client-side
  # map.js/Main.js this ticket retires (`Web/wwwroot/maps/*/map.js`, `Web/wwwroot/Main.js`).
  # Transcribed field-for-field from `MapInfo.cs` the same way `@original_areas`/
  # `@elements_areas` above were, kept as a separate table rather than folded into the
  # `{number, name, region, links}` tuples so callers that only need topology (the
  # differential-harness-verified `links_to?/3`, `regions/1`, etc.) are untouched.

  @original_render [
    {1, "alaska", 135, 117, 64, 79},
    {2, "northern", 182, 75, 144, 100},
    {3, "alberta", 177, 142, 47, 77},
    {4, "ontario", 210, 152, 69, 67},
    {5, "quebec", 256, 160, 90, 61},
    {6, "west", 203, 212, 59, 39},
    {7, "east", 239, 204, 108, 67},
    {8, "mexico", 216, 247, 104, 60},
    {9, "greenland", 343, 65, 80, 123},
    {10, "columbia", 282, 296, 58, 36},
    {11, "peru", 275, 321, 51, 61},
    {12, "brazil", 293, 324, 71, 75},
    {13, "argentina", 290, 371, 39, 87},
    {14, "algeria", 405, 264, 63, 73},
    {15, "egypt", 459, 274, 65, 50},
    {16, "congo", 429, 307, 71, 54},
    {17, "tanzania", 474, 319, 67, 63},
    {18, "southAfrica", 459, 352, 52, 67},
    {19, "madagascar", 520, 353, 27, 47},
    {20, "iceland", 406, 149, 24, 28},
    {21, "united", 410, 189, 31, 40},
    {22, "france", 419, 219, 35, 46},
    {23, "italy", 444, 201, 32, 63},
    {24, "scandinavia", 447, 138, 87, 72},
    {25, "greece", 465, 201, 65, 62},
    {26, "hungary", 508, 127, 75, 103},
    {27, "turkey", 491, 247, 69, 68},
    {28, "iran", 513, 179, 79, 94},
    {29, "india", 553, 254, 76, 74},
    {30, "kazakhstan", 560, 127, 79, 157},
    {31, "ural", 600, 83, 69, 148},
    {32, "china", 619, 209, 112, 75},
    {33, "thailand", 616, 269, 67, 62},
    {34, "mongolia", 648, 178, 79, 51},
    {35, "siberia", 643, 117, 54, 79},
    {36, "cherskiy", 672, 117, 60, 72},
    {37, "pevek", 720, 137, 63, 49},
    {38, "japan", 719, 199, 57, 56},
    {39, "indonesia", 624, 299, 88, 70},
    {40, "albany", 642, 376, 56, 54},
    {41, "sydney", 691, 373, 89, 86},
    {42, "newZealand", 700, 355, 73, 30}
  ]

  @elements_render [
    {1, "cf", 410, 123, 107, 107},
    {2, "ca", 322, 211, 107, 107},
    {3, "ce", 411, 300, 107, 107},
    {4, "cw", 499, 212, 107, 107},
    {5, "bs", 374, 176, 91, 90},
    {6, "bm", 463, 264, 91, 90},
    {7, "f1o", 604, 142, 74, 71},
    {8, "f2o", 489, 70, 81, 81},
    {9, "f3o", 357, 70, 81, 81},
    {10, "ftow", 464, 176, 71, 73},
    {11, "f5i", 489, 123, 55, 54},
    {12, "f6i", 462, 96, 56, 56},
    {13, "f7i", 410, 96, 54, 55},
    {14, "f8i", 383, 122, 56, 56},
    {15, "w1o", 606, 318, 71, 73},
    {16, "w2o", 579, 291, 80, 81},
    {17, "w3o", 578, 159, 81, 81},
    {18, "wtof", 482, 194, 71, 73},
    {19, "w5i", 552, 291, 55, 54},
    {20, "w6i", 579, 265, 53, 53},
    {21, "w7i", 577, 212, 56, 56},
    {22, "w8i", 551, 186, 55, 54},
    {23, "a1o", 252, 141, 71, 73},
    {24, "a2o", 269, 159, 81, 81},
    {25, "a3o", 270, 290, 81, 80},
    {26, "atoe", 375, 264, 71, 73},
    {27, "a5i", 321, 185, 54, 55},
    {28, "a6i", 295, 210, 56, 56},
    {29, "a7i", 296, 265, 53, 53},
    {30, "a8i", 322, 290, 54, 55},
    {31, "e1o", 251, 317, 74, 71},
    {32, "e2o", 358, 380, 81, 80},
    {33, "e3o", 491, 379, 80, 81},
    {34, "etoa", 393, 282, 71, 73},
    {35, "e5i", 385, 354, 53, 53},
    {36, "e6i", 411, 379, 54, 55},
    {37, "e7i", 463, 379, 55, 54},
    {38, "e8i", 491, 353, 53, 53}
  ]

  @doc "`{tech_name, x, y, width, height}` sprite geometry for `number` on `map_name` — `AreaInfo.TechName`/`X`/`Y`/`Width`/`Height`."
  def render_info(map_name, number) do
    {^number, tech_name, x, y, width, height} =
      Enum.find(all_render_info(map_name), &(elem(&1, 0) == number))

    {tech_name, x, y, width, height}
  end

  @doc "`{tech_name, x, y, width, height}` for every area of `map_name`, in area-number order."
  def all_render_info(:original), do: @original_render
  def all_render_info(:elements), do: @elements_render
end

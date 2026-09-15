defmodule GlobalCombatWeb.GameLive.WorldMapTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.GameLive.WorldMap

  # The colocated-hook rewrite (`Phoenix.LiveView.ColocatedHook`) only fires
  # for a static `phx-hook="..."` string; it qualifies the leading-dot name
  # with the defining module. Any test asserting the rendered `phx-hook`
  # value should compare against this, not the raw ".TerritoryKeyboard".
  @territory_keyboard_hook "#{inspect(WorldMap)}.TerritoryKeyboard"

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

  defp wrapper(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query_by_id("world-map")
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
    #
    # `phx-hook` itself must stay static (`.TerritoryKeyboard` unconditionally)
    # so `Phoenix.LiveView.ColocatedHook`'s compile-time rewrite can rename it
    # to the manifest key — that rewrite only fires for a literal string
    # attribute, so `phx-hook={@interactive && ".TerritoryKeyboard"}` would
    # ship the raw ".TerritoryKeyboard" to the browser and never match the
    # manifest (LiveView logs "unknown hook found for '.TerritoryKeyboard'"
    # and the keyboard hook never mounts). Interactivity is gated instead via
    # `data-interactive`, read by the hook itself on every keydown.

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
      assert territory |> LazyHTML.filter(~s([data-interactive])) |> Enum.any?()
      assert territory |> LazyHTML.filter(".world-map-territory--interactive") |> Enum.any?()
      assert LazyHTML.attribute(territory, "phx-hook") == [@territory_keyboard_hook]
    end

    test "interactive={false} territories keep a static (unrewritable) phx-hook but no data-interactive" do
      assigns = %{areas: [board_area(1)], players: players()}

      html =
        rendered_to_string(~H"""
        <WorldMap.world_map map_name={:original} areas={@areas} players={@players} interactive={false} />
        """)

      territory = territory(html)

      assert territory |> LazyHTML.filter("[role]") |> Enum.empty?()
      assert territory |> LazyHTML.filter("[tabindex]") |> Enum.empty?()
      assert territory |> LazyHTML.filter("[phx-click]") |> Enum.empty?()
      assert territory |> LazyHTML.filter("[data-interactive]") |> Enum.empty?()
      assert territory |> LazyHTML.filter(".world-map-territory--interactive") |> Enum.empty?()

      # `phx-hook` stays present and static even when non-interactive — the
      # ColocatedHook rewrite must see the same literal string every render,
      # never a conditional expression, or it silently stops rewriting.
      assert LazyHTML.attribute(territory, "phx-hook") == [@territory_keyboard_hook]
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
      assert arrow |> LazyHTML.filter(~s([data-interactive])) |> Enum.any?()
      assert arrow |> LazyHTML.filter(~s([data-select-event="select_order"])) |> Enum.any?()
      assert arrow |> LazyHTML.filter(".world-map-order--interactive") |> Enum.any?()

      # Regression: `phx-hook` must be the fully-qualified manifest key, not
      # the raw ".TerritoryKeyboard" — a dynamic `phx-hook={@interactive && ...}`
      # skips the ColocatedHook rewrite and ships a name that matches nothing
      # in the manifest, so the hook silently never mounts.
      assert LazyHTML.attribute(arrow, "phx-hook") == [@territory_keyboard_hook]
    end

    test "interactive={false} order arrows have no role, tabindex, click, or select-event, but keep the static hook" do
      assigns = %{areas: attacking_areas(), players: players()}

      html =
        rendered_to_string(~H"""
        <WorldMap.world_map map_name={:original} areas={@areas} players={@players} interactive={false} />
        """)

      arrow = order_arrow(html)

      assert arrow |> LazyHTML.filter("[role]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter("[tabindex]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter("[phx-click]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter("[data-interactive]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter("[data-select-event]") |> Enum.empty?()
      assert arrow |> LazyHTML.filter(".world-map-order--interactive") |> Enum.empty?()

      # `phx-hook` stays static (and thus still rewritten) even when
      # non-interactive — only `data-interactive` gates the hook's behavior.
      assert LazyHTML.attribute(arrow, "phx-hook") == [@territory_keyboard_hook]

      # Non-interactive doesn't mean invisible — the arrow itself, its label,
      # and the amount it carries must still render.
      assert arrow |> LazyHTML.filter(~s([aria-label])) |> Enum.any?()
    end
  end

  describe ".MapViewport wrapper attrs" do
    test "the .world-map wrapper carries the viewport hook, view box and keyboard tabindex" do
      assigns = %{areas: [board_area(1)], players: players()}

      html =
        rendered_to_string(~H"""
        <WorldMap.world_map map_name={:original} areas={@areas} players={@players} />
        """)

      wrap = wrapper(html)

      # A static `phx-hook="..."` literal on a colocated hook gets expanded at
      # compile time to the fully-qualified hook name (module + name), unlike
      # `.TerritoryKeyboard` above which is threaded through an `{...}` expression
      # and so keeps its short form — hence the suffix match here.
      assert wrap |> LazyHTML.filter(~s([phx-hook$=".MapViewport"])) |> Enum.any?()
      assert wrap |> LazyHTML.filter(~s([data-view-box="0 0 800 480"])) |> Enum.any?()
      assert wrap |> LazyHTML.filter(~s([tabindex="0"])) |> Enum.any?()
    end

    test "carries the game id for the hook's sessionStorage key when given one" do
      assigns = %{areas: [board_area(1)], players: players()}

      html =
        rendered_to_string(~H"""
        <WorldMap.world_map map_name={:original} areas={@areas} players={@players} game_id="abc123" />
        """)

      wrap = wrapper(html)

      assert wrap |> LazyHTML.filter(~s([data-game-id="abc123"])) |> Enum.any?()
    end
  end

  describe "region bonus legend" do
    for map_name <- [:original, :elements] do
      test "#{map_name}: lists every region's bonus in one aria-hidden legend inside the view box" do
        map_name = unquote(map_name)
        assigns = %{areas: [board_area(1)], players: players(), map_name: map_name}

        html =
          rendered_to_string(~H"""
          <WorldMap.world_map map_name={@map_name} areas={@areas} players={@players} />
          """)

        doc = LazyHTML.from_fragment(html)
        legend = LazyHTML.query(doc, "g.world-map-legend[aria-hidden='true']")
        assert Enum.count(legend) == 1

        for {number, name, _num_areas, bonus} <- GlobalCombat.Engine.MapInfo.regions(map_name) do
          row = LazyHTML.query(legend, ".world-map-legend-row[data-region='#{number}']")
          assert LazyHTML.text(row) =~ name
          assert LazyHTML.text(row) =~ "+#{bonus}"
        end

        # Highest bonus first, ties in region order.
        expected_order =
          map_name
          |> GlobalCombat.Engine.MapInfo.regions()
          |> Enum.sort_by(&elem(&1, 3), :desc)
          |> Enum.map(&to_string(elem(&1, 0)))

        assert legend
               |> LazyHTML.query(".world-map-legend-row")
               |> LazyHTML.attribute("data-region") ==
                 expected_order

        [vx, vy, vw, vh] =
          map_name |> WorldMap.view_box() |> String.split() |> Enum.map(&String.to_integer/1)

        %{x: x, y: y, scale: scale, width: w, height: h} = WorldMap.legend(map_name)

        assert x >= vx and y >= vy
        assert x + w * scale <= vx + vw
        assert y + h * scale <= vy + vh
      end
    end

    test "elements widens its view box with a sea strip on the left for the legend" do
      [x, _y, w, _h] = String.split(WorldMap.view_box(:elements))
      [gx, _gy, gw, _gh] = String.split(GlobalCombatWeb.GameLive.MapGeometry.view_box(:elements))

      assert String.to_integer(x) < String.to_integer(gx)

      assert String.to_integer(x) + String.to_integer(w) ==
               String.to_integer(gx) + String.to_integer(gw)
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

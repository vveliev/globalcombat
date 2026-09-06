defmodule GlobalCombatWeb.GameLive.WorldMap do
  @moduledoc """
  Vector board for every map — replaces the per-territory GIF sprites the
  legacy `Web` project still ships (`Web/wwwroot/maps/<map>/<tech><owner>.gif`,
  nine pre-colored 8-bit tiles per area) with one responsive SVG whose
  territories are `<use>` clones of static `<defs>` outlines, filled by CSS
  from the owner slot. The `:elements` map additionally overlays a per-element
  texture (flame, wave, gust, grit) so the four elements read at a glance the
  way the old textured tiles did, while the owner colour stays the fill.

  Why a rewrite rather than a restyle: the sprites baked owner color into pixels,
  so they could not be themed, could not show a selection state beyond a box
  outline, rendered blurry on any display density above 1x, and the LiveView
  port had also dropped the two overlay layers the legacy `Index.cshtml` drew
  (sea lanes and the Europe/Asia divider) — leaving no visible cue that Alaska
  reaches Pevek or Brazil reaches Algeria. Here the lanes are derived from the
  same `MapInfo` adjacency the rules use, so they can never disagree with it.

  Layering (paint order, bottom to top): sea → sea lanes → territories (the only
  interactive layer) → region borders → selected/target highlight → army counts.
  The highlight is a second `<use>` of the same outline drawn *above* the
  neighbours so a selected coastline is never half-covered by the territory
  painted after it, over a wider surface-coloured halo so the ring reads even
  where the owner fill happens to match the focus-ring or danger hue.

  Geometry (`world_map/<map>_map_defs.html.heex`, `MapGeometry`) is generated
  by `scripts/trace_maps.py` from the legacy silhouettes, so shapes, adjacency
  and the coordinate space are unchanged from the sprite board. The defs are
  static templates: LiveView ships them once with the page statics and never
  re-sends them on a diff, however often ownership changes.

  Accessibility: each territory is a `role="button"` group with an `aria-label`
  carrying name, owner and army count (or "hidden by fog of war") and
  `aria-pressed` for the selected/target state; Enter and Space activate it
  through the colocated `.TerritoryKeyboard` hook since SVG has no native
  button. The army-count text is decorative (`aria-hidden`, the label already
  says it) and gets a dark stroke under a light fill via `paint-order: stroke`
  so it stays legible on every owner colour (GIF-83). `GameLive.board_table/1`
  remains the tabular equivalent for screen readers (GIF-81); it and the labels
  here share `owner_text/2` so the two can never word an owner differently.

  Owner colours are the app-level `--map-owner-N` tokens (see ADR-0003); the
  same `owner_slot/1` drives the territory fill and the player-list legend dot,
  so there is one place the legacy `Player.GetColor()` numbering lives.

  The `lens` attr swaps what the territory fill (and, for
  `:frontier`, the army count) encodes without touching the paint order,
  fog gate, or accessible labels above — those stay truthful to the real
  per-area owner/visibility regardless of lens, so the sr-only board table
  never has to know a lens exists.

    * `:owner` (default) — fill is the area's own owner slot.
    * `:region` — fill is the slot of whoever holds every area in that
      area's region (`--map-owner-0` if contested or, since a region can
      only read as "held" when every one of its areas is individually
      visible, if any of them is fogged — never the true per-area owner
      leaking through a mixed region), plus a decorative bonus label per
      region centroid.
    * `:frontier` — fill is the true owner slot as in `:owner`, but interior
      areas are dimmed (`data-frontier="dim"`); only the viewer's border
      areas and the enemy areas touching them stay full strength, with the
      army delta against the strongest adjacent opposing stack shown next
      to the count. A spectator (`viewer_number: nil`) has no "own"
      territory to draw a frontier from, so this lens falls back to
      `:owner` for them, same as `PlayerView`'s fog treats a spectator as a
      fogged non-owner.
  """
  use Phoenix.Component

  alias GlobalCombat.Engine.MapInfo
  alias GlobalCombatWeb.GameLive.MapGeometry, as: Geometry

  embed_templates "world_map/*"

  @doc """
  The colour slot (0..8) for an owner number — the sprite board's
  `owner_number % 9` (`Player.GetColor()` in the original), with `nil` (no
  owner) as slot 0. `--map-owner-N` tokens follow this numbering.
  """
  def owner_slot(nil), do: 0
  def owner_slot(owner_number) when is_integer(owner_number), do: rem(owner_number, 9)

  @doc """
  How an area's owner is worded everywhere a player reads it (territory labels,
  the sr-only board table's Owner cell verbatim; `owner_phrase/2` is the same
  wording as a label clause). A fog-hidden area is neither "owned by <player>"
  nor "unclaimed" (GIF-121) — collapsing the two would make a fogged enemy tile
  indistinguishable from a real unowned one for a screen reader user.
  `owner_names` is `%{player_number => name}`.
  """
  def owner_text(%{visible: false}, _owner_names), do: "hidden by fog of war"

  def owner_text(%{owner_number: owner_number}, owner_names) do
    case Map.fetch(owner_names, owner_number) do
      {:ok, name} -> name
      :error -> "unclaimed"
    end
  end

  @doc "`owner_text/2` as a label clause: `\"owned by Alice\"`, `\"unclaimed\"`, `\"hidden by fog of war\"`."
  def owner_phrase(%{visible: true, owner_number: owner_number} = area, owner_names)
      when is_integer(owner_number) and is_map_key(owner_names, owner_number),
      do: "owned by #{owner_text(area, owner_names)}"

  def owner_phrase(area, owner_names), do: owner_text(area, owner_names)

  @doc "`%{player_number => name}` from `PlayerView.players`, built once per render."
  def owner_names(players), do: Map.new(players, &{&1.number, &1.name})

  attr :map_name, :atom, required: true, doc: "`:original` or `:elements`"
  attr :areas, :list, required: true, doc: "`PlayerView.areas` — already fog-filtered"
  attr :players, :list, required: true, doc: "`PlayerView.players`, for owner names"
  attr :selected_area, :integer, default: nil, doc: "area number, or nil when none is selected"
  attr :target_area, :integer, default: nil, doc: "area number, or nil when no target is picked"

  attr :lens, :atom,
    default: :owner,
    values: [:owner, :region, :frontier],
    doc: "which view mode fills the territories — see the moduledoc"

  attr :viewer_number, :any,
    default: nil,
    doc: "`PlayerView.viewer_number` — nil for a spectator, needed by the :frontier lens"

  attr :interactive, :boolean,
    default: true,
    doc:
      "false once the game has ended: territories stop being a focus/click target " <>
        "at all rather than staying clickable dead controls"

  def world_map(assigns) do
    lens = effective_lens(assigns.lens, assigns.viewer_number)

    assigns =
      assigns
      |> assign(:view_box, Geometry.view_box(assigns.map_name))
      |> assign(:owner_names, owner_names(assigns.players))
      |> assign(:lens, lens)
      |> assign(:fills, fills(lens, assigns.areas, assigns.map_name, assigns.viewer_number))
      |> assign(
        :region_labels,
        if(lens == :region, do: region_labels(assigns.map_name), else: [])
      )

    ~H"""
    <div class="world-map" data-map={@map_name}>
      <svg
        viewBox={@view_box}
        role="group"
        aria-label={board_label(@map_name)}
        class="block h-auto w-full"
      >
        <.original_map_defs :if={@map_name == :original} />
        <.elements_map_defs :if={@map_name == :elements} />
        <.board_ground view_box={@view_box} />
        <use href="#gc-links" class="world-map-links" />
        <g class="world-map-areas">
          <.territory
            :for={area <- @areas}
            area={area}
            map_name={@map_name}
            owner_names={@owner_names}
            selected={area.number == @selected_area}
            target={area.number == @target_area}
            fill={Map.fetch!(@fills, area.number)}
            interactive={@interactive}
          />
        </g>
        <use href="#gc-region-outlines" class="world-map-outlines" />
        <g class="world-map-highlights" aria-hidden="true">
          <use :if={@selected_area} href={"#gc-area-#{@selected_area}"} class="world-map-halo" />
          <use
            :if={@selected_area}
            href={"#gc-area-#{@selected_area}"}
            class="world-map-highlight world-map-highlight--selected"
          />
          <use :if={@target_area} href={"#gc-area-#{@target_area}"} class="world-map-halo" />
          <use
            :if={@target_area}
            href={"#gc-area-#{@target_area}"}
            class="world-map-highlight world-map-highlight--target"
          />
        </g>
        <g class="world-map-counts" aria-hidden="true">
          <.army_count
            :for={area <- @areas}
            :if={area.armies}
            area={area}
            map_name={@map_name}
            delta={Map.fetch!(@fills, area.number).delta}
          />
        </g>
        <g :if={@lens == :region} class="world-map-region-labels" aria-hidden="true">
          <text
            :for={r <- @region_labels}
            x={r.x}
            y={r.y}
            class="world-map-region-label"
            text-anchor="middle"
            dominant-baseline="central"
          >
            {"+#{r.bonus}"}
          </text>
        </g>
      </svg>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".TerritoryKeyboard">
        // SVG has no <button>, so a territory is a focusable role="button" <g>;
        // this gives it the keyboard activation a real button has for free.
        // Clicks go through phx-click on the same element — this hook only
        // covers Enter/Space (Space must be swallowed or the page scrolls).
        export default {
          mounted() {
            this.el.addEventListener("keydown", (e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault()
                this.pushEvent("select_area", {area: this.el.dataset.area})
              }
            })
          }
        }
      </script>
    </div>
    """
  end

  # The ground rects cover the viewBox rather than `100%` of it because the
  # elements map is cropped to its art (its viewBox does not start at 0 0).
  attr :view_box, :string, required: true

  defp board_ground(assigns) do
    [x, y, w, h] = String.split(assigns.view_box)
    assigns = assign(assigns, x: x, y: y, w: w, h: h)

    ~H"""
    <rect class="world-map-sea" x={@x} y={@y} width={@w} height={@h} />
    <rect class="world-map-sea-texture" x={@x} y={@y} width={@w} height={@h} />
    """
  end

  attr :area, :map, required: true
  attr :map_name, :atom, required: true
  attr :owner_names, :map, required: true
  attr :selected, :boolean, required: true
  attr :target, :boolean, required: true
  attr :fill, :map, required: true, doc: "one entry of `fills/4`: `%{owner:, dim:, delta:}`"
  attr :interactive, :boolean, required: true

  defp territory(assigns) do
    assigns =
      assigns
      |> assign(:label, territory_label(assigns.area, assigns.owner_names))
      |> assign(:element, Geometry.element(assigns.map_name, assigns.area.number))

    ~H"""
    <g
      id={"territory-#{@area.number}"}
      class={[
        "world-map-territory world-map-owner",
        @interactive && "world-map-territory--interactive"
      ]}
      role={@interactive && "button"}
      tabindex={@interactive && "0"}
      aria-label={@label}
      aria-pressed={@interactive && to_string(@selected or @target)}
      data-area={@area.number}
      data-owner={@fill.owner}
      data-fog={!@area.visible}
      data-frontier={@fill.dim && "dim"}
      data-element={@element}
      phx-hook={@interactive && ".TerritoryKeyboard"}
      phx-click={@interactive && "select_area"}
      phx-value-area={@interactive && @area.number}
    >
      <use href={"#gc-area-#{@area.number}"} class="world-map-area" />
      <use
        :if={@element && @area.visible}
        href={"#gc-area-#{@area.number}"}
        class="world-map-texture"
      />
    </g>
    """
  end

  attr :area, :map, required: true
  attr :map_name, :atom, required: true

  attr :delta, :integer,
    default: nil,
    doc: ":frontier lens only — delta vs. the strongest adjacent opposing stack"

  defp army_count(assigns) do
    {x, y} = Geometry.label(assigns.map_name, assigns.area.number)
    assigns = assign(assigns, x: x, y: y)

    # `paint-order`/`stroke-linejoin` are presentation attributes here (they need
    # no theme token) so the outline-under-glyphs contract is visible in the
    # rendered markup; the stroke/fill colours come from `.world-map-count`.
    ~H"""
    <text
      x={@x}
      y={@y}
      class="world-map-count"
      text-anchor="middle"
      dominant-baseline="central"
      paint-order="stroke"
      stroke-linejoin="round"
    >
      {@area.armies}
      <tspan :if={@delta} dx="10" class="world-map-delta">{delta_text(@delta)}</tspan>
    </text>
    """
  end

  defp delta_text(delta) when delta > 0, do: "(+#{delta})"
  defp delta_text(delta), do: "(#{delta})"

  # --- lenses -----------------------------------------------------------

  # A spectator has no "own" territory for :frontier to draw a border from —
  # same treatment `PlayerView` gives a spectator elsewhere (it "sees exactly
  # what a fogged non-owner sees"), so this falls back to :owner rather than
  # rendering every area dimmed.
  defp effective_lens(:frontier, nil), do: :owner
  defp effective_lens(lens, _viewer_number), do: lens

  @doc false
  def fills(:owner, areas, _map_name, _viewer_number) do
    Map.new(areas, fn area ->
      {area.number,
       %{owner: area.visible && owner_slot(area.owner_number), dim: false, delta: nil}}
    end)
  end

  def fills(:region, areas, map_name, _viewer_number) do
    region_owners = region_owners(map_name, areas)

    area_regions =
      Map.new(MapInfo.areas(map_name), fn {number, _name, region, _links} -> {number, region} end)

    Map.new(areas, fn area ->
      region_owner = Map.fetch!(region_owners, Map.fetch!(area_regions, area.number))
      {area.number, %{owner: owner_slot(region_owner), dim: false, delta: nil}}
    end)
  end

  def fills(:frontier, areas, _map_name, viewer_number) do
    frontier = frontier_info(areas, viewer_number)
    areas_by_number = Map.new(areas, &{&1.number, &1})

    Map.new(areas, fn area ->
      on_frontier? = MapSet.member?(frontier, area.number)

      {area.number,
       %{
         owner: area.visible && owner_slot(area.owner_number),
         dim: not on_frontier?,
         delta: if(on_frontier?, do: frontier_delta(area, areas_by_number))
       }}
    end)
  end

  @doc """
  `%{region_number => owner_number | nil}` for every region of `map_name` — the
  owner is set only when every area of that region is individually visible to
  this viewer *and* shares one owner; a region with a hidden area, or a mix of
  owners, reads as contested (`nil`, `--map-owner-0`). A hidden area can never
  tip a region into reading as "held" by its true owner — the same fog
  invariant `owner_text/2` enforces per-area.
  """
  def region_owners(map_name, areas) do
    areas_by_number = Map.new(areas, &{&1.number, &1})

    map_name
    |> MapInfo.areas()
    |> Enum.group_by(
      fn {_number, _name, region, _links} -> region end,
      fn {number, _name, _region, _links} -> number end
    )
    |> Map.new(fn {region_number, area_numbers} ->
      region_areas = Enum.map(area_numbers, &Map.fetch!(areas_by_number, &1))
      {region_number, region_owner(region_areas)}
    end)
  end

  @doc "The single owner_number holding every one of `region_areas` (visible, one owner), else nil."
  def region_owner(region_areas) do
    if Enum.all?(region_areas, & &1.visible) do
      case region_areas |> Enum.map(& &1.owner_number) |> Enum.uniq() do
        [owner] when not is_nil(owner) -> owner
        _ -> nil
      end
    else
      nil
    end
  end

  # Every area bordering one of the viewer's own areas is already visible
  # regardless of fog (`PlayerView.owns_adjacent?/3`), so this needs no
  # separate fog check: an owned area with a differently-owned neighbour is a
  # border area, and every enemy area adjacent to one is, by that same rule,
  # already revealed.
  defp frontier_info(areas, viewer_number) do
    areas_by_number = Map.new(areas, &{&1.number, &1})

    my_borders =
      areas
      |> Enum.filter(&(&1.owner_number == viewer_number))
      |> Enum.filter(fn area ->
        Enum.any?(area.adjacent, fn n ->
          case Map.fetch(areas_by_number, n) do
            {:ok, neighbor} -> neighbor.owner_number != viewer_number
            :error -> false
          end
        end)
      end)
      |> MapSet.new(& &1.number)

    enemy_borders =
      areas
      |> Enum.filter(&(&1.owner_number != viewer_number))
      |> Enum.filter(&Enum.any?(&1.adjacent, fn n -> MapSet.member?(my_borders, n) end))
      |> MapSet.new(& &1.number)

    MapSet.union(my_borders, enemy_borders)
  end

  # The army delta shown next to a frontier tile's count: this area's armies
  # minus the strongest visible, differently-owned neighbour — from either
  # side of the line, a positive delta favours whoever holds the tile it's
  # printed on.
  defp frontier_delta(area, areas_by_number) do
    opposing =
      area.adjacent
      |> Enum.map(&Map.get(areas_by_number, &1))
      |> Enum.filter(&(&1 && &1.visible && &1.armies && &1.owner_number != area.owner_number))
      |> Enum.map(& &1.armies)

    case opposing do
      [] -> nil
      armies -> area.armies - Enum.max(armies)
    end
  end

  # Region label anchor: the mean of its areas' own label points (the pole of
  # inaccessibility `MapGeometry` already computed per area) rather than new
  # generated geometry — close enough for a decorative, aria-hidden bonus
  # readout backed by the accessible `region_bonuses/1` panel.
  defp region_labels(map_name) do
    areas_by_region =
      MapInfo.areas(map_name)
      |> Enum.group_by(
        fn {_number, _name, region, _links} -> region end,
        fn {number, _name, _region, _links} -> number end
      )

    for {region_number, _name, _num_areas, bonus} <- MapInfo.regions(map_name) do
      {x, y} = region_centroid(map_name, Map.fetch!(areas_by_region, region_number))
      %{number: region_number, bonus: bonus, x: x, y: y}
    end
  end

  defp region_centroid(map_name, area_numbers) do
    points = Enum.map(area_numbers, &Geometry.label(map_name, &1))
    {sum_x, sum_y} = Enum.reduce(points, {0, 0}, fn {x, y}, {sx, sy} -> {sx + x, sy + y} end)
    count = length(points)
    {sum_x / count, sum_y / count}
  end

  # Fog-hidden areas get no owner slot at all (`data-owner` is omitted) — the fog
  # hatch is styled off `data-fog`, never off a neutral "0" that would be
  # indistinguishable from a genuinely unclaimed territory (GIF-121).
  defp territory_label(%{visible: false} = area, owner_names),
    do: "#{area.name}, #{owner_phrase(area, owner_names)}"

  defp territory_label(area, owner_names),
    do: "#{area.name}, #{owner_phrase(area, owner_names)}, #{armies_text(area.armies)}"

  defp board_label(:original), do: "World map board"
  defp board_label(:elements), do: "Elements map board"

  defp armies_text(1), do: "1 army"
  defp armies_text(n), do: "#{n} armies"
end

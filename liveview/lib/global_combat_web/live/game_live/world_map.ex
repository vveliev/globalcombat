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
  interactive layer, alongside the order arrows below) → region borders →
  selected/target highlight → pending-order arrows → last-turn replay arrows →
  army counts. The highlight is a second `<use>` of the same outline drawn
  *above* the neighbours so a selected coastline is never half-covered by the
  territory painted after it, over a wider surface-coloured halo so the ring
  reads even where the owner fill happens to match the focus-ring or danger
  hue. The order arrows sit above the highlight, and the replay arrows above
  those — a viewer composing this turn's orders and reviewing last turn's
  results are two different moments, but a queued move's amount label and a
  replayed one both need to stay clear of the counts painted last.

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

  @doc "`%{area_number => name}` from `PlayerView.areas`, built once per render."
  def area_names(areas), do: Map.new(areas, &{&1.number, &1.name})

  @doc """
  Worded once and shared by the board's pending-orders arrows (`aria-label`) and
  `GameLive`'s "Your orders" sr card, so the two textual descriptions of the same
  queued order can never drift apart. `order` is a `PlayerView` area's `order` field
  (`%{command:, target:, amount:}`, never `nil` here — callers only reach this once
  they've already checked).
  """
  def order_label(source_name, %{command: :attack} = order, target_name),
    do: "Attack #{target_name} with #{armies_text(order.amount)} from #{source_name}"

  def order_label(source_name, %{command: :transfer} = order, target_name),
    do: "Transfer #{armies_text(order.amount)} to #{target_name} from #{source_name}"

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

  attr :replay_steps, :list,
    default: [],
    doc: "`GameLive.Replay.steps/4` output for `PlayerView.last_turn_events`"

  attr :game_id, :any,
    default: nil,
    doc: "used only as the `.MapViewport` hook's sessionStorage key; nil disables persistence"

  attr :unassigned, :any,
    default: nil,
    doc:
      "the viewer's unplaced reinforcements, or nil when they can't act (spectating, " <>
        "eliminated, turn ended) — a number turns on the phone gestures, and while it is " <>
        "above zero a tap on an own territory places one (`quick_assign`) instead of selecting it"

  def world_map(assigns) do
    lens = effective_lens(assigns.lens, assigns.viewer_number)

    assigns =
      assigns
      |> assign(:view_box, view_box(assigns.map_name))
      |> assign(:owner_names, owner_names(assigns.players))
      |> assign(:area_names, area_names(assigns.areas))
      |> assign(:lens, lens)
      |> assign(:fills, fills(lens, assigns.areas, assigns.map_name, assigns.viewer_number))
      |> assign(
        :region_labels,
        if(lens == :region, do: region_labels(assigns.map_name), else: [])
      )
      |> assign(:legend, legend(assigns.map_name))
      |> assign(:replay_arrows, Enum.filter(assigns.replay_steps, &(&1.from && &1.to)))
      |> assign(:replay_captures, Enum.filter(assigns.replay_steps, & &1.captured))

    ~H"""
    <div
      id="world-map"
      class="world-map"
      data-map={@map_name}
      data-view-box={@view_box}
      data-game-id={@game_id}
      data-zoomed="false"
      data-unassigned={@interactive && @unassigned}
      data-curve={curve_json(@map_name)}
      tabindex="0"
      phx-hook=".MapViewport"
    >
      <svg
        viewBox={@view_box}
        role="group"
        aria-label={board_label(@map_name)}
        class="block h-auto w-full"
      >
        <defs>
          <marker
            :for={kind <- ~w(attack transfer)}
            id={"gc-order-arrowhead-#{kind}"}
            viewBox="0 0 10 10"
            refX="8.5"
            refY="5"
            markerWidth="6"
            markerHeight="6"
            orient="auto"
          >
            <path
              d="M0,0 L10,5 L0,10 Z"
              class={"gc-order-arrowhead gc-order-arrowhead--#{kind}"}
            />
          </marker>
        </defs>
        <.original_map_defs :if={@map_name == :original} />
        <.elements_map_defs :if={@map_name == :elements} />
        <defs>
          <marker
            id="gc-replay-arrowhead-attack"
            viewBox="0 0 10 10"
            refX="8"
            refY="5"
            markerWidth="6"
            markerHeight="6"
            orient="auto-start-reverse"
          >
            <path
              d="M0,0 L10,5 L0,10 z"
              class="world-map-replay-arrowhead world-map-replay-arrowhead--attack"
            />
          </marker>
          <marker
            id="gc-replay-arrowhead-transfer"
            viewBox="0 0 10 10"
            refX="8"
            refY="5"
            markerWidth="6"
            markerHeight="6"
            orient="auto-start-reverse"
          >
            <path
              d="M0,0 L10,5 L0,10 z"
              class="world-map-replay-arrowhead world-map-replay-arrowhead--transfer"
            />
          </marker>
        </defs>
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
            mine={mine?(area, @viewer_number)}
          />
        </g>
        <use href="#gc-region-outlines" class="world-map-outlines" />
        <g
          class="world-map-legend"
          aria-hidden="true"
          transform={"translate(#{@legend.x} #{@legend.y}) scale(#{@legend.scale})"}
        >
          <rect
            class="world-map-legend-plate"
            width={@legend.width}
            height={@legend.height}
            rx="8"
          />
          <text class="world-map-legend-title" x="10" y="19">REGION BONUSES</text>
          <line class="world-map-legend-rule" x1="10" y1="27" x2={@legend.width - 10} y2="27" />
          <g
            :for={{row, i} <- Enum.with_index(@legend.rows)}
            class="world-map-legend-row"
            data-region={row.number}
          >
            <text class="world-map-legend-name" x="10" y={45 + i * 19}>{row.name}</text>
            <text
              class="world-map-legend-bonus"
              x={@legend.width - 10}
              y={45 + i * 19}
              text-anchor="end"
            >
              +{row.bonus}
            </text>
          </g>
        </g>
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
        <%!-- While a drag-to-order is under way `.MapViewport` veils the board
        here and redraws the source and the neighbours it can land on over
        the veil. Client-owned like the ghost arrow below, so LiveView never
        patches it mid-gesture. --%>
        <g id="world-map-drag" class="world-map-drag" phx-update="ignore" aria-hidden="true"></g>
        <g :if={Enum.any?(@areas, &queued_order?/1)} class="world-map-orders">
          <.order_arrow
            :for={area <- @areas}
            :if={queued_order?(area)}
            area={area}
            area_names={@area_names}
            map_name={@map_name}
            interactive={@interactive}
          />
        </g>
        <g id="world-map-replay" class="world-map-replay" aria-hidden="true">
          <.replay_arrow :for={step <- @replay_arrows} step={step} />
          <use
            :for={step <- @replay_captures}
            data-step={step.index}
            href={"#gc-area-#{step.to.area}"}
            class="world-map-halo world-map-replay-pulse"
          />
        </g>
        <g class="world-map-counts" aria-hidden="true">
          <.army_count
            :for={area <- @areas}
            :if={area.armies}
            area={area}
            map_name={@map_name}
            delta={Map.fetch!(@fills, area.number).delta}
            owner={Map.fetch!(@fills, area.number).owner}
          />
        </g>
        <%!-- The drag-to-order preview arrow `.MapViewport` draws while a finger
        is dragging from an own territory — client-owned, so LiveView must
        never patch its children away mid-gesture. --%>
        <g id="world-map-ghost" class="world-map-ghost" phx-update="ignore" aria-hidden="true"></g>
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
        // SVG has no <button>, so a territory (or order arrow) is a focusable
        // role="button" <g>; this gives it the keyboard activation a real button
        // has for free. Clicks go through phx-click on the same element — this
        // hook only covers Enter/Space (Space must be swallowed or the page
        // scrolls). `data-select-event` lets an order arrow reuse this hook
        // while pushing `select_order` instead of a territory's `select_area`
        // (defaulting to `select_area` so territories need no extra attribute).
        // `phx-hook` must stay a static string so LiveView's colocated-hook
        // rewrite can match it to the manifest — `@interactive` instead gates
        // `data-interactive`, checked on every keydown so a live toggle of
        // interactivity (no remount) still takes effect.
        export default {
          mounted() {
            this.el.addEventListener("keydown", (e) => {
              if (this.el.dataset.interactive === undefined) return
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault()
                this.pushEvent(this.el.dataset.selectEvent || "select_area", {area: this.el.dataset.area})
              }
            })
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".MapViewport">
        // The map's gesture layer. One finger pans, two pinch-zoom, a double
        // tap on open board zooms in or back out — and, below `lg` (the phone
        // HUD; from `lg` up a click selects and a drag pans, as it always
        // has), the two game gestures on the viewer's own territories:
        //
        //   * tap places one reinforcement while any are unplaced, hold places
        //     five (`quick_assign`), instead of opening the order panel;
        //   * a drag that starts on an own territory's army token draws a live
        //     arrow and, released over a neighbour, opens that order
        //     (`drag_order`). A drag from anywhere else pans, own land included.
        //
        // A tap only ever gets cancelled when the pointer actually moved, when
        // it was a hold, or when it completes a double tap.
        //
        // The viewBox always takes the stage's own aspect ratio, so the board
        // fills the screen edge to edge instead of letterboxing: "fit" shows
        // the whole board, and a phone held upright starts zoomed to fill its
        // height around the viewer's territories. LiveView owns the viewBox
        // attribute and resets it on every patch, so `updated()` re-applies
        // whatever pan/zoom this hook holds — same as `.TurnReplay` re-applying
        // its step counts.
        const MAX_SCALE = 6
        const DOUBLE_TAP_ZOOM = 2.5
        const DOUBLE_TAP_MS = 300
        const DOUBLE_TAP_PX = 24
        const DRAG_PX = 8
        const HOLD_MS = 450
        const HOLD_AMOUNT = 5
        const TOKEN_REACH_PX = 22
        const TOKEN_GRAB_PX = 30
        const PLACE_COOLDOWN_MS = 500
        const PANEL_GAP_PX = 28
        const PANEL_MARGIN_PX = 8
        const EDGE_SLACK = 0.12
        const PORTRAIT_HEIGHT = 1.15
        const ANIMATE_MS = 200
        const TOKEN_PX = 12
        const TOKEN_UNITS = 9
        const DESKTOP_QUERY = "(min-width: 64rem)"

        const buzz = (pattern) => {
          try {
            navigator.vibrate?.(pattern)
          } catch {
            // Not every browser lets a page vibrate; the gesture works without it.
          }
        }

        export default {
          mounted() {
            this.svg = this.el.querySelector("svg")
            this.ghost = this.el.querySelector("#world-map-ghost")
            this.dragLayer = this.el.querySelector("#world-map-drag")
            this.curveShape = JSON.parse(this.el.dataset.curve)
            this.desktop = window.matchMedia(DESKTOP_QUERY)
            this.lastPlaceAt = 0
            this.base = this.parseViewBox(this.el.dataset.viewBox)
            this.pointers = new Map()
            this.moved = false
            this.gestureStart = null
            this.lastSingle = null
            this.pinch = null
            this.lastTap = null
            this.press = null
            this.drag = null
            this.suppressClick = false
            this.pendingPlacements = 0
            this.raf = null
            this.counts = this.readCounts()
            this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches

            this.onPointerDown = this.onPointerDown.bind(this)
            this.onPointerMove = this.onPointerMove.bind(this)
            this.onPointerUp = this.onPointerUp.bind(this)
            this.onClick = this.onClick.bind(this)
            this.onWheel = this.onWheel.bind(this)
            this.onKeyDown = this.onKeyDown.bind(this)
            this.onFitEvent = this.onFitEvent.bind(this)
            this.onResize = this.onResize.bind(this)

            this.el.addEventListener("pointerdown", this.onPointerDown)
            this.el.addEventListener("pointermove", this.onPointerMove)
            this.el.addEventListener("pointerup", this.onPointerUp)
            this.el.addEventListener("pointercancel", this.onPointerUp)
            this.el.addEventListener("click", this.onClick, true)
            this.el.addEventListener("dblclick", (e) => e.preventDefault())
            this.el.addEventListener("contextmenu", (e) => {
              if (this.press) e.preventDefault()
            })
            this.el.addEventListener("wheel", this.onWheel, { passive: false })
            this.el.addEventListener("keydown", this.onKeyDown)
            window.addEventListener("gc:map-fit", this.onFitEvent)

            const saved = this.restore()
            this.lastAspect = this.aspect()
            this.current = saved ? this.withAspect(saved) : this.home()
            this.applyViewBox()

            this.resizeObserver = new ResizeObserver(this.onResize)
            this.resizeObserver.observe(this.el)
          },

          updated() {
            this.svg = this.el.querySelector("svg")
            this.ghost = this.el.querySelector("#world-map-ghost")
            this.dragLayer = this.el.querySelector("#world-map-drag")
            this.applyViewBox()
            this.bumpChangedCounts()
          },

          destroyed() {
            window.removeEventListener("gc:map-fit", this.onFitEvent)
            this.resizeObserver?.disconnect()
            this.cancelHold()
            this.clearPanelPosition()
            if (this.raf) cancelAnimationFrame(this.raf)
          },

          // --- viewBox state -----------------------------------------------

          parseViewBox(str) {
            const [x, y, w, h] = str.split(" ").map(Number)
            return { x, y, w, h }
          },

          aspect() {
            const rect = this.svg?.getBoundingClientRect()
            return rect && rect.width > 0 && rect.height > 0
              ? rect.width / rect.height
              : this.base.w / this.base.h
          },

          // Widest view: the whole board, plus open sea on whichever axis the
          // stage is relatively longer than the board.
          fitWidth(aspect = this.aspect()) {
            return Math.max(this.base.w, this.base.h * aspect)
          },

          fit() {
            const aspect = this.aspect()
            const w = this.fitWidth(aspect)
            const h = w / aspect
            return {
              x: this.base.x + this.base.w / 2 - w / 2,
              y: this.base.y + this.base.h / 2 - h / 2,
              w,
              h
            }
          },

          // Where a fresh visit starts. Upright on a phone the whole board is a
          // thin strip, so zoom until its height fills the screen, centred on
          // the viewer's territories; anywhere else the whole board fits.
          home() {
            const aspect = this.aspect()
            if (aspect >= 1 || this.desktop.matches) return this.fit()

            const mine = [...this.el.querySelectorAll(".world-map-territory[data-mine]")]
              .map((t) => this.labelOf(t.dataset.area))
              .filter(Boolean)
            if (mine.length === 0) return this.fit()

            const median = (values) => values.sort((a, b) => a - b)[Math.floor(values.length / 2)]
            const cx = median(mine.map((p) => p.x))
            const cy = median(mine.map((p) => p.y))
            const h = this.base.h * PORTRAIT_HEIGHT
            const w = h * aspect
            return this.clamped({ x: cx - w / 2, y: cy - h / 2, w, h })
          },

          // A saved or resized view keeps its centre and zoom but takes the
          // stage's current shape.
          withAspect(view) {
            const aspect = this.aspect()
            const w = Math.min(Math.max(view.w, this.base.w / MAX_SCALE), this.fitWidth(aspect))
            const h = w / aspect
            return this.clamped({
              x: view.x + view.w / 2 - w / 2,
              y: view.y + view.h / 2 - h / 2,
              w,
              h
            })
          },

          storageKey() {
            const gameId = this.el.dataset.gameId
            return gameId ? `gc:viewport:${gameId}` : null
          },

          restore() {
            const key = this.storageKey()
            if (!key) return null
            try {
              const parsed = JSON.parse(sessionStorage.getItem(key))
              if (!parsed || typeof parsed.x !== "number" || typeof parsed.w !== "number") {
                return null
              }
              return parsed
            } catch {
              return null
            }
          },

          save(state = this.current) {
            const key = this.storageKey()
            if (!key) return
            try {
              sessionStorage.setItem(key, JSON.stringify(state))
            } catch {
              // Private browsing / quota — the viewport just won't survive a reload.
            }
          },

          applyViewBox() {
            if (!this.svg) return
            const { x, y, w, h } = this.current
            this.svg.setAttribute("viewBox", `${x} ${y} ${w} ${h}`)
            this.el.dataset.zoomed = w < this.fitWidth() - 0.01 ? "true" : "false"

            // Army tokens keep a thumb-readable size instead of shrinking and
            // growing with the board (`.world-map-token` in app.css).
            const width = this.svg.getBoundingClientRect().width
            const unitsPerPx = width > 0 ? w / width : 1
            const scale = Math.min(Math.max((TOKEN_PX * unitsPerPx) / TOKEN_UNITS, 0.7), 1.6)
            this.el.style.setProperty("--token-scale", scale.toFixed(3))
            this.positionOrderPanel()
          },

          // On a phone the order panel for a transfer/attack floats beside its
          // arrow instead of sitting in the dock: `GameLive` puts the arrow's
          // midpoint (board units) in the card's `data-anchor`, and this turns
          // it into screen pixels, below the arrow when there is room and
          // above it when not. The position goes out as custom properties on
          // the root element — outside anything LiveView patches — and
          // `app.css` (`#order-panel[data-anchor]`) reads them.
          positionOrderPanel() {
            const panel = document.querySelector("#order-panel[data-anchor]")
            if (!panel || this.desktop.matches || !this.svg) {
              this.clearPanelPosition()
              return
            }

            const [x, y] = panel.dataset.anchor.split(",").map(Number)
            const rect = this.svg.getBoundingClientRect()
            const pxPerUnit = rect.width / this.current.w
            const cx = rect.left + (x - this.current.x) * pxPerUnit
            const cy = rect.top + (y - this.current.y) * pxPerUnit
            const w = panel.offsetWidth
            const h = panel.offsetHeight
            const maxLeft = window.innerWidth - w - PANEL_MARGIN_PX
            const maxTop = window.innerHeight - h - PANEL_MARGIN_PX
            const left = Math.max(PANEL_MARGIN_PX, Math.min(cx - w / 2, maxLeft))
            const below = cy + PANEL_GAP_PX
            const top = below <= maxTop ? below : cy - PANEL_GAP_PX - h
            const root = document.documentElement.style
            root.setProperty("--order-panel-left", `${Math.round(left)}px`)
            root.setProperty(
              "--order-panel-top",
              `${Math.round(Math.max(PANEL_MARGIN_PX, Math.min(top, maxTop)))}px`
            )
          },

          clearPanelPosition() {
            const root = document.documentElement.style
            root.removeProperty("--order-panel-left")
            root.removeProperty("--order-panel-top")
          },

          // A view smaller than the board stays over it (with a little sea at
          // the edges); a view larger than the board on an axis stays centred.
          clamped(next) {
            const b = this.base
            const axis = (pos, size, start, length) => {
              if (size >= length) return start + length / 2 - size / 2
              const slack = size * EDGE_SLACK
              return Math.min(Math.max(pos, start - slack), start + length - size + slack)
            }
            return { ...next, x: axis(next.x, next.w, b.x, b.w), y: axis(next.y, next.h, b.y, b.h) }
          },

          clientToViewBox(clientX, clientY) {
            const rect = this.svg.getBoundingClientRect()
            const upp = this.current.w / rect.width
            return {
              x: this.current.x + (clientX - rect.left) * upp,
              y: this.current.y + (clientY - rect.top) * upp
            }
          },

          // Zoom so `vbPoint` (a viewBox-space point) lands back under the
          // client point (clientX, clientY) — the same anchoring math serves
          // pinch, wheel, keyboard and double tap.
          computeZoom(newW, vbPoint, clientX, clientY) {
            const rect = this.svg.getBoundingClientRect()
            const aspect = this.aspect()
            const w = Math.min(Math.max(newW, this.base.w / MAX_SCALE), this.fitWidth(aspect))
            const upp = w / rect.width

            return this.clamped({
              w,
              h: w / aspect,
              x: vbPoint.x - (clientX - rect.left) * upp,
              y: vbPoint.y - (clientY - rect.top) * upp
            })
          },

          animateTo(target) {
            if (this.raf) cancelAnimationFrame(this.raf)

            if (this.reduceMotion) {
              this.current = target
              this.applyViewBox()
              return
            }

            const start = { ...this.current }
            const startTime = performance.now()

            const step = (now) => {
              const t = Math.min(1, (now - startTime) / ANIMATE_MS)
              const eased = 1 - Math.pow(1 - t, 3)
              this.current = {
                x: start.x + (target.x - start.x) * eased,
                y: start.y + (target.y - start.y) * eased,
                w: start.w + (target.w - start.w) * eased,
                h: start.h + (target.h - start.h) * eased
              }
              this.applyViewBox()
              if (t < 1) this.raf = requestAnimationFrame(step)
            }

            this.raf = requestAnimationFrame(step)
          },

          showView(target) {
            this.animateTo(target)
            this.save(target)
          },

          resetToFit() {
            this.showView(this.fit())
          },

          zoomTo(newW, vbPoint, clientX, clientY, { animate = false } = {}) {
            const target = this.computeZoom(newW, vbPoint, clientX, clientY)
            if (animate) {
              this.animateTo(target)
            } else {
              this.current = target
              this.applyViewBox()
            }
            this.save(target)
            return target
          },

          // --- board lookups -------------------------------------------------

          labelOf(area) {
            const count = this.el.querySelector(`.world-map-count[data-area="${area}"]`)
            if (!count) return null
            return { x: Number(count.getAttribute("x")), y: Number(count.getAttribute("y")) }
          },

          // The territory under a point — or, over open sea, the nearest army
          // token within reach, so Iceland or Madagascar don't need a perfect
          // fingertip.
          territoryAt(clientX, clientY) {
            const under = document.elementFromPoint(clientX, clientY)
            // An order arrow sits over the board and has its own click
            // (`select_order`) — never reinterpret it as the land beneath.
            if (under?.closest?.(".world-map-order")) return null
            const hit = under?.closest?.(".world-map-territory")
            if (hit && this.el.contains(hit)) return hit

            let best = null
            let bestDistance = TOKEN_REACH_PX
            this.el.querySelectorAll(".world-map-count[data-area]").forEach((count) => {
              const r = count.getBoundingClientRect()
              const d = Math.hypot(r.left + r.width / 2 - clientX, r.top + r.height / 2 - clientY)
              if (d < bestDistance) {
                bestDistance = d
                best = count.dataset.area
              }
            })
            return best ? this.el.querySelector(`#territory-${best}`) : null
          },

          // The game gestures are on only where the phone HUD is (below `lg`),
          // and only while the viewer can act: `data-unassigned` is rendered
          // for a seated player who hasn't ended their turn.
          gestures() {
            return this.el.dataset.unassigned !== undefined && !this.desktop.matches
          },

          unplaced() {
            return Number(this.el.dataset.unassigned || 0) - this.pendingPlacements
          },

          // --- pointer gestures ----------------------------------------------

          onPointerDown(e) {
            this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY })

            if (this.pointers.size === 1) {
              this.gestureStart = { x: e.clientX, y: e.clientY }
              this.moved = false
              this.lastSingle = { x: e.clientX, y: e.clientY }
              this.pinch = null
              this.suppressClick = false
              this.press = this.pressAt(e.clientX, e.clientY)
              if (this.press?.canPlace) {
                this.press.timer = setTimeout(() => this.onHold(), HOLD_MS)
              }
            } else if (this.pointers.size === 2) {
              this.cancelHold()
              this.endDrag(false)
              this.lastSingle = null
              this.pinch = this.pinchState()
            }

            // A finger added mid-drag never crosses the drag threshold itself, so
            // capture it now rather than leaving it uncaptured for the rest of
            // the gesture (a lost pointerup would leave the map stuck pinching).
            if (this.moved) this.capturePointers()
          },

          pressAt(clientX, clientY) {
            if (!this.gestures()) return null
            const territory = this.territoryAt(clientX, clientY)
            if (!territory) return null
            const mine = territory.dataset.mine !== undefined
            const area = territory.dataset.area

            // An order is dragged from the army token, not from anywhere on the
            // land: a big territory (or a screen full of your own) still pans.
            const token = this.el
              .querySelector(`.world-map-count[data-area="${area}"]`)
              ?.getBoundingClientRect()
            const onToken =
              !!token &&
              Math.hypot(
                token.left + token.width / 2 - clientX,
                token.top + token.height / 2 - clientY
              ) <= TOKEN_GRAB_PX

            return {
              area,
              canPlace: mine && this.unplaced() > 0,
              canDrag: mine && onToken && Number(territory.dataset.armies || 0) > 1,
              adjacent: (territory.dataset.adjacent || "").split(",").filter(Boolean),
              timer: null
            }
          },

          onHold() {
            if (!this.press || this.moved) return
            this.press.timer = null
            this.suppressClick = true
            this.place(this.press.area, HOLD_AMOUNT)
          },

          cancelHold() {
            if (this.press?.timer) clearTimeout(this.press.timer)
            if (this.press) this.press.timer = null
          },

          onPointerMove(e) {
            if (!this.pointers.has(e.pointerId)) return
            this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY })

            if (this.gestureStart && !this.moved) {
              const dx = e.clientX - this.gestureStart.x
              const dy = e.clientY - this.gestureStart.y
              if (Math.hypot(dx, dy) > DRAG_PX) {
                this.moved = true
                this.cancelHold()
                this.capturePointers()
                if (this.pointers.size === 1 && this.press?.canDrag && !this.suppressClick) {
                  this.startDrag()
                }
              }
            }

            if (this.drag) {
              this.updateDrag(e.clientX, e.clientY)
              return
            }

            if (this.pointers.size === 1 && this.lastSingle) {
              const dx = e.clientX - this.lastSingle.x
              const dy = e.clientY - this.lastSingle.y
              this.lastSingle = { x: e.clientX, y: e.clientY }
              // Below the drag threshold a press on a draggable territory might
              // still become an order — don't nudge the map under it yet.
              if (!this.moved && this.press?.canDrag) return
              const rect = this.svg.getBoundingClientRect()
              const upp = this.current.w / rect.width
              this.current = this.clamped({
                ...this.current,
                x: this.current.x - dx * upp,
                y: this.current.y - dy * upp
              })
              this.applyViewBox()
            } else if (this.pointers.size === 2 && this.pinch) {
              if (!this.moved) this.capturePointers()
              this.moved = true
              const next = this.pinchState()
              const vbPoint = this.clientToViewBox(this.pinch.mid.x, this.pinch.mid.y)
              const scaleFactor = this.pinch.dist / Math.max(next.dist, 1)
              this.current = this.computeZoom(
                this.current.w * scaleFactor,
                vbPoint,
                next.mid.x,
                next.mid.y
              )
              this.applyViewBox()
              this.pinch = next
            }
          },

          onPointerUp(e) {
            this.pointers.delete(e.pointerId)

            if (this.drag && this.pointers.size === 0) {
              if (e.type === "pointerup") this.updateDrag(e.clientX, e.clientY)
              this.endDrag(e.type === "pointerup")
            }

            if (this.pointers.size === 1) {
              const [remaining] = this.pointers.values()
              this.lastSingle = { ...remaining }
              this.pinch = null
            } else if (this.pointers.size === 0) {
              this.cancelHold()
              this.pinch = null
              this.lastSingle = null
              this.gestureStart = null
              this.save()
            }
          },

          // Capture only once a gesture is really a drag: capturing on pointerdown
          // retargets the tap's `click` to this wrapper, so a territory's
          // phx-click="select_area" would never fire. Capture is a nice-to-have
          // (keeps a fast finger receiving moves after it strays outside the
          // wrapper) and can fail (InvalidPointerId) in edge cases — the pointer
          // then stays tracked, just uncaptured.
          capturePointers() {
            for (const id of this.pointers.keys()) {
              if (this.el.hasPointerCapture?.(id)) continue
              try {
                this.el.setPointerCapture?.(id)
              } catch {
                // Ignored — see above.
              }
            }
          },

          pinchState() {
            const [p1, p2] = [...this.pointers.values()]
            return {
              dist: Math.hypot(p2.x - p1.x, p2.y - p1.y),
              mid: { x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 }
            }
          },

          // --- drag to order ---------------------------------------------------

          startDrag() {
            const origin = this.labelOf(this.press.area)
            if (!origin) return
            this.drag = {
              from: this.press.area,
              adjacent: new Set(this.press.adjacent),
              origin,
              target: null,
              kind: null
            }
            this.showDropTargets()
            buzz(8)
          },

          // Veil the board and redraw the source and each neighbour it can
          // reach on top, as clones in the client-owned drag layer — the real
          // territories are LiveView's to patch and are left alone.
          showDropTargets() {
            if (!this.dragLayer) return
            const svgNs = "http://www.w3.org/2000/svg"
            const veil = document.createElementNS(svgNs, "rect")
            const { x, y, w, h } = this.fit()
            veil.setAttribute("x", x - w)
            veil.setAttribute("y", y - h)
            veil.setAttribute("width", w * 3)
            veil.setAttribute("height", h * 3)
            veil.setAttribute("class", "world-map-drag-veil")

            const clone = (area, role) => {
              const territory = this.el.querySelector(`#territory-${area}`)
              if (!territory) return null
              const use = document.createElementNS(svgNs, "use")
              use.setAttribute("href", `#gc-area-${area}`)
              use.setAttribute("class", `world-map-owner world-map-drag-area world-map-drag-area--${role}`)
              use.dataset.area = area
              if (territory.dataset.owner) use.dataset.owner = territory.dataset.owner
              return use
            }

            const clones = [
              ...[...this.drag.adjacent].map((area) => clone(area, "target")),
              clone(this.drag.from, "source")
            ]
            this.dragLayer.replaceChildren(veil, ...clones.filter(Boolean))
          },

          updateDrag(clientX, clientY) {
            const territory = this.territoryAt(clientX, clientY)
            const area = territory?.dataset.area
            const target = area && this.drag.adjacent.has(area) ? area : null

            if (target !== this.drag.target) {
              this.drag.target = target
              this.drag.kind = target
                ? territory.dataset.mine !== undefined
                  ? "transfer"
                  : "attack"
                : null
              if (target) buzz(4)
              this.dragLayer?.querySelectorAll(".world-map-drag-area--target").forEach((use) => {
                use.classList.toggle("is-hover", use.dataset.area === target)
              })
            }

            const end = (target && this.labelOf(target)) || this.clientToViewBox(clientX, clientY)
            this.drawGhost(this.drag.origin, end, this.drag.kind)
          },

          endDrag(commit) {
            if (!this.drag) return
            const { from, target } = this.drag
            this.drag = null
            this.dragLayer?.replaceChildren()
            this.ghost?.replaceChildren()

            if (commit && target) {
              buzz(15)
              this.pushEvent("drag_order", { from, to: target })
            }
          },

          // Same bow as `WorldMap.order_curve/3`, so the preview lands exactly
          // where the queued arrow will be drawn.
          curve(a, b) {
            const { trim, trimRatio, bow: bowRatio, wrap } = this.curveShape
            let x2 = b.x
            if (wrap && Math.abs(x2 - a.x) > wrap / 2) x2 += x2 > a.x ? -wrap : wrap
            const dx = x2 - a.x
            const dy = b.y - a.y
            const len = Math.max(Math.hypot(dx, dy), 1)
            const cut = Math.min(trim, len * trimRatio)
            const ux = dx / len
            const uy = dy / len
            const sx = a.x + ux * cut
            const sy = a.y + uy * cut
            const ex = x2 - ux * cut
            const ey = b.y - uy * cut
            const bow = len * bowRatio
            const cx = (sx + ex) / 2 - uy * bow
            const cy = (sy + ey) / 2 + ux * bow
            return `M${sx} ${sy} Q${cx} ${cy} ${ex} ${ey}`
          },

          drawGhost(from, to, kind) {
            if (!this.ghost) return
            let path = this.ghost.querySelector("path")
            if (!path) {
              path = document.createElementNS("http://www.w3.org/2000/svg", "path")
              this.ghost.appendChild(path)
            }
            path.setAttribute("d", this.curve(from, to))
            path.setAttribute("class", `world-map-ghost-line world-map-ghost-line--${kind || "none"}`)
            if (kind) path.setAttribute("marker-end", `url(#gc-order-arrowhead-${kind})`)
            else path.removeAttribute("marker-end")
          },

          // --- taps: place, territory click, double-tap zoom -----------------

          onClick(e) {
            if (this.moved || this.suppressClick) {
              e.stopPropagation()
              e.preventDefault()
              this.suppressClick = false
              return
            }

            // A pointer tap on an own territory while reinforcements are
            // unplaced places one instead of selecting (keyboard Enter/Space
            // still selects — `.TerritoryKeyboard` — so the order panel stays
            // reachable). Never a double-tap zoom: tapping fast is how you
            // place several.
            if (e.detail > 0 && this.gestures()) {
              const territory = this.territoryAt(e.clientX, e.clientY)
              const mine = territory?.dataset.mine !== undefined
              // The tap after the last army is placed is still part of the
              // same burst: swallow it rather than pop the order panel open.
              const justPlaced = Date.now() - this.lastPlaceAt < PLACE_COOLDOWN_MS
              if (mine && (this.unplaced() > 0 || justPlaced)) {
                e.stopPropagation()
                e.preventDefault()
                this.lastTap = null
                this.place(territory.dataset.area, 1)
                return
              }
            }

            const now = Date.now()
            const isDoubleTap =
              this.lastTap &&
              now - this.lastTap.time < DOUBLE_TAP_MS &&
              Math.hypot(e.clientX - this.lastTap.x, e.clientY - this.lastTap.y) < DOUBLE_TAP_PX

            if (isDoubleTap) {
              e.stopPropagation()
              e.preventDefault()
              this.lastTap = null
              this.doubleTapZoom(e.clientX, e.clientY)
              return
            }

            this.lastTap = { time: now, x: e.clientX, y: e.clientY }
          },

          // Optimistic: placements still on their way to the server count
          // against the pool locally, so a burst of taps can't overshoot it.
          // Each one stops counting when its own reply lands — by then the
          // server-rendered `data-unassigned` already includes it.
          place(area, amount) {
            const n = Math.min(amount, this.unplaced())
            if (n <= 0) return
            this.pendingPlacements += n
            this.lastPlaceAt = Date.now()
            buzz(n > 1 ? [12, 40, 12] : 10)
            this.bump(area)
            const settle = () => {
              this.pendingPlacements = Math.max(0, this.pendingPlacements - n)
            }
            // Settles on a failed push too (socket down), or the pool would
            // stay short by `n` for good.
            this.pushEvent("quick_assign", { area, amount: n }).then(settle, settle)
          },

          doubleTapZoom(clientX, clientY) {
            if (this.current.w < this.fitWidth() - 0.01) {
              this.resetToFit()
              return
            }
            const vb = this.clientToViewBox(clientX, clientY)
            this.zoomTo(this.fitWidth() / DOUBLE_TAP_ZOOM, vb, clientX, clientY, { animate: true })
          },

          // --- count feedback ------------------------------------------------

          readCounts() {
            const counts = {}
            this.el.querySelectorAll(".world-map-count[data-area]").forEach((c) => {
              counts[c.dataset.area] = c.firstChild?.textContent?.trim()
            })
            return counts
          },

          bump(area) {
            const inner = this.el.querySelector(
              `.world-map-token[data-area="${area}"] .world-map-token-inner`
            )
            if (!inner) return
            inner.classList.remove("is-bumped")
            void inner.getBBox?.()
            inner.classList.add("is-bumped")
          },

          bumpChangedCounts() {
            const counts = this.readCounts()
            Object.entries(counts).forEach(([area, value]) => {
              if (this.counts[area] !== undefined && this.counts[area] !== value) this.bump(area)
            })
            this.counts = counts
          },

          // --- wheel, keyboard, fit button, resize --------------------------

          onWheel(e) {
            if (!e.ctrlKey) return
            e.preventDefault()
            const factor = Math.exp(e.deltaY * 0.01)
            const vb = this.clientToViewBox(e.clientX, e.clientY)
            this.zoomTo(this.current.w * factor, vb, e.clientX, e.clientY)
          },

          onKeyDown(e) {
            const rect = this.svg.getBoundingClientRect()
            const cx = rect.left + rect.width / 2
            const cy = rect.top + rect.height / 2
            const panStep = this.current.w * 0.1

            switch (e.key) {
              case "+":
              case "=":
                e.preventDefault()
                this.zoomTo(this.current.w / 1.2, this.clientToViewBox(cx, cy), cx, cy, { animate: true })
                return
              case "-":
              case "_":
                e.preventDefault()
                this.zoomTo(this.current.w * 1.2, this.clientToViewBox(cx, cy), cx, cy, { animate: true })
                return
              case "ArrowUp":
                e.preventDefault()
                this.current = this.clamped({ ...this.current, y: this.current.y - panStep })
                break
              case "ArrowDown":
                e.preventDefault()
                this.current = this.clamped({ ...this.current, y: this.current.y + panStep })
                break
              case "ArrowLeft":
                e.preventDefault()
                this.current = this.clamped({ ...this.current, x: this.current.x - panStep })
                break
              case "ArrowRight":
                e.preventDefault()
                this.current = this.clamped({ ...this.current, x: this.current.x + panStep })
                break
              default:
                return
            }

            this.applyViewBox()
            this.save()
          },

          // The Fit button lives in the status strip, outside this wrapper —
          // its own `.MapFit` hook dispatches this window event. From the whole
          // board it goes back to the starting view (on a phone held upright,
          // the zoom around your own territories); from anywhere else it fits.
          onFitEvent() {
            if (this.current.w >= this.fitWidth() - 0.01) this.showView(this.home())
            else this.resetToFit()
          },

          // The stage changed shape (rotation, address bar, keyboard, a
          // devtools panel): keep the centre and zoom and take the new shape —
          // except that turning a phone between upright and sideways starts
          // over from its home view (sideways shows the whole board).
          onResize() {
            const aspect = this.aspect()
            const flipped = aspect >= 1 !== this.lastAspect >= 1
            this.lastAspect = aspect
            this.current =
              flipped && !this.desktop.matches
                ? this.home()
                : this.withAspect(this.current)
            this.applyViewBox()
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

  attr :mine, :boolean,
    default: false,
    doc: "the viewer owns this (visible) area — a drag from it can become an order"

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
      data-interactive={@interactive}
      data-mine={@interactive && @mine}
      data-armies={@interactive && @mine && @area.armies}
      data-adjacent={@interactive && Enum.join(@area.adjacent, ",")}
      phx-hook=".TerritoryKeyboard"
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

  attr :owner, :any, default: nil, doc: "the fill's owner slot, which colours the token's ring"

  # Each count sits on a round token ringed in the owner colour, like a game
  # piece, with a gold `+N` badge while reinforcements are queued on it. The
  # outer group is scaled by `--token-scale` (set by `.MapViewport` from the
  # zoom level) so tokens stay a thumb-readable size instead of shrinking with
  # the board; the inner one is what `.MapViewport` bumps when the count changes.
  defp army_count(assigns) do
    {x, y} = Geometry.label(assigns.map_name, assigns.area.number)
    assigns = assign(assigns, x: x, y: y, pending: Map.get(assigns.area, :pending_armies, 0))

    # `paint-order`/`stroke-linejoin` are presentation attributes here (they need
    # no theme token) so the outline-under-glyphs contract is visible in the
    # rendered markup; the stroke/fill colours come from `.world-map-count`.
    ~H"""
    <g
      class="world-map-token world-map-owner"
      data-owner={@owner}
      data-area={@area.number}
      style={"transform-origin: #{@x}px #{@y}px"}
    >
      <g class="world-map-token-inner" style={"transform-origin: #{@x}px #{@y}px"}>
        <circle cx={@x} cy={@y} r="9" class="world-map-token-ring" />
        <text
          x={@x}
          y={@y}
          class="world-map-count"
          data-area={@area.number}
          text-anchor="middle"
          dominant-baseline="central"
          paint-order="stroke"
          stroke-linejoin="round"
        >
          {@area.armies}
          <tspan :if={@delta} dx="10" class="world-map-delta">{delta_text(@delta)}</tspan>
        </text>
        <g :if={@pending > 0} class="world-map-pending">
          <rect x={@x + 3} y={@y - 15} width="16" height="10" rx="5" />
          <text
            x={@x + 11}
            y={@y - 10}
            text-anchor="middle"
            dominant-baseline="central"
          >
            +{@pending}
          </text>
        </g>
      </g>
    </g>
    """
  end

  defp delta_text(delta) when delta > 0, do: "(+#{delta})"
  defp delta_text(delta), do: "(#{delta})"

  # One `world-map-replay` arrow per `:attack`/`:transfer` step — `:assign`/
  # `:eliminated`/`:ended` steps have no `from`/`to` and are filtered out of
  # `@replay_arrows` before this ever renders (see `world_map/1`). Static and fully
  # visible by default (no-JS / prefers-reduced-motion); `data-step` is what the
  # `.TurnReplay` hook keys its stepwise reveal off of.
  attr :step, :map, required: true

  defp replay_arrow(assigns) do
    ~H"""
    <line
      data-step={@step.index}
      class={["world-map-replay-arrow", replay_color_class(@step.kind)]}
      x1={@step.from.x}
      y1={@step.from.y}
      x2={@step.to.x}
      y2={@step.to.y}
    />
    """
  end

  defp replay_color_class(:attack), do: "world-map-replay-arrow--attack"
  defp replay_color_class(:transfer), do: "world-map-replay-arrow--transfer"

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

  # The elements art fills its generated, cropped view box edge to edge, so
  # the region bonus legend gets a 100-unit strip of sea added on the left.
  # Everything that reads the view box (the SVG, `.MapViewport`'s base box,
  # `board_ground/1`) takes it from this one assign, so they stay in step.
  @elements_view_box "136 54 556 421"

  @doc "The board's SVG `viewBox`: `MapGeometry`'s, plus the legend strip on elements."
  def view_box(:elements), do: @elements_view_box
  def view_box(map_name), do: Geometry.view_box(map_name)

  # A printed-board style legend of every region's control bonus, drawn into
  # the sea in the board's bottom-left corner so it pans and zooms with the
  # art. `{x, y}` is the box's top-left, checked clear of every territory and
  # sea lane on the world map; elements draws it smaller because that board
  # renders ~1.5x larger per SVG unit. Decorative and aria-hidden —
  # `GameLive`'s `region_bonuses/1` carries the same numbers accessibly.
  @legend_width 150
  @legend_height 152
  @legend_placement %{original: {8, 320, 1}, elements: {142, 375, 0.62}}

  @doc false
  def legend(map_name) do
    {x, y, scale} = Map.fetch!(@legend_placement, map_name)

    # Highest bonus first; `sort_by` is stable, so ties keep region order.
    rows =
      for {number, name, _num_areas, bonus} <- MapInfo.regions(map_name) do
        %{number: number, name: name, bonus: bonus}
      end
      |> Enum.sort_by(& &1.bonus, :desc)

    %{x: x, y: y, scale: scale, width: @legend_width, height: @legend_height, rows: rows}
  end

  defp region_centroid(map_name, area_numbers) do
    points = Enum.map(area_numbers, &Geometry.label(map_name, &1))
    {sum_x, sum_y} = Enum.reduce(points, {0, 0}, fn {x, y}, {sx, sy} -> {sx + x, sy + y} end)
    count = length(points)
    {sum_x / count, sum_y / count}
  end

  # One arrow per owned area carrying a queued transfer/attack, from its
  # label anchor to the target's — the same anchors `army_count/1` uses, so an arrow
  # always starts/ends exactly where the two counts it connects are drawn. A thick
  # transparent `.world-map-order-hit` line rides under the thin visible dashed one
  # because the visible stroke alone (2px) is too thin a hit target for a pointer or
  # touch to reliably land on, unlike a territory's whole filled silhouette.
  attr :area, :map, required: true
  attr :area_names, :map, required: true
  attr :map_name, :atom, required: true
  attr :interactive, :boolean, required: true

  defp order_arrow(assigns) do
    from = Geometry.label(assigns.map_name, assigns.area.number)
    to = Geometry.label(assigns.map_name, assigns.area.order.target)
    kind = to_string(assigns.area.order.command)
    target_name = Map.fetch!(assigns.area_names, assigns.area.order.target)
    %{d: d, mid: {mx, my}} = order_curve(assigns.map_name, from, to)

    assigns =
      assign(assigns,
        d: d,
        mx: mx,
        my: my,
        kind: kind,
        label: order_label(assigns.area.name, assigns.area.order, target_name)
      )

    ~H"""
    <g
      id={"order-#{@area.number}"}
      class={["world-map-order", @interactive && "world-map-order--interactive"]}
      role={@interactive && "button"}
      tabindex={@interactive && "0"}
      aria-label={@label}
      data-area={@area.number}
      data-select-event={@interactive && "select_order"}
      data-interactive={@interactive}
      phx-hook=".TerritoryKeyboard"
      phx-click={@interactive && "select_order"}
      phx-value-area={@interactive && @area.number}
    >
      <path d={@d} class="world-map-order-hit" />
      <path
        d={@d}
        class={"world-map-order-line world-map-order-line--#{@kind}"}
        marker-end={"url(#gc-order-arrowhead-#{@kind})"}
      />
      <g
        class={"world-map-order-badge world-map-order-badge--#{@kind}"}
        style={"transform-origin: #{@mx}px #{@my}px"}
      >
        <circle cx={@mx} cy={@my} r="8" />
        <text
          x={@mx}
          y={@my}
          class="world-map-order-amount"
          text-anchor="middle"
          dominant-baseline="central"
          paint-order="stroke"
          stroke-linejoin="round"
        >
          {@area.order.amount}
        </text>
      </g>
    </g>
    """
  end

  # A gentle quadratic bow from one label anchor to the other, trimmed at both
  # ends so the arrow starts and stops beside the two tokens rather than under
  # them. The world map's Alaska <-> Pevek lane wraps off the board edges, so a
  # link spanning more than half the board aims at the wrapped copy of its
  # target and runs off the near edge instead of across the whole world.
  # `.MapViewport`'s drag preview draws the same curve client-side from the
  # same numbers, handed over in `data-curve` (`curve_json/1`).
  @curve_trim 11.0
  @curve_trim_ratio 0.3
  @curve_bow 0.14
  @curve_wrap %{original: 800}

  defp curve_json(map_name) do
    Jason.encode!(%{
      trim: @curve_trim,
      trimRatio: @curve_trim_ratio,
      bow: @curve_bow,
      wrap: Map.get(@curve_wrap, map_name)
    })
  end

  @doc false
  def order_curve(map_name, {x1, y1}, {x2, y2}) do
    x2 =
      case Map.get(@curve_wrap, map_name) do
        wrap when is_number(wrap) and abs(x2 - x1) > wrap / 2 ->
          if(x2 > x1, do: x2 - wrap, else: x2 + wrap)

        _ ->
          x2
      end

    dx = x2 - x1
    dy = y2 - y1
    len = max(:math.sqrt(dx * dx + dy * dy), 1.0)
    cut = min(@curve_trim, len * @curve_trim_ratio)
    {ux, uy} = {dx / len, dy / len}
    {sx, sy} = {x1 + ux * cut, y1 + uy * cut}
    {ex, ey} = {x2 - ux * cut, y2 - uy * cut}
    bow = len * @curve_bow
    {cx, cy} = {(sx + ex) / 2 - uy * bow, (sy + ey) / 2 + ux * bow}
    r = &Float.round(&1 * 1.0, 1)

    %{
      d: "M#{r.(sx)} #{r.(sy)} Q#{r.(cx)} #{r.(cy)} #{r.(ex)} #{r.(ey)}",
      mid: {r.((sx + 2 * cx + ex) / 4), r.((sy + 2 * cy + ey) / 4)}
    }
  end

  @doc """
  The board point (`"x,y"`) at the middle of the arrow an order from area
  `from` to area `to` draws — where `GameLive`'s order panel anchors itself on
  a phone.
  """
  def order_anchor(map_name, from, to) do
    %{mid: {x, y}} =
      order_curve(map_name, Geometry.label(map_name, from), Geometry.label(map_name, to))

    "#{x},#{y}"
  end

  @doc """
  True when `area` (a `PlayerView` area) carries a live queued order. An order
  cut to zero armies is the "removed" state — the engine has no separate
  cancel, so `GameLive`'s Remove resubmits zero — and counts as no order:
  no arrow, no line in Your orders, not counted as ready.
  """
  def queued_order?(%{order: %{amount: amount}}) when amount > 0, do: true
  def queued_order?(_area), do: false

  defp mine?(_area, nil), do: false
  defp mine?(area, viewer_number), do: area.visible and area.owner_number == viewer_number

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

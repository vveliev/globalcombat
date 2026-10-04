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
  button. The territories form one roving-tabindex group: a single Tab stop
  (the selected area, else the first) and the arrow keys moving focus to the
  nearest territory in that direction. The army-count text is decorative
  (`aria-hidden`, the label already says it) and gets a dark stroke under a light fill via `paint-order: stroke`
  so it stays legible on every owner colour. `GameLive.Board.board_table/1`
  remains the tabular equivalent for screen readers; it and the labels
  here share `owner_text/2` so the two can never word an owner differently.

  Last-turn replay: the board renders every replay arrow, capture pulse and
  army count statically (no-JS and reduced-motion fallback); the `<svg>`'s
  colocated `.MapReplay` hook is the only code that animates them. It takes
  its state from a `gc:replay` window event (`%{current, animate, counts}`)
  that `GameLive`'s `.TurnReplay` controls broadcast, and finds counts by
  their own ids (`territory-count-N`, original value in `data-armies`), so
  no caller reaches into this component's markup.

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
      fogged non-owner. A seated player with no frontier at all (eliminated,
      or a winner holding the whole board) gets the same fallback rather
      than a board of nothing but dimmed areas.
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
  nor "unclaimed" — collapsing the two would make a fogged enemy tile
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

  def world_map(assigns) do
    lens = effective_lens(assigns.lens, assigns.areas, assigns.viewer_number)

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
      |> assign(:tab_stop, tab_stop(assigns.selected_area, assigns.areas))

    ~H"""
    <div
      id="world-map"
      class="world-map"
      data-map={@map_name}
      data-view-box={@view_box}
      data-game-id={@game_id}
      data-zoomed="false"
      tabindex="0"
      phx-hook=".MapViewport"
    >
      <svg
        id="world-map-board"
        phx-hook=".MapReplay"
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
            tab_stop={area.number == @tab_stop}
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
        <g :if={Enum.any?(@areas, & &1.order)} class="world-map-orders">
          <.order_arrow
            :for={area <- @areas}
            :if={area.order}
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
        // SVG has no <button>, so a territory (or order arrow) is a focusable
        // role="button" <g>; this gives it the keyboard activation a real button
        // has for free. Clicks go through phx-click on the same element — this
        // hook covers Enter/Space (Space must be swallowed or the page
        // scrolls) and, for territories, arrow-key navigation. `data-select-event`
        // lets an order arrow reuse this hook while pushing `select_order`
        // instead of a territory's `select_area` (defaulting to `select_area`
        // so territories need no extra attribute). `phx-hook` must stay a
        // static string so LiveView's colocated-hook rewrite can match it to
        // the manifest — `@interactive` instead gates `data-interactive`,
        // checked on every keydown so a live toggle of interactivity (no
        // remount) still takes effect.
        //
        // Arrow keys move focus to the nearest territory in that direction,
        // measured between label anchors (`data-cx`/`data-cy`), so the board
        // is one roving-tabindex group: only one territory is in the Tab
        // order (`world_map/1`'s tab stop) and the arrows move within it.
        // The event stops here so `.MapViewport` doesn't also pan the map.
        const DIRECTIONS = {
          ArrowUp: [0, -1],
          ArrowDown: [0, 1],
          ArrowLeft: [-1, 0],
          ArrowRight: [1, 0]
        }

        const anchor = (el) => ({ x: Number(el.dataset.cx), y: Number(el.dataset.cy) })

        export default {
          mounted() {
            this.el.addEventListener("keydown", (e) => {
              if (this.el.dataset.interactive === undefined) return

              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault()
                this.pushEvent(this.el.dataset.selectEvent || "select_area", {area: this.el.dataset.area})
                return
              }

              const direction = DIRECTIONS[e.key]
              if (direction && this.el.dataset.cx !== undefined) {
                e.preventDefault()
                e.stopPropagation()
                this.nearest(direction)?.focus()
              }
            })
          },

          // Distance along the arrow plus double the sideways offset: a
          // territory straight ahead beats a closer one off to the side.
          nearest([dx, dy]) {
            const from = anchor(this.el)
            let best = null
            let bestScore = Infinity

            for (const el of this.el.parentNode.querySelectorAll("[data-cx][data-interactive]")) {
              if (el === this.el) continue
              const to = anchor(el)
              const along = (to.x - from.x) * dx + (to.y - from.y) * dy
              if (along <= 0) continue
              const across = Math.abs((to.x - from.x) * dy - (to.y - from.y) * dx)
              const score = along + 2 * across
              if (score < bestScore) {
                best = el
                bestScore = score
              }
            }

            return best
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".MapReplay">
        // The board side of the last-turn replay. `GameLive`'s `.TurnReplay`
        // hook owns the timing and broadcasts where the replay is as a
        // `gc:replay` window event (`{current, animate, counts}`, counts
        // keyed by area number); this hook owns the board markup that state
        // touches — arrow reveal, the capture pulse, and the running army
        // counts (`#territory-count-N`, restored from `data-armies` when no
        // step overrides them). LiveView resets anything the server didn't
        // render (`is-revealed`, a count's text) whenever it patches this
        // subtree, and any such patch also visits this <svg>, so `updated()`
        // re-applies the last state and an unrelated patch (a chat message)
        // can no longer wipe a replay in progress.
        export default {
          mounted() {
            this.state = { current: -1, animate: false, counts: {} }
            this.shownCurrent = null
            this.onReplay = (e) => {
              this.state = e.detail
              this.apply()
            }
            window.addEventListener("gc:replay", this.onReplay)
            // `.TurnReplay` may have mounted, and broadcast, before this did.
            window.dispatchEvent(new CustomEvent("gc:replay-sync"))
          },

          updated() {
            this.apply()
          },

          destroyed() {
            window.removeEventListener("gc:replay", this.onReplay)
          },

          apply() {
            const { current, animate, counts } = this.state
            const stepChanged = current !== this.shownCurrent
            this.shownCurrent = current

            const layer = this.el.querySelector(".world-map-replay")
            if (layer) {
              layer.classList.toggle("world-map-replay--js", animate)
              layer.querySelectorAll("[data-step]").forEach((el) => {
                const step = Number(el.dataset.step)
                el.classList.toggle("is-revealed", step <= current)
                if (el.classList.contains("world-map-replay-pulse")) this.pulse(el, step === current, stepChanged)
              })
            }

            this.el.querySelectorAll(".world-map-count[data-armies]").forEach((el) => {
              const value = String(counts[el.dataset.area] ?? el.dataset.armies)
              const text = el.firstChild
              if (text && text.textContent.trim() !== value) text.textContent = value
            })
          },

          // Landing on the capture step always shows *some* indicator —
          // reduced motion (media query, `app.css`) drops the animating
          // keyframe but keeps a static ring. Removing and re-adding the class
          // (with a forced reflow) replays the animation when the step is
          // revisited; a patch that merely stripped it just puts it back.
          pulse(el, active, restart) {
            if (!active) {
              el.classList.remove("is-active")
            } else if (restart || !el.classList.contains("is-active")) {
              el.classList.remove("is-active")
              void el.getBoundingClientRect()
              el.classList.add("is-active")
            }
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".MapViewport">
        // Pan/pinch/double-tap zoom for the map, without touching territory
        // selection: a tap is only ever cancelled when the pointer actually
        // moved (drag) or when it completes a double tap (zoom, not select).
        // LiveView owns the SVG's viewBox attribute and resets it to the
        // server-rendered value on every patch, so `updated()` re-applies
        // whatever pan/zoom this hook is holding — same pattern as
        // `.MapReplay` re-applying the replay state after a patch.
        //
        // Client <-> viewBox conversions go through `getScreenCTM()`: in the
        // stage the <svg> is sized 100% x 100% of a box whose aspect rarely
        // matches the map's, and its default `preserveAspectRatio` (xMidYMid
        // meet) letterboxes the drawing inside that box, so the element's
        // own client rect is not where the drawing is.
        import {DESKTOP_QUERY} from "@/js/breakpoints"

        const MAX_SCALE = 6
        const DOUBLE_TAP_ZOOM = 2.5
        const DOUBLE_TAP_MS = 300
        const DOUBLE_TAP_PX = 24
        const DRAG_PX = 8
        const VISIBLE_MARGIN = 0.2
        const ANIMATE_MS = 200

        const swallow = (e) => {
          e.stopPropagation()
          e.preventDefault()
        }

        export default {
          mounted() {
            this.svg = this.el.querySelector("svg")
            this.base = this.parseViewBox(this.el.dataset.viewBox)
            this.current = this.restore() || { ...this.base }
            this.pointers = new Map()
            this.moved = false
            this.gestureStart = null
            this.lastSingle = null
            this.pinch = null
            this.lastClick = null
            this.pendingTap = null
            this.deliveringTap = false
            this.pointerType = "mouse"
            this.raf = null
            this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
            this.desktop = window.matchMedia(DESKTOP_QUERY)
            this.lastWidth = window.innerWidth
            this.wasDesktop = this.desktop.matches

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
            this.el.addEventListener("wheel", this.onWheel, { passive: false })
            this.el.addEventListener("keydown", this.onKeyDown)
            window.addEventListener("gc:map-fit", this.onFitEvent)
            window.addEventListener("resize", this.onResize)
            window.addEventListener("orientationchange", this.onResize)
            this.desktop.addEventListener("change", this.onResize)

            this.applyViewBox()
          },

          updated() {
            this.svg = this.el.querySelector("svg")
            this.applyViewBox()
          },

          destroyed() {
            window.removeEventListener("gc:map-fit", this.onFitEvent)
            window.removeEventListener("resize", this.onResize)
            window.removeEventListener("orientationchange", this.onResize)
            this.desktop.removeEventListener("change", this.onResize)
            if (this.raf) cancelAnimationFrame(this.raf)
            if (this.pendingTap) clearTimeout(this.pendingTap.timer)
          },

          // --- viewBox state -----------------------------------------------

          parseViewBox(str) {
            const [x, y, w, h] = str.split(" ").map(Number)
            return { x, y, w, h }
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
            this.el.dataset.zoomed = this.current.w < this.base.w - 0.01 ? "true" : "false"
          },

          clamped(next) {
            const b = this.base
            const minX = b.x - (1 - VISIBLE_MARGIN) * next.w
            const maxX = b.x + b.w - VISIBLE_MARGIN * next.w
            const minY = b.y - (1 - VISIBLE_MARGIN) * next.h
            const maxY = b.y + b.h - VISIBLE_MARGIN * next.h

            return {
              ...next,
              x: Math.min(Math.max(next.x, minX), maxX),
              y: Math.min(Math.max(next.y, minY), maxY)
            }
          },

          // --- client <-> viewBox ------------------------------------------

          // Client pixels per viewBox unit at the current zoom (uniform in x
          // and y under `meet`). Falls back to the element box if the SVG has
          // no CTM (not rendered).
          pixelsPerUnit() {
            const ctm = this.svg.getScreenCTM()
            return ctm ? ctm.a : this.svg.getBoundingClientRect().width / this.current.w
          },

          clientToViewBox(clientX, clientY) {
            const ctm = this.svg.getScreenCTM()
            if (!ctm) return { x: this.current.x, y: this.current.y }
            const p = new DOMPoint(clientX, clientY).matrixTransform(ctm.inverse())
            return { x: p.x, y: p.y }
          },

          // Where the viewBox's top-left corner sits on screen. Under `meet`
          // the letterbox depends only on the aspect ratio, which zooming
          // never changes, so this point stays put across a zoom.
          viewBoxOriginClient() {
            const ctm = this.svg.getScreenCTM()
            if (!ctm) {
              const rect = this.svg.getBoundingClientRect()
              return { x: rect.left, y: rect.top }
            }
            const p = new DOMPoint(this.current.x, this.current.y).matrixTransform(ctm)
            return { x: p.x, y: p.y }
          },

          // Zoom so `vbPoint` (a viewBox-space point) lands back under the
          // client point (clientX, clientY) — the same anchoring math serves
          // pinch (vbPoint from the old midpoint, anchored to the new one),
          // wheel/keyboard zoom (anchored to the same point it zoomed from),
          // and double tap.
          computeZoom(newW, vbPoint, clientX, clientY) {
            const minW = this.base.w / MAX_SCALE
            const clampedW = Math.min(Math.max(newW, minW), this.base.w)
            const newH = clampedW * (this.base.h / this.base.w)
            const origin = this.viewBoxOriginClient()
            const ppu = this.pixelsPerUnit() * (this.current.w / clampedW)

            return this.clamped({
              w: clampedW,
              h: newH,
              x: vbPoint.x - (clientX - origin.x) / ppu,
              y: vbPoint.y - (clientY - origin.y) / ppu
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

          resetToFit() {
            const target = { ...this.base }
            this.animateTo(target)
            this.save(target)
          },

          // Shared by every discrete (non-gesture-driven) zoom: wheel, the
          // +/- keys, and double tap. `animate: true` eases toward the target
          // (skipped under reduced motion by `animateTo` itself); wheel stays
          // un-eased since its own repeated small deltas are already smooth.
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

          // --- pointer gestures: one finger pans, two pinch-zoom -----------

          onPointerDown(e) {
            this.pointerType = e.pointerType || "mouse"
            this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY })

            if (this.pointers.size === 1) {
              this.gestureStart = { x: e.clientX, y: e.clientY }
              this.moved = false
              this.lastSingle = { x: e.clientX, y: e.clientY }
              this.pinch = null
            } else if (this.pointers.size === 2) {
              this.lastSingle = null
              this.pinch = this.pinchState()
            }

            // A finger added mid-drag never crosses the drag threshold itself, so
            // capture it now rather than leaving it uncaptured for the rest of
            // the gesture (a lost pointerup would leave the map stuck pinching).
            if (this.moved) this.capturePointers()
          },

          onPointerMove(e) {
            if (!this.pointers.has(e.pointerId)) return
            this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY })

            if (this.gestureStart) {
              const dx = e.clientX - this.gestureStart.x
              const dy = e.clientY - this.gestureStart.y
              if (!this.moved && Math.hypot(dx, dy) > DRAG_PX) {
                this.moved = true
                this.capturePointers()
              }
            }

            if (this.pointers.size === 1 && this.lastSingle) {
              const dx = e.clientX - this.lastSingle.x
              const dy = e.clientY - this.lastSingle.y
              this.lastSingle = { x: e.clientX, y: e.clientY }
              const ppu = this.pixelsPerUnit()
              this.current = this.clamped({
                ...this.current,
                x: this.current.x - dx / ppu,
                y: this.current.y - dy / ppu
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

            if (this.pointers.size === 1) {
              const [remaining] = this.pointers.values()
              this.lastSingle = { ...remaining }
              this.pinch = null
            } else if (this.pointers.size === 0) {
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

          // --- taps: territory click vs. double-tap zoom --------------------

          // Capture phase, so it runs before LiveView's own click handling.
          // A drag never selects. A mouse click goes straight through (no
          // added latency on desktop; a second click inside the double-click
          // window zooms instead of selecting again). A touch or pen tap is
          // held for the double-tap window and only then delivered, so the
          // first tap of a double tap never reaches phx-click="select_area".
          onClick(e) {
            if (this.deliveringTap) return

            if (this.moved) {
              swallow(e)
              return
            }

            // Keyboard-synthesised clicks (detail 0) are never part of a tap.
            if (e.detail === 0) return

            if ((e.pointerType || this.pointerType) === "mouse") {
              this.onMouseClick(e)
            } else {
              this.onTap(e)
            }
          },

          onMouseClick(e) {
            const now = Date.now()
            const last = this.lastClick
            this.lastClick = { time: now, x: e.clientX, y: e.clientY }

            if (last && this.isDoubleTap(last, now, e)) {
              swallow(e)
              this.lastClick = null
              this.doubleTapZoom(e.clientX, e.clientY)
            }
          },

          onTap(e) {
            swallow(e)
            const now = Date.now()
            const pending = this.pendingTap

            if (pending && this.isDoubleTap(pending, now, e)) {
              clearTimeout(pending.timer)
              this.pendingTap = null
              this.doubleTapZoom(e.clientX, e.clientY)
              return
            }

            // A second tap somewhere else: the first was a single tap after all.
            this.deliverPendingTap()

            this.pendingTap = {
              time: now,
              x: e.clientX,
              y: e.clientY,
              target: e.target,
              targetId: e.target.closest?.("[id]")?.id,
              timer: setTimeout(() => this.deliverPendingTap(), DOUBLE_TAP_MS)
            }
          },

          isDoubleTap(previous, now, e) {
            return (
              now - previous.time < DOUBLE_TAP_MS &&
              Math.hypot(e.clientX - previous.x, e.clientY - previous.y) < DOUBLE_TAP_PX
            )
          },

          // Re-dispatches the held tap as a click on what was tapped, which
          // LiveView then handles like any other click (select_area,
          // select_order, …). A patch may have replaced the tapped node in the
          // meantime, so it is looked up again by id if it has gone.
          deliverPendingTap() {
            const tap = this.pendingTap
            if (!tap) return
            clearTimeout(tap.timer)
            this.pendingTap = null

            const target = tap.target.isConnected
              ? tap.target
              : tap.targetId && document.getElementById(tap.targetId)
            if (!target) return

            this.deliveringTap = true
            try {
              target.dispatchEvent(
                new MouseEvent("click", {
                  bubbles: true,
                  cancelable: true,
                  clientX: tap.x,
                  clientY: tap.y,
                  view: window
                })
              )
            } finally {
              this.deliveringTap = false
            }
          },

          doubleTapZoom(clientX, clientY) {
            if (this.current.w < this.base.w - 0.01) {
              this.resetToFit()
              return
            }
            const vb = this.clientToViewBox(clientX, clientY)
            this.zoomTo(this.base.w / DOUBLE_TAP_ZOOM, vb, clientX, clientY, { animate: true })
          },

          // --- wheel, keyboard, fit button, resize --------------------------

          onWheel(e) {
            if (!e.ctrlKey) return
            e.preventDefault()
            const factor = Math.exp(e.deltaY * 0.01)
            const vb = this.clientToViewBox(e.clientX, e.clientY)
            this.zoomTo(this.current.w * factor, vb, e.clientX, e.clientY)
          },

          // +/- zoom from anywhere inside the map; the arrow keys pan only
          // while the map wrapper itself has focus — on a focused territory
          // they move between territories (`.TerritoryKeyboard`).
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
            }

            if (e.target !== this.el) return

            switch (e.key) {
              case "ArrowUp":
                this.current = this.clamped({ ...this.current, y: this.current.y - panStep })
                break
              case "ArrowDown":
                this.current = this.clamped({ ...this.current, y: this.current.y + panStep })
                break
              case "ArrowLeft":
                this.current = this.clamped({ ...this.current, x: this.current.x - panStep })
                break
              case "ArrowRight":
                this.current = this.clamped({ ...this.current, x: this.current.x + panStep })
                break
              default:
                return
            }

            e.preventDefault()
            this.applyViewBox()
            this.save()
          },

          // The Fit button lives in the status strip, outside this wrapper —
          // its own `.MapFit` hook dispatches this window event rather than
          // us reaching for it with a document-level click listener.
          onFitEvent() {
            this.resetToFit()
          },

          // Below `lg` the stage is meant to start fitted, so a real size
          // change — the width changing (device rotation) or crossing the
          // `lg` breakpoint — refits. Height-only resizes never do: with
          // `interactive-widget=resizes-content` the Android soft keyboard
          // resizes the window whenever the amount field takes focus, and
          // that must not throw away the player's zoom. Above `lg` the board
          // isn't full-height/gesture-first, so a resize (e.g. a devtools
          // panel toggling) leaves a deliberate zoom alone.
          onResize() {
            const width = window.innerWidth
            const desktop = this.desktop.matches
            const sizeClassChanged = width !== this.lastWidth || desktop !== this.wasDesktop
            this.lastWidth = width
            this.wasDesktop = desktop

            if (sizeClassChanged && !desktop) this.resetToFit()
          }
        }
      </script>
    </div>
    """
  end

  # Roving tabindex: the board's territories are one Tab stop, with the
  # arrow keys (`.TerritoryKeyboard`) moving between them. The stop is the
  # selected area when there is one, so Tab returns to where the player was;
  # otherwise the first area.
  defp tab_stop(selected_area, _areas) when is_integer(selected_area), do: selected_area
  defp tab_stop(_selected_area, [first | _]), do: first.number
  defp tab_stop(_selected_area, []), do: nil

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

  attr :tab_stop, :boolean,
    default: false,
    doc:
      "the one territory in the Tab order (roving tabindex; the arrow keys move between the rest)"

  defp territory(assigns) do
    {cx, cy} = Geometry.label(assigns.map_name, assigns.area.number)

    assigns =
      assigns
      |> assign(:label, territory_label(assigns.area, assigns.owner_names))
      |> assign(:element, Geometry.element(assigns.map_name, assigns.area.number))
      |> assign(cx: cx, cy: cy)

    ~H"""
    <g
      id={"territory-#{@area.number}"}
      class={[
        "world-map-territory world-map-owner",
        @interactive && "world-map-territory--interactive"
      ]}
      role={@interactive && "button"}
      tabindex={@interactive && if(@tab_stop, do: "0", else: "-1")}
      aria-label={@label}
      aria-pressed={@interactive && to_string(@selected or @target)}
      data-area={@area.number}
      data-cx={@cx}
      data-cy={@cy}
      data-owner={@fill.owner}
      data-fog={!@area.visible}
      data-frontier={@fill.dim && "dim"}
      data-element={@element}
      data-interactive={@interactive}
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

  defp army_count(assigns) do
    {x, y} = Geometry.label(assigns.map_name, assigns.area.number)
    assigns = assign(assigns, x: x, y: y)

    # `paint-order`/`stroke-linejoin` are presentation attributes here (they need
    # no theme token) so the outline-under-glyphs contract is visible in the
    # rendered markup; the stroke/fill colours come from `.world-map-count`.
    ~H"""
    <text
      id={"territory-count-#{@area.number}"}
      x={@x}
      y={@y}
      class="world-map-count"
      data-area={@area.number}
      data-armies={@area.armies}
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
  # rendering every area dimmed. So does a seated player whose frontier is
  # empty: eliminated (owns nothing), or the winner owning the whole board.
  @doc false
  def effective_lens(:frontier, _areas, nil), do: :owner

  def effective_lens(:frontier, areas, viewer_number) do
    if Enum.empty?(frontier_info(areas, viewer_number)), do: :owner, else: :frontier
  end

  def effective_lens(lens, _areas, _viewer_number), do: lens

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

  # An owned area with a differently-owned neighbour is a border area; an
  # enemy area is on the frontier when one of its own links reaches a border
  # area. Fog still has to be checked here: `PlayerView.owns_adjacent?/3`
  # reveals the areas the viewer's *own* links reach, but some links are
  # one-way (on the elements map 7->8, 9->23, 31->32, 33->15), so an enemy
  # area can link into the viewer's border while staying fogged, with no
  # owner or army count to draw a frontier delta from.
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
      |> Enum.filter(&(&1.visible and &1.owner_number != viewer_number))
      |> Enum.filter(&Enum.any?(&1.adjacent, fn n -> MapSet.member?(my_borders, n) end))
      |> MapSet.new(& &1.number)

    MapSet.union(my_borders, enemy_borders)
  end

  # The army delta shown next to a frontier tile's count: this area's armies
  # minus the strongest visible, differently-owned neighbour — from either
  # side of the line, a positive delta favours whoever holds the tile it's
  # printed on. No count of its own (fogged), no delta.
  defp frontier_delta(%{armies: armies}, _areas_by_number) when not is_integer(armies), do: nil

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
    {x1, y1} = Geometry.label(assigns.map_name, assigns.area.number)
    {x2, y2} = Geometry.label(assigns.map_name, assigns.area.order.target)
    kind = to_string(assigns.area.order.command)
    target_name = Map.fetch!(assigns.area_names, assigns.area.order.target)

    assigns =
      assign(assigns,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        mx: (x1 + x2) / 2,
        my: (y1 + y2) / 2,
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
      <line x1={@x1} y1={@y1} x2={@x2} y2={@y2} class="world-map-order-hit" />
      <line
        x1={@x1}
        y1={@y1}
        x2={@x2}
        y2={@y2}
        class={"world-map-order-line world-map-order-line--#{@kind}"}
        marker-end={"url(#gc-order-arrowhead-#{@kind})"}
      />
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
    """
  end

  # Fog-hidden areas get no owner slot at all (`data-owner` is omitted) — the fog
  # hatch is styled off `data-fog`, never off a neutral "0" that would be
  # indistinguishable from a genuinely unclaimed territory.
  defp territory_label(%{visible: false} = area, owner_names),
    do: "#{area.name}, #{owner_phrase(area, owner_names)}"

  defp territory_label(area, owner_names),
    do: "#{area.name}, #{owner_phrase(area, owner_names)}, #{armies_text(area.armies)}"

  defp board_label(:original), do: "World map board"
  defp board_label(:elements), do: "Elements map board"

  defp armies_text(1), do: "1 army"
  defp armies_text(n), do: "#{n} armies"
end

defmodule GlobalCombatWeb.GameLive.StatusBar do
  @moduledoc """
  The game page's status strip — everything `GameLive` renders into `GameLayout`'s `:status`
  slot: the turn/lobby line with its status pills, the map-lens switch, the map's Fit button,
  the last-turn replay controls (`GameLive.TurnResults`), the screen-reader game-over
  announcement, and the Players drawer and full-screen buttons. On a phone in stage mode it is
  the game HUD's top strip: the turn pill with its turn hint and army summary, the roster as
  avatars on the drawer button, and Fit, the replay controls and a lens-cycle button folded
  behind one "⋯" menu (`#hud-more`).

  `GameLayout` already marks the `:status` section `aria-live="polite"`, so the announcement
  spans rendered here are what a screen reader hears when a turn resolves or the game ends.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.SegmentedControl
  alias GlobalCombatWeb.Components.Boutique.StatusPill
  alias GlobalCombatWeb.GameLive.Hud
  alias GlobalCombatWeb.GameLive.TurnResults
  alias GlobalCombatWeb.GameLive.WorldMap

  import GlobalCombatWeb.GameLive.ViewHelpers, only: [my_player: 1]

  attr :status, :atom, required: true, doc: "`:lobby` or `:playing`"
  attr :view, :map, required: true
  attr :lens, :atom, required: true

  attr :stage, :boolean,
    default: false,
    doc: "stage mode (a turn in progress): the phone HUD's menu and lens-cycle button show"

  attr :replay_steps, :list,
    default: [],
    doc: "`GameLive.Replay.steps/4` for the last turn; only used while playing"

  attr :headline, :string, default: nil, doc: "the game-over headline, once the game has ended"
  attr :outcome, :string, default: nil, doc: "the viewer's own game-over line, if seated"

  def status_bar(assigns) do
    ~H"""
    <span id="game-status"><.status_line
      status={@status}
      view={@view}
      lens={@lens}
      stage={@stage}
      replay_steps={@replay_steps}
      headline={@headline}
      outcome={@outcome}
    /></span>
    <form
      :if={@status == :playing}
      id="lens-form"
      phx-change="set_lens"
      class={[@stage && "hidden lg:block"]}
    >
      <SegmentedControl.segmented_control name="lens" label="Map lens" value={@lens}>
        <:option value="owner">Owner</:option>
        <:option value="region">Region control</:option>
        <:option value="frontier">Frontier</:option>
      </SegmentedControl.segmented_control>
    </form>
    <div class="ml-auto flex items-center gap-[var(--space-2)]">
      <%!-- Phone only: Fit, the replay controls and the lens sit behind
      this one button (`#hud-more` in status_line/1), so the strip
      stays a single row over the map. --%>
      <button
        :if={@stage}
        type="button"
        id="hud-more-toggle"
        aria-label="Map and replay controls"
        aria-controls="hud-more"
        aria-expanded="false"
        phx-click={
          JS.toggle_class("is-open", to: "#hud-more")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        class="hud-chip lg:hidden"
      >
        <.icon name="hero-ellipsis-horizontal" class="size-5" />
      </button>
      <%!-- The roster as avatars doubles as the drawer opener on a phone:
      each seat's colour, initial and a tick once they've ended their
      turn — who you're waiting on, at a glance. --%>
      <button
        type="button"
        id="drawer-open"
        aria-controls="game-drawer"
        aria-expanded="false"
        aria-label="Players and chat"
        phx-mounted={JS.ignore_attributes(["aria-expanded"])}
        class="hud-chip relative rounded-[var(--radius-sm)] px-[var(--space-3)] py-[var(--space-1)] text-sm font-semibold bg-surface-muted hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring lg:hidden"
      >
        <%= if @status == :playing do %>
          <span class="flex items-center -space-x-1.5" aria-hidden="true">
            <span
              :for={p <- @view.players}
              class={["hud-avatar world-map-owner", p.eliminated && "opacity-40"]}
              data-owner={WorldMap.owner_slot(p.number)}
              data-done={p.done && !p.eliminated}
            >
              {String.first(p.name)}
            </span>
          </span>
        <% else %>
          Players
        <% end %>
        <span
          data-unread-dot
          aria-hidden="true"
          phx-mounted={JS.ignore_attributes(["class"])}
          class="hidden absolute -right-1 -top-1 size-2.5 rounded-full bg-danger"
        />
      </button>
      <button
        id="fullscreen-toggle"
        type="button"
        phx-hook=".Fullscreen"
        aria-pressed="false"
        aria-label="Full screen"
        class="hud-chip hidden shrink-0 items-center justify-center rounded-[var(--radius-sm)] p-[var(--space-2)] border border-border bg-surface hover:bg-surface-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
      >
        <.icon name="hero-arrows-pointing-out" class="fullscreen-toggle-icon size-5" />
      </button>
    </div>
    <.bonus_layer :if={@stage} map_name={@view.map_name} />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Fullscreen">
      // iOS Safari has no Fullscreen API for arbitrary elements
      // (`document.fullscreenEnabled` is false there) — the button stays
      // hidden rather than shown-and-broken; those players get the
      // browser-chrome-free experience through the PWA install instead
      // (manifest.webmanifest, root layout metas).
      export default {
        mounted() {
          if (!document.fullscreenEnabled) return
          this.el.classList.remove("hidden")
          this.el.classList.add("inline-flex")
          this.onClick = () => this.toggle()
          this.onFullscreenChange = () => this.syncPressed()
          this.el.addEventListener("click", this.onClick)
          document.addEventListener("fullscreenchange", this.onFullscreenChange)
        },
        toggle() {
          if (document.fullscreenElement) {
            document.exitFullscreen()
          } else {
            document.getElementById("game-board")?.requestFullscreen({ navigationUI: "hide" })
          }
        },
        syncPressed() {
          const pressed = !!document.fullscreenElement
          this.el.setAttribute("aria-pressed", pressed ? "true" : "false")
          this.el.querySelector(".fullscreen-toggle-icon")?.classList.toggle(
            "hero-arrows-pointing-in",
            pressed
          )
          this.el.querySelector(".fullscreen-toggle-icon")?.classList.toggle(
            "hero-arrows-pointing-out",
            !pressed
          )
        },
        destroyed() {
          this.el.removeEventListener("click", this.onClick)
          document.removeEventListener("fullscreenchange", this.onFullscreenChange)
        }
      }
    </script>
    """
  end

  attr :status, :atom, required: true
  attr :view, :map, required: true
  attr :lens, :atom, required: true
  attr :stage, :boolean, required: true
  attr :replay_steps, :list, required: true
  attr :headline, :string, default: nil
  attr :outcome, :string, default: nil

  defp status_line(%{status: :lobby} = assigns) do
    ~H"""
    <span class="font-semibold">Waiting for players</span>
    <StatusPill.status_pill tone="waiting">
      {length(@view.players)}/{@view.max_players} joined
    </StatusPill.status_pill>
    """
  end

  defp status_line(%{status: :playing} = assigns) do
    me = my_player(assigns.view)

    assigns =
      assign(assigns,
        ended_pill: ended_pill(assigns.view),
        turn_hint: !assigns.view.ended && Hud.turn_hint(assigns.view, me),
        income:
          !assigns.view.ended && Hud.gesture_pool(assigns.view, me) &&
            Hud.income(assigns.view, me)
      )

    ~H"""
    <span class="turn-pill">
      <span class="heading-3 tabular-nums">
        Turn {@view.turn}
      </span>
      <%!-- aria-live="off": this changes on every placement, and the strip
      around it is a live region that would otherwise read each one out. --%>
      <span :if={@turn_hint} id="turn-hint" class="turn-hint" aria-live="off">{@turn_hint}</span>
      <%!-- Your army at a glance: everything you have on the board and in hand,
      and what next turn brings (the breakdown is in the Players drawer). --%>
      <span :if={@income} id="army-summary" class="army-summary" aria-live="off">
        {@income.armies} armies · +{@income.total} next turn
      </span>
    </span>
    <StatusPill.status_pill :if={!@view.ended} tone="active" class="hud-desktop-only">
      In progress
    </StatusPill.status_pill>
    <StatusPill.status_pill :if={@view.ended} tone={@ended_pill.tone}>
      {@ended_pill.label}
    </StatusPill.status_pill>
    <StatusPill.status_pill :if={@view.is_fogged} tone="partial">Fog of war</StatusPill.status_pill>
    <%!-- On a phone this group is the "⋯" menu (#hud-more-toggle); from `lg`
    up it isn't a box at all (`display: contents`) and its controls sit inline
    in the strip as before. --%>
    <span id="hud-more" class="hud-more">
      <Button.button
        type="button"
        intent="neutral"
        id="map-fit"
        phx-hook=".MapFit"
        aria-label="Reset map zoom"
        class="hud-chip"
      >
        <.icon name="hero-globe-americas" class="size-5 lg:hidden" />
        <span class="hud-menu-label hidden lg:inline">Fit</span>
      </Button.button>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".MapFit">
        // The .MapViewport hook (world_map.ex) lives on a different element,
        // so rather than it reaching out with a document-level click listener,
        // this button announces itself over a window event.
        export default {
          mounted() {
            this.el.addEventListener("click", () => window.dispatchEvent(new CustomEvent("gc:map-fit")))
          }
        }
      </script>
      <TurnResults.turn_replay_controls turn={@view.turn} steps={@replay_steps} />
      <button
        :if={@stage}
        type="button"
        id="lens-cycle"
        phx-click="cycle_lens"
        class="hud-chip lg:hidden"
      >
        <.icon name={Hud.lens_icon(@lens)} class="size-5" />
        <span>Lens: {Hud.lens_name(@lens)}</span>
      </button>
    </span>
    <span :if={@view.ended} id="game-over-announce" class="sr-only">
      {@headline}<span :if={@outcome}>{" " <> @outcome}</span>
    </span>
    """
  end

  # Phone HUD only: the region bonus legend as a card in the HUD layer, under
  # the turn pill, instead of the SVG legend drawn into the map's sea — that
  # one pans and zooms with the board, so on a phone it rendered too small to
  # read and slid off screen once zoomed. `app.css` shows this below `lg` (and
  # hides the SVG legend there); from `lg` up the board's own legend stays.
  # Open by default; `ignore_attributes` keeps a player's collapse across
  # patches.
  attr :map_name, :atom, required: true

  defp bonus_layer(assigns) do
    assigns = assign(assigns, :rows, WorldMap.legend(assigns.map_name).rows)

    ~H"""
    <details
      id="hud-bonuses"
      class="hud-bonuses"
      open
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <summary class="hud-bonuses-toggle">
        Region bonuses
        <.icon name="hero-chevron-down" class="hud-bonuses-chevron size-4" />
      </summary>
      <dl class="hud-bonuses-list">
        <div :for={row <- @rows} data-region={row.number}>
          <dt>{row.name}</dt>
          <dd>+{row.bonus}</dd>
        </div>
      </dl>
    </details>
    """
  end

  # The pill used to be tone "done" (green, terminal-success) for every viewer once a
  # game ended, so a losing player's own status strip told them they'd succeeded. It now reflects
  # the *viewer's* outcome, matching `GameOver`'s viewer outcome line — a spectator gets the
  # neutral "Ended", a seated player gets their own Victory/Defeat.
  defp ended_pill(view) do
    case my_player(view) do
      nil -> %{tone: "new", label: "Ended"}
      %{place: 1} -> %{tone: "done", label: "Victory"}
      _ -> %{tone: "blocked", label: "Defeat"}
    end
  end
end

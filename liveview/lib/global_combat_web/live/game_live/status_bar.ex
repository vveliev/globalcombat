defmodule GlobalCombatWeb.GameLive.StatusBar do
  @moduledoc """
  The game page's status strip — everything `GameLive` renders into `GameLayout`'s `:status`
  slot: the turn/lobby line with its status pills, the map-lens switch, the map's Fit button,
  the last-turn replay controls (`GameLive.TurnResults`), the screen-reader game-over
  announcement, and the Players drawer and full-screen buttons.

  `GameLayout` already marks the `:status` section `aria-live="polite"`, so the announcement
  spans rendered here are what a screen reader hears when a turn resolves or the game ends.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.SegmentedControl
  alias GlobalCombatWeb.Components.Boutique.StatusPill
  alias GlobalCombatWeb.GameLive.TurnResults

  import GlobalCombatWeb.GameLive.ViewHelpers, only: [my_player: 1]

  attr :status, :atom, required: true, doc: "`:lobby` or `:playing`"
  attr :view, :map, required: true
  attr :lens, :atom, required: true

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
      replay_steps={@replay_steps}
      headline={@headline}
      outcome={@outcome}
    /></span>
    <form :if={@status == :playing} id="lens-form" phx-change="set_lens">
      <SegmentedControl.segmented_control name="lens" label="Map lens" value={@lens}>
        <:option value="owner">Owner</:option>
        <:option value="region">Region control</:option>
        <:option value="frontier">Frontier</:option>
      </SegmentedControl.segmented_control>
    </form>
    <div class="ml-auto flex items-center gap-[var(--space-2)]">
      <button
        type="button"
        id="drawer-open"
        aria-controls="game-drawer"
        aria-expanded="false"
        phx-mounted={JS.ignore_attributes(["aria-expanded"])}
        class="relative rounded-[var(--radius-sm)] px-[var(--space-3)] py-[var(--space-1)] text-sm font-semibold bg-surface-muted hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring lg:hidden"
      >
        Players
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
        class="hidden shrink-0 items-center justify-center rounded-[var(--radius-sm)] p-[var(--space-2)] border border-border bg-surface hover:bg-surface-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
      >
        <.icon name="hero-arrows-pointing-out" class="fullscreen-toggle-icon size-5" />
      </button>
    </div>
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
    assigns = assign(assigns, :ended_pill, ended_pill(assigns.view))

    ~H"""
    <span class="heading-3 tabular-nums">
      Turn {@view.turn}
    </span>
    <StatusPill.status_pill :if={!@view.ended} tone="active">In progress</StatusPill.status_pill>
    <StatusPill.status_pill :if={@view.ended} tone={@ended_pill.tone}>
      {@ended_pill.label}
    </StatusPill.status_pill>
    <StatusPill.status_pill :if={@view.is_fogged} tone="partial">Fog of war</StatusPill.status_pill>
    <Button.button
      type="button"
      intent="neutral"
      id="map-fit"
      phx-hook=".MapFit"
      aria-label="Reset map zoom"
    >
      Fit
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
    <span :if={@view.ended} id="game-over-announce" class="sr-only">
      {@headline}<span :if={@outcome}>{" " <> @outcome}</span>
    </span>
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

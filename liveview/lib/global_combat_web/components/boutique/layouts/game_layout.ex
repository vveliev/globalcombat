defmodule GlobalCombatWeb.Components.Boutique.Layouts.GameLayout do
  @moduledoc """
  Board region + player panel + live status for turn-based multiplayer —
  LiveView-only, no React counterpart (`layouts/LAYOUTS.md`,
  `DESIGN-CONTRACTS.md`'s pending-ports table: "deliberately LiveView-first").
  Real-time turn/connection state belongs on the server that owns the
  socket, so unlike the other five shells this one was designed directly
  in HEEx rather than ported — same slot/grid-area/token contract as the
  rest of the layer (`design-layouts` skill), no React shape to mirror.

  Named slots: `:status` (turn indicator, connection state — a persistent
  strip above the board), `:board` (required — the game surface), and
  `:players` (roster/scores rail, `--size-rail` wide, same track robo-hub's
  `ConsoleLayout.Queue` uses for a live side panel).

  The `:status` strip is `tabindex="-1"` and marked `data-focus-landmark` —
  it's the one region that survives every board/players patch, so it's the
  designated fallback focus target for consumers restoring keyboard focus
  after a state-changing patch removes whatever was previously focused
  (GIF-82).

  Collapses to a stacked status/board/players column at `lg:` (Tailwind's
  64rem breakpoint matches `--size-collapse`, tokens/scales.json), same
  convention as the ported shells.

  Sizes to its container rather than forcing its own `min-h-screen` (GIF-102):
  `GameLive` nests this inside `SiteChrome.site_chrome`'s already-`min-h-screen`
  content slot, so a second forced viewport-height here would inflate the page
  to roughly double the visible content. A standalone consumer (`DesignSmokeLive`)
  passes `class="min-h-screen"` explicitly to get the old full-viewport look back.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :status
  slot :board, required: true
  slot :players

  def game_layout(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "grid bg-background text-text font-sans",
        "grid-cols-1 grid-rows-[auto_minmax(0,1fr)_auto]",
        "[grid-template-areas:'status'_'board'_'players']",
        "lg:grid-cols-[minmax(0,1fr)_var(--size-rail)] lg:grid-rows-[auto_minmax(0,1fr)]",
        "lg:[grid-template-areas:'status_status'_'board_players']",
        @class
      ]}
      {@rest}
    >
      <section
        :if={@status != []}
        aria-label="Game status"
        aria-live="polite"
        tabindex="-1"
        data-focus-landmark
        class="[grid-area:status] flex items-center gap-[var(--space-4)] px-[var(--space-4)] py-[var(--space-2)] bg-surface border-b border-border text-[length:var(--text-sm)] focus:outline focus:outline-2 focus:outline-offset-2 focus:outline-focus-ring"
      >
        {render_slot(@status)}
      </section>
      <main class="[grid-area:board] min-w-0 min-h-0 p-[var(--space-4)] overflow-auto">
        {render_slot(@board)}
      </main>
      <aside
        :if={@players != []}
        aria-label="Players"
        class="[grid-area:players] bg-surface p-[var(--space-4)] overflow-y-auto border-t border-border lg:border-t-0 lg:border-l"
      >
        {render_slot(@players)}
      </aside>
    </div>
    """
  end
end

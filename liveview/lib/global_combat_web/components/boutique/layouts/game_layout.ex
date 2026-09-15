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

  `:players` renders once, inside a native `<dialog id="game-drawer">`
  (`docs/mobile-battle-mode.md` §4.5) — chat and the roster carry DOM ids a
  second copy would collide with, so there is exactly one render of this
  slot regardless of breakpoint. The colocated `.Drawer` hook (below) opens
  it as a right-hand slide-in sheet below `lg:` (triggered by a consumer
  button elsewhere in the tree with `aria-controls="game-drawer"`) and keeps
  it permanently shown as today's static rail at `lg:` and up — see the CSS
  rules for `.game-drawer` in `assets/css/app.css`.

  The `:status` strip is `tabindex="-1"` and marked `data-focus-landmark` —
  it's the one region that survives every board/players patch, so it's the
  designated fallback focus target for consumers restoring keyboard focus
  after a state-changing patch removes whatever was previously focused
  (GIF-82).

  Collapses to a stacked status/board/players column at `lg:` (Tailwind's
  64rem breakpoint matches `--size-collapse`, tokens/scales.json), same
  convention as the ported shells.

  `players_first` flips that stacked order to status/players/board
  below `lg:` only — once a game has ended, the outcome and final standings
  in the players rail matter more than a board a phone/tablet viewport clips
  to a fraction of the map. The side-by-side `lg:` arrangement is unaffected.

  Sizes to its container rather than forcing its own `min-h-screen` (GIF-102):
  `GameLive` nests this inside `SiteChrome.site_chrome`'s already-`min-h-screen`
  content slot, so a second forced viewport-height here would inflate the page
  to roughly double the visible content. A standalone consumer (`DesignSmokeLive`)
  passes `class="min-h-screen"` explicitly to get the old full-viewport look back.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :players_first, :boolean, default: false
  attr :rest, :global

  slot :status
  slot :board, required: true
  slot :players

  def game_layout(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "grid bg-background text-text body-text",
        "grid-cols-1 grid-rows-[auto_minmax(0,1fr)_auto]",
        if(@players_first,
          do: "[grid-template-areas:'status'_'players'_'board']",
          else: "[grid-template-areas:'status'_'board'_'players']"
        ),
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
        class="[grid-area:status] flex flex-wrap items-center gap-[var(--space-4)] px-[var(--space-4)] py-[var(--space-2)] bg-surface border-b border-border text-[length:var(--text-sm)] focus:outline focus:outline-2 focus:outline-offset-2 focus:outline-focus-ring"
      >
        {render_slot(@status)}
      </section>
      <main class="[grid-area:board] min-w-0 min-h-0 p-[var(--space-4)] overflow-auto">
        {render_slot(@board)}
      </main>
      <dialog
        :if={@players != []}
        id="game-drawer"
        aria-label="Players and chat"
        phx-hook=".Drawer"
        class="game-drawer [grid-area:players] bg-surface p-[var(--space-4)] overflow-y-auto border-t border-border lg:border-t-0 lg:border-l"
      >
        <div class="mb-[var(--space-3)] flex justify-end lg:hidden">
          <button
            type="button"
            data-drawer-close
            class="rounded-[var(--radius-sm)] px-[var(--space-3)] py-[var(--space-1)] text-sm font-semibold bg-surface-muted hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
          >
            Close
          </button>
        </div>
        {render_slot(@players)}
      </dialog>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Drawer">
        // Native <dialog> drawer for the :players slot (docs/mobile-battle-mode.md
        // §4.5). Below lg: closed by default, opened as a modal sheet by a
        // consumer-rendered button elsewhere in the tree (found via
        // aria-controls="game-drawer", so this hook never needs to know where
        // that button lives). Above lg: always shown as a plain static column —
        // CSS forces `display:block` there regardless of the `open` attribute,
        // so the rail renders even before this hook mounts.
        //
        // Every LiveView patch walks the whole page, and neither `open` nor the
        // opener's `aria-expanded` are ever part of the server-rendered HTML —
        // so a patch strips them back to their absent/false defaults on every
        // single re-render while the drawer is open, exactly like `.MapViewport`
        // resetting `viewBox` (world_map.ex's moduledoc). `updated()` restores
        // the bare attribute directly rather than re-calling showModal()/show(),
        // which would steal focus from whatever's focused inside the drawer
        // (e.g. mid-keystroke in the chat input) on every unrelated broadcast.
        export default {
          mounted() {
            this.mq = window.matchMedia("(min-width: 64rem)")
            this.opener = document.querySelector(`[aria-controls="${this.el.id}"]`)
            this.wantOpen = false
            this.chatCount = this.chatMessageCount()

            this.onModeChange = () => this.applyMode()
            this.mq.addEventListener("change", this.onModeChange)

            this.el.addEventListener("close", () => this.onNativeClose())
            this.el.addEventListener("click", (e) => {
              if (e.target === this.el || e.target.closest("[data-drawer-close]")) {
                this.el.close()
              }
            })
            this.opener?.addEventListener("click", () => this.openDrawer())

            this.applyMode()
          },

          destroyed() {
            this.mq.removeEventListener("change", this.onModeChange)
          },

          chatMessageCount() {
            // Not children.length: the empty state ("No messages yet.") is a
            // sibling <li> with no data-message, and would otherwise mask the
            // very first real message ever arriving (1 placeholder -> 1
            // message is not an increase).
            return this.el.querySelectorAll("#chat-messages li[data-message]").length
          },

          // Real open/close calls: only for a genuine user action or an actual
          // lg: breakpoint crossing, both rare enough that resetting focus is
          // correct (or, for the breakpoint crossing, irrelevant — the opener
          // is lg:hidden either way).
          applyMode() {
            const desktop = this.mq.matches
            if (this.el.open) this.el.close()

            if (desktop) {
              this.el.show()
            } else if (this.wantOpen) {
              try { this.el.showModal() } catch (e) {}
            }
          },

          openDrawer() {
            if (this.mq.matches || this.el.open) return
            this.wantOpen = true
            try { this.el.showModal() } catch (e) { this.el.show() }
            this.syncExpanded(true)
            this.hideUnread()
            this.chatCount = this.chatMessageCount()
          },

          onNativeClose() {
            // Escape, a backdrop click and the Close button all end here —
            // close() fires "close" once the dialog has actually closed.
            this.wantOpen = false
            this.syncExpanded(false)
            this.opener?.focus()
          },

          syncExpanded(expanded) {
            this.opener?.setAttribute("aria-expanded", expanded ? "true" : "false")
          },

          hideUnread() {
            this.opener?.querySelector("[data-unread-dot]")?.classList.add("hidden")
          },

          showUnread() {
            this.opener?.querySelector("[data-unread-dot]")?.classList.remove("hidden")
          },

          updated() {
            const shouldBeOpen = this.mq.matches || this.wantOpen

            if (shouldBeOpen !== this.el.hasAttribute("open")) {
              if (shouldBeOpen) this.el.setAttribute("open", "")
              else this.el.removeAttribute("open")
            }

            if (!this.mq.matches) this.syncExpanded(this.wantOpen)

            const count = this.chatMessageCount()
            if (count > this.chatCount && !this.mq.matches && !this.wantOpen) {
              this.showUnread()
            }
            this.chatCount = count
          }
        }
      </script>
    </div>
    """
  end
end

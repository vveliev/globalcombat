defmodule GlobalCombatWeb.Components.Boutique.Layouts.AdminLayout do
  @moduledoc """
  Left sidebar + top bar + scrollable content — LiveView mirror of
  `layouts/react/AdminLayout`. Named slots (`:sidebar`/`:topbar`/`:content`)
  replace the React compound-component API; grid-area placement keeps slot
  order at the call site irrelevant.

  Collapses to a stacked topbar/sidebar/content column at `lg:` (Tailwind's
  64rem breakpoint matches `--size-collapse`, tokens/scales.json) — a CSS
  media query stands in for the React version's `useCollapsed()` hook.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :sidebar
  slot :topbar
  slot :content, required: true

  def admin_layout(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "grid min-h-screen bg-background text-text font-sans",
        "grid-cols-1 grid-rows-[var(--size-topbar)_auto_minmax(0,1fr)]",
        "[grid-template-areas:'topbar'_'sidebar'_'content']",
        "lg:grid-cols-[var(--size-sidebar)_minmax(0,1fr)] lg:grid-rows-[var(--size-topbar)_minmax(0,1fr)]",
        "lg:[grid-template-areas:'sidebar_topbar'_'sidebar_content']",
        @class
      ]}
      {@rest}
    >
      <nav
        :if={@sidebar != []}
        aria-label="Sidebar"
        class={[
          "[grid-area:sidebar] bg-surface p-[var(--space-4)] overflow-y-auto",
          "border-b border-border lg:border-b-0 lg:border-r"
        ]}
      >
        {render_slot(@sidebar)}
      </nav>
      <header
        :if={@topbar != []}
        class="[grid-area:topbar] flex items-center gap-[var(--space-4)] px-[var(--space-6)] bg-surface border-b border-border"
      >
        {render_slot(@topbar)}
      </header>
      <main class="[grid-area:content] min-w-0 p-[var(--space-6)] overflow-y-auto">
        {render_slot(@content)}
      </main>
    </div>
    """
  end
end

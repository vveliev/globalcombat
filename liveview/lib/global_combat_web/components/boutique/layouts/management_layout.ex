defmodule GlobalCombatWeb.Components.Boutique.Layouts.ManagementLayout do
  @moduledoc """
  Dense ops surface: filter bar, primary data pane, optional inspector pane
  — LiveView mirror of `layouts/react/ManagementLayout`. Named slots
  (`:filter_bar`/`:primary`/`:inspector`) replace the React compound
  component API; omitting `:inspector` collapses its column to nothing,
  same as the React version's `auto` track. Padding and type run one step
  tighter than the other shells — this is the data-heavy view.

  Collapses to a stacked filter/primary/inspector column at `lg:`
  (Tailwind's 64rem breakpoint matches `--size-collapse`,
  tokens/scales.json) — a CSS media query stands in for the React
  version's `useCollapsed()` hook.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :filter_bar
  slot :primary, required: true
  slot :inspector

  def management_layout(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "grid min-h-screen bg-background text-text font-sans text-[length:var(--text-sm)]",
        "grid-cols-1 grid-rows-[auto_minmax(0,1fr)_auto]",
        "[grid-template-areas:'filter'_'primary'_'inspector']",
        "lg:grid-cols-[minmax(0,1fr)_auto] lg:grid-rows-[auto_minmax(0,1fr)]",
        "lg:[grid-template-areas:'filter_filter'_'primary_inspector']",
        @class
      ]}
      {@rest}
    >
      <header
        :if={@filter_bar != []}
        class="[grid-area:filter] flex items-center flex-wrap gap-[var(--space-2)] px-[var(--space-4)] py-[var(--space-2)] bg-surface border-b border-border"
      >
        {render_slot(@filter_bar)}
      </header>
      <main class="[grid-area:primary] min-w-0 p-[var(--space-4)] overflow-auto">
        {render_slot(@primary)}
      </main>
      <aside
        :if={@inspector != []}
        aria-label="Inspector"
        class={[
          "[grid-area:inspector] bg-surface p-[var(--space-4)] overflow-y-auto",
          "border-t border-border lg:border-t-0 lg:border-l lg:w-[var(--size-inspector)]"
        ]}
      >
        {render_slot(@inspector)}
      </aside>
    </div>
    """
  end
end

defmodule GlobalCombatWeb.Components.Boutique.Layouts.ConsoleLayout do
  @moduledoc """
  Fixed-viewport operations cockpit, extracted from robo-hub's
  control-board archetype — LiveView mirror of
  `layouts/react/ConsoleLayout`. Named slots (`:banner`/`:queue`/`:stage`/
  `:focus`/`:strip`) replace the React compound-component API; omitting a
  rail collapses its track to nothing (rails size themselves via `auto`
  tracks). Density matches `ManagementLayout`: this is the live-operations
  surface.

  At `lg:` (Tailwind's 64rem breakpoint matches `--size-collapse`,
  tokens/scales.json) the cockpit becomes a single scrolling column —
  stage first, then focus, queue, strip, mirroring robo-hub's own
  stacking order. The no-page-scroll rule (fixed 100vh, every region
  scrolls itself) holds only at `lg:` and above.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :banner
  slot :queue
  slot :stage, required: true
  slot :focus
  slot :strip

  def console_layout(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "grid min-h-screen lg:h-screen bg-background text-text font-sans text-[length:var(--text-sm)]",
        "grid-cols-1 grid-rows-[auto_auto_auto_auto_auto]",
        "[grid-template-areas:'banner'_'stage'_'focus'_'queue'_'strip']",
        "lg:grid-cols-[auto_minmax(0,1fr)_auto] lg:grid-rows-[auto_minmax(0,1fr)_auto]",
        "lg:[grid-template-areas:'banner_banner_banner'_'queue_stage_focus'_'strip_strip_strip']",
        @class
      ]}
      {@rest}
    >
      <section
        :if={@banner != []}
        aria-label="Session banner"
        class="[grid-area:banner] px-[var(--space-2)] pt-[var(--space-2)]"
      >
        {render_slot(@banner)}
      </section>
      <aside
        :if={@queue != []}
        aria-label="Work queue"
        class="[grid-area:queue] lg:w-[var(--size-rail)] min-h-0 flex flex-col gap-[var(--space-2)] p-[var(--space-2)] overflow-y-auto"
      >
        {render_slot(@queue)}
      </aside>
      <main class="[grid-area:stage] min-w-0 min-h-0 p-[var(--space-2)] overflow-auto">
        {render_slot(@stage)}
      </main>
      <aside
        :if={@focus != []}
        aria-label="Focus panel"
        class="[grid-area:focus] lg:w-[var(--size-rail-lg)] min-h-0 flex flex-col gap-[var(--space-2)] p-[var(--space-2)] overflow-y-auto"
      >
        {render_slot(@focus)}
      </aside>
      <section
        :if={@strip != []}
        aria-label="Media strip"
        class="[grid-area:strip] h-[var(--size-filmstrip)] flex gap-[var(--space-2)] px-[var(--space-2)] pb-[var(--space-2)] overflow-x-auto"
      >
        {render_slot(@strip)}
      </section>
    </div>
    """
  end
end

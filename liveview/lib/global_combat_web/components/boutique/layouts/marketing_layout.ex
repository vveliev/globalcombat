defmodule GlobalCombatWeb.Components.Boutique.Layouts.MarketingLayout do
  @moduledoc """
  Landing-page flow: sticky nav, full-bleed hero, repeatable centered
  sections (optionally muted for banding), footer — LiveView mirror of
  `layouts/react/MarketingLayout`. `:section` is a repeatable slot with a
  `muted` attr, the HEEx equivalent of React's `<MarketingLayout.Section
  muted>` instances. Every region is a full-width wrapper around a
  centered `--size-page` inner column so background bands stretch edge to
  edge — no grid-area placement here, this shell is a single flowing
  column (flex, not grid).

  Marketing is a single column already, so unlike the other shells it has
  no `lg:` collapse point — only the nav row wraps at phone widths.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :nav
  slot :hero

  slot :section do
    attr :muted, :boolean, doc: "Muted background band to alternate section rhythm."
  end

  slot :footer

  def marketing_layout(assigns) do
    ~H"""
    <div
      id={@id}
      class={["min-h-screen flex flex-col bg-background text-text font-sans", @class]}
      {@rest}
    >
      <header
        :if={@nav != []}
        class="sticky top-0 z-[var(--z-sticky)] bg-surface border-b border-border"
      >
        <div class="max-w-[var(--size-page)] mx-auto flex items-center flex-wrap gap-[var(--space-4)] px-[var(--space-6)] py-[var(--space-3)]">
          {render_slot(@nav)}
        </div>
      </header>
      <section :if={@hero != []} class="bg-surface-muted border-b border-border">
        <div class="max-w-[var(--size-page)] mx-auto px-[var(--space-6)] py-[calc(var(--space-12)*2)]">
          {render_slot(@hero)}
        </div>
      </section>
      <section
        :for={section <- @section}
        class={[Map.get(section, :muted, false) && "bg-surface-muted"]}
      >
        <div class="max-w-[var(--size-page)] mx-auto px-[var(--space-6)] py-[var(--space-12)]">
          {render_slot(section)}
        </div>
      </section>
      <footer
        :if={@footer != []}
        class="mt-auto bg-surface border-t border-border text-text-muted text-[length:var(--text-sm)]"
      >
        <div class="max-w-[var(--size-page)] mx-auto px-[var(--space-6)] py-[var(--space-8)]">
          {render_slot(@footer)}
        </div>
      </footer>
    </div>
    """
  end
end

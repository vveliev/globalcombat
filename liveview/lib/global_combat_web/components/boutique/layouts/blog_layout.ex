defmodule GlobalCombatWeb.Components.Boutique.Layouts.BlogLayout do
  @moduledoc """
  Centered reading column with an optional table-of-contents rail —
  LiveView mirror of `layouts/react/BlogLayout`. Named slots replace the
  React compound-component API (`BlogLayout.Header`/`.Toc`/`.Content`/
  `.Footer`); grid-area placement means slot order at the call site never
  matters, same guarantee the React version gets from CSS.

  Collapses to a single column at `lg:` (Tailwind's 64rem breakpoint is the
  same value as `--size-collapse`, tokens/scales.json) — a plain CSS media
  query stands in for the React version's `useCollapsed()` JS hook, which
  exists only because inline styles can't carry `@media`.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :header
  slot :toc
  slot :content, required: true
  slot :footer

  def blog_layout(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "grid min-h-screen bg-background text-text font-sans",
        "grid-cols-1 grid-rows-[auto_auto_1fr_auto]",
        "[grid-template-areas:'header'_'toc'_'content'_'footer']",
        "lg:grid-cols-[1fr_min(var(--size-content),100%)_minmax(0,1fr)] lg:grid-rows-[auto_1fr_auto]",
        "lg:[grid-template-areas:'header_header_header'_'._content_toc'_'footer_footer_footer']",
        @class
      ]}
      {@rest}
    >
      <header
        :if={@header != []}
        class="[grid-area:header] px-[var(--space-6)] py-[var(--space-4)] bg-surface border-b border-border"
      >
        {render_slot(@header)}
      </header>
      <nav
        :if={@toc != []}
        aria-label="Table of contents"
        class={[
          "[grid-area:toc] text-text-muted text-[length:var(--text-sm)]",
          "px-[var(--space-4)] pt-[var(--space-4)]",
          "lg:px-[var(--space-6)] lg:py-[var(--space-8)] lg:pt-[var(--space-8)]",
          "lg:sticky lg:top-[var(--space-6)] lg:self-start lg:max-w-[var(--size-inspector)]"
        ]}
      >
        {render_slot(@toc)}
      </nav>
      <main class="[grid-area:content] min-w-0 px-[var(--space-4)] py-[var(--space-8)] leading-[var(--leading-relaxed)]">
        {render_slot(@content)}
      </main>
      <footer
        :if={@footer != []}
        class="[grid-area:footer] px-[var(--space-6)] py-[var(--space-6)] border-t border-border text-text-muted text-[length:var(--text-sm)] text-center"
      >
        {render_slot(@footer)}
      </footer>
    </div>
    """
  end
end

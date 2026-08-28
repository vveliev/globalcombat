defmodule GlobalCombatWeb.Components.Boutique.PullQuote do
  @moduledoc """
  Display quote — LiveView mirror of `components/react/PullQuote`
  (claude-design landing grammar, pure tokens): a hanging opening
  quotation mark and a hung em-dash attribution. The hang advances are
  font-measured per brand and arrive through the theme
  (`--quote-hang` / `--attribution-hang`, from `tokens/brands.json`); on
  the original brands both are `0em` and the quote sets flush. Keep the
  leading “ in the quote text and the leading "— " in the attribution —
  the negative text-indents are what hang them. A `text-indent` hang
  can't be expressed cleanly as a Tailwind utility here (the value is a
  brand-supplied custom property, not a scale step), so it stays an
  inline `style` referencing the var, same as React's inline `textIndent`.
  """
  use Phoenix.Component

  attr :attribution, :any, default: nil, doc: ~s(Who said it — rendered as a hung "— name" line.)
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def pull_quote(assigns) do
    ~H"""
    <figure class={["m-0", @class]} {@rest}>
      <blockquote
        class="m-0 max-w-[32ch] font-heading font-[var(--font-heading-weight)] text-[length:var(--heading-3)] leading-[1.4] tracking-[var(--heading-tracking)] text-text"
        style="text-indent: var(--quote-hang)"
      >
        {render_slot(@inner_block)}
      </blockquote>
      <figcaption
        :if={@attribution}
        class="mt-[var(--space-6)] text-[length:var(--text-sm)] leading-[var(--font-body-leading)] text-text-muted"
        style="text-indent: var(--attribution-hang)"
      >
        {@attribution}
      </figcaption>
    </figure>
    """
  end
end

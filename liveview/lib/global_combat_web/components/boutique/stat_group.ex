defmodule GlobalCombatWeb.Components.Boutique.StatGroup do
  @moduledoc """
  LiveView mirror of `components/react/StatGroup` (claude-design landing
  stat grammar, pure tokens): display figures with uppercase muted labels,
  spread across the measure. Figures set tabular and take the brand
  heading face at the `--heading-1` size, so the scale follows the theme.
  Draws no band ground — whether stats sit on the page or lift to a
  saturated full-bleed band is the page's call, per BRAND-GUIDES.

  React's compound `StatGroup.Stat` becomes two public function
  components here: `stat_group/1` (the `<dl>` wrapper) and
  `stat_group_stat/1` (one `<dt>`/`<dd>` pair). DOM keeps the valid
  dt→dd order; `flex-col-reverse` puts the figure on top visually.
  """
  use Phoenix.Component

  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def stat_group(assigns) do
    ~H"""
    <dl
      class={[
        "m-0 flex flex-wrap justify-between gap-[var(--space-8)_var(--space-6)]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </dl>
    """
  end

  attr :value, :any, required: true, doc: ~s(The figure, e.g. "42ms", "9", "3 a.m.".)
  attr :label, :any, required: true, doc: "The uppercase label under it."

  attr :emphasis, :string,
    values: ~w(text primary),
    default: "text",
    doc: "Ink for the figure: page text (default) or the brand primary."

  attr :class, :any, default: nil
  attr :rest, :global

  def stat_group_stat(assigns) do
    ~H"""
    <div class={["flex flex-col-reverse gap-[var(--space-2)]", @class]} {@rest}>
      <dt class="text-[length:var(--text-xs)] tracking-[0.06em] uppercase text-text-muted">
        {@label}
      </dt>
      <dd class={[
        "m-0 font-heading text-[length:var(--heading-1)] tabular-nums",
        "leading-[var(--heading-leading)] tracking-[var(--heading-tracking)]",
        "font-[var(--font-heading-weight)]",
        if(@emphasis == "primary", do: "text-primary", else: "text-text")
      ]}>
        {@value}
      </dd>
    </div>
    """
  end
end

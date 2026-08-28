defmodule GlobalCombatWeb.Components.Boutique.Kicker do
  @moduledoc """
  LiveView mirror of `components/react/Kicker` (claude-design landing
  grammar, pure tokens): an uppercase tabular-figure micro-label in the
  primary ink, led by a short solid dash (a mark, not a rule — marks stay
  solid, rules fade; see `FadingRule`). Wayfinding only, never a hero
  eyebrow.
  """
  use Phoenix.Component

  attr :dash, :boolean, default: true
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def kicker(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-[var(--space-3)] text-[length:var(--text-xs)]",
        "leading-[var(--leading-tight)] tracking-[0.06em] uppercase text-primary tabular-nums",
        @class
      ]}
      {@rest}
    >
      <span :if={@dash} aria-hidden="true" class="inline-block h-px w-[2.75rem] shrink-0 bg-current" />
      {render_slot(@inner_block)}
    </span>
    """
  end
end

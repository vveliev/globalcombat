defmodule GlobalCombatWeb.Components.Boutique.FadingRule do
  @moduledoc """
  LiveView mirror of `components/react/FadingRule` (claude-design rule
  treatment, pure tokens): a 1px `--color-divider` separator whose ends
  fade to transparent over 3rem a side instead of stopping cleanly. Full-
  width separators fade; short accent marks (`Kicker`'s dash) stay solid —
  they are marks, not rules.

  The fade is a `linear-gradient` mask on `background`, ported literally
  from the React inline style since Tailwind's utility scale has no
  equivalent for a token-driven gradient stop — hence the inline `style`
  here rather than arbitrary-value classes.
  """
  use Phoenix.Component

  attr :class, :any, default: nil
  attr :rest, :global

  def fading_rule(assigns) do
    ~H"""
    <hr
      role="separator"
      class={["m-0 h-px border-0", @class]}
      style="background: linear-gradient(to right, transparent, var(--color-divider) 3rem calc(100% - 3rem), transparent);"
      {@rest}
    />
    """
  end
end

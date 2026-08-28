defmodule GlobalCombatWeb.Components.Boutique.Badge do
  @moduledoc """
  LiveView mirror of `components/react/Badge`. `intent` resolves through
  the theme's status hues; `dot` swaps the light fill for a small colored
  dot plus neutral text (hue is reinforcement, never the only signal —
  robo-hub convention).
  """
  use Phoenix.Component

  attr :intent, :string, values: ~w(neutral info success warning danger), default: "neutral"
  attr :dot, :boolean, default: false
  attr :class, :any, default: nil

  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-[var(--space-1)] rounded-[var(--radius-sm)]",
      "px-[var(--space-2)] py-[var(--space-1)] text-xs font-medium",
      if(@dot, do: "bg-transparent text-text", else: intent_fill(@intent)),
      @class
    ]}>
      <span
        :if={@dot}
        aria-hidden="true"
        class={["inline-block size-2 rounded-full", intent_dot(@intent)]}
      />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp intent_fill("neutral"), do: "bg-surface-muted text-text"
  defp intent_fill("info"), do: "bg-info/15 text-info"
  defp intent_fill("success"), do: "bg-success/15 text-success"
  defp intent_fill("warning"), do: "bg-warning/15 text-warning"
  defp intent_fill("danger"), do: "bg-danger/15 text-danger"

  defp intent_dot("neutral"), do: "bg-text-muted"
  defp intent_dot("info"), do: "bg-info"
  defp intent_dot("success"), do: "bg-success"
  defp intent_dot("warning"), do: "bg-warning"
  defp intent_dot("danger"), do: "bg-danger"
end

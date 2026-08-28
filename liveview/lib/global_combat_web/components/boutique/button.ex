defmodule GlobalCombatWeb.Components.Boutique.Button do
  @moduledoc """
  Semantic-intent button — LiveView mirror of `components/react/Button`.
  Primary fills from `--color-primary`/`--color-primary-contrast` (recolors
  on a `data-theme` swap, no markup change — C6). Danger stays Tailwind's
  stock red/white, matching the React Button's documented exception: no
  `--color-danger-contrast` token exists yet, so a semantic danger fill
  can't guarantee contrast (see CLAUDE.md provenance notes).
  """
  use Phoenix.Component

  attr :type, :string, values: ~w(button submit reset), default: "button"
  attr :intent, :string, values: ~w(primary neutral danger), default: "primary"
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      class={[
        "inline-flex items-center justify-center gap-[var(--space-2)]",
        "rounded-[var(--radius-sm)] px-[var(--space-4)] py-[var(--space-2)]",
        "text-sm font-semibold transition-opacity cursor-pointer",
        "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        intent_class(@intent),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp intent_class("primary"), do: "bg-primary text-primary-contrast hover:opacity-90"

  defp intent_class("neutral"),
    do: "bg-surface text-text border border-border hover:bg-surface-muted"

  defp intent_class("danger"), do: "bg-red-600 text-white hover:bg-red-700"
end

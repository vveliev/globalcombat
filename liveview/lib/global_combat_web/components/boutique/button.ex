defmodule GlobalCombatWeb.Components.Boutique.Button do
  @moduledoc """
  Semantic-intent button — LiveView mirror of `components/react/Button`.
  Primary fills from `--color-primary`/`--color-primary-contrast` (recolors
  on a `data-theme` swap, no markup change — C6). Danger stays Tailwind's
  stock red/white, matching the React Button's documented exception: no
  `--color-danger-contrast` token exists yet, so a semantic danger fill
  can't guarantee contrast (see CLAUDE.md provenance notes).

  Renders an `<a>` instead of a `<button>` when given `href`/`navigate`/`patch`
  (identical styling either way) — a "Play again"-style next action is a real
  navigation, not a click handler standing in for one, so it should keep the
  native anchor behavior (open in a new tab, show the destination on hover) a
  `<button>` can't offer. `disabled` has no native meaning on an `<a>` (it
  would still navigate on click), so combining it with `href`/`navigate`/
  `patch` raises rather than silently rendering a link that looks disabled
  but isn't.
  """
  use Phoenix.Component

  attr :type, :string, values: ~w(button submit reset), default: "button"
  attr :intent, :string, values: ~w(primary neutral danger), default: "primary"
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(form name value href navigate patch method download)

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    navigable? = !!(rest[:href] || rest[:navigate] || rest[:patch])

    if navigable? and assigns.disabled do
      raise ArgumentError,
            "Button.button/1: `disabled` cannot be combined with href/navigate/patch — a disabled <a> still navigates on click"
    end

    assigns = assign(assigns, :navigable?, navigable?)

    ~H"""
    <.link :if={@navigable?} class={[button_class(@intent), @class]} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    <button
      :if={!@navigable?}
      type={@type}
      disabled={@disabled}
      class={[button_class(@intent), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_class(intent) do
    [
      "inline-flex items-center justify-center gap-[var(--space-2)]",
      "rounded-[var(--radius-sm)] px-[var(--space-4)] py-[var(--space-2)]",
      "text-sm font-semibold transition-opacity cursor-pointer",
      "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring",
      "disabled:opacity-50 disabled:cursor-not-allowed",
      intent_class(intent)
    ]
  end

  defp intent_class("primary"), do: "bg-primary text-primary-contrast hover:opacity-90"

  defp intent_class("neutral"),
    do: "bg-surface text-text border border-border hover:bg-surface-muted"

  defp intent_class("danger"), do: "bg-red-600 text-white hover:bg-red-700"
end

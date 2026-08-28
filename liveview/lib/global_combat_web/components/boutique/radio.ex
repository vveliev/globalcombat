defmodule GlobalCombatWeb.Components.Boutique.Radio do
  @moduledoc """
  Single-choice input — LiveView mirror of `components/react/Radio`, ported
  from the claude-design systems' `.radio` control
  (`data/*/components/forms.html`). Wraps the native `<input type="radio">`
  (label association and radiogroup semantics inherited for free); the
  checked dot and focus ring take the theme's primary via `accent-color`,
  so brand character arrives through the theme, never through props.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :name, :any, required: true
  attr :value, :any, required: true
  attr :checked, :boolean, default: false
  attr :label, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled required form)

  def radio(assigns) do
    ~H"""
    <label class={["inline-flex items-center gap-[var(--space-2)] text-sm text-text", @class]}>
      <input
        type="radio"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        class="size-4 accent-[var(--color-primary)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
        {@rest}
      />
      {@label}
    </label>
    """
  end

  attr :label, :string, default: nil
  slot :inner_block, required: true

  def group(assigns) do
    ~H"""
    <fieldset class="flex flex-col gap-[var(--space-2)]">
      <legend :if={@label} class="text-sm font-medium text-text mb-[var(--space-1)]">
        {@label}
      </legend>
      {render_slot(@inner_block)}
    </fieldset>
    """
  end
end

defmodule GlobalCombatWeb.Components.Boutique.Input do
  @moduledoc """
  Thin restyle of `GlobalCombatWeb.CoreComponents.input/1` onto semantic
  tokens — LiveView mirror of `components/react/Input` (itself a bare
  Mantine `TextInput` pass-through; "contract point for future defaults").
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :label, :string, default: nil
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(autocomplete disabled form max maxlength min minlength pattern placeholder readonly required step)

  def input(assigns) do
    ~H"""
    <GlobalCombatWeb.CoreComponents.input
      id={@id}
      name={@name}
      label={@label}
      value={@value}
      type={@type}
      field={@field}
      errors={@errors}
      class={[
        "w-full rounded-[var(--radius-sm)] border border-border bg-surface text-text",
        "px-[var(--space-3)] py-[var(--space-2)] text-sm placeholder:text-text-muted",
        "focus:outline focus:outline-2 focus:outline-offset-2 focus:outline-focus-ring",
        @class
      ]}
      error_class="border-danger"
      {@rest}
    />
    """
  end
end

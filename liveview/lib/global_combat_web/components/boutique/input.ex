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
    # With a `field`, only forward the id/name/value that were actually given: passing them as
    # `nil` stops CoreComponents.input/1 filling them in from the field (its `assign_new`),
    # which left field-driven inputs with no `name`, so the browser dropped them from the
    # submit. Without a field, CoreComponents needs all three keys, nil or not.
    given = Map.take(assigns, [:id, :name, :value])
    given = if assigns.field, do: Map.reject(given, fn {_k, v} -> is_nil(v) end), else: given
    assigns = assign(assigns, :given, given)

    ~H"""
    <GlobalCombatWeb.CoreComponents.input
      {@given}
      label={@label}
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

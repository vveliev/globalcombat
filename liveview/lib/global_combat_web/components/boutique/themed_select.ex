defmodule GlobalCombatWeb.Components.Boutique.ThemedSelect do
  @moduledoc """
  Single-select dropdown on semantic tokens — LiveView mirror of
  `components/react/ThemedSelect` (a wrapped Mantine `Select` with a
  compound `<ThemedSelect.Option>`, a Downshift-style `stateReducer` escape
  hatch, and a `useThemedSelect()` context hook for reading open/value
  state from sibling children).

  Built on the generated Mishka Chelekom primitive
  `GlobalCombatWeb.Components.NativeSelect` (accessible native `<select>`)
  rather than a JS-driven combobox — there is no client-hydrated listbox on
  this side, so this stays a server-rendered `<select>` inside the normal
  `phx-change`/`phx-submit` cycle. The primitive's own `color`/`variant`
  output is dead weight here (this repo never imports Mishka's vendor CSS
  and forbids literal color in component sources — C1), so it's invoked
  with `variant="native"`, `border="none"`, `rounded="none"`, `ring={false}`
  to strip its built-in classes, and restyled through `select_class` with
  our own semantic Tailwind utilities. Field errors are rendered here
  directly (`text-danger`/`border-danger`) rather than through the
  primitive's own `<.error>`, which hardcodes a non-token `rose-700`.

  ### C5 deviation — `stateReducer` / `useThemedSelect()` omitted

  React's `stateReducer` lets a consumer intercept and veto any client-side
  state transition (open, close, pending selection) before Mantine's
  `Select` commits it, and `useThemedSelect()` lets sibling components read
  that in-flight state. Both exist to manage *client-side* state that this
  component owns between renders — a HEEx `<select>` has no such state:
  there is no "proposed transition" happening on the server to intercept,
  because nothing is proposed until the browser fires a change event and
  Phoenix hands the LiveView the already-committed value. Any veto or
  derived-state logic here belongs in the LiveView's `handle_event`, not in
  a component-local reducer standing in front of a plain `<select>` with
  nothing on the other end to intercept. Faking the callback shape would
  add an indirection layer that can never fire the way its React
  counterpart does, so it's left out — a named, reasoned gap per C5, not a
  silent one. Everything else in the React inventory (label, options,
  controlled value, disabled option, form errors) has a direct attr/slot
  equivalent below.
  """
  use Phoenix.Component

  alias GlobalCombatWeb.Components.NativeSelect
  alias GlobalCombatWeb.CoreComponents

  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :label, :string, default: nil
  attr :value, :any, default: nil
  attr :prompt, :string, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :class, :any, default: nil

  attr :rest, :global, include: ~w(disabled form required autofocus tabindex)

  slot :option, required: false do
    attr :value, :string, required: true
    attr :disabled, :boolean, required: false
  end

  def themed_select(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &CoreComponents.translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> themed_select()
  end

  def themed_select(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <NativeSelect.native_select
        id={@id}
        name={@name}
        label={@label}
        variant="native"
        border="none"
        rounded="none"
        ring={false}
        errors={[]}
        select_class={select_class(@errors, @class)}
        {@rest}
      >
        <:option :if={@prompt} value="">{@prompt}</:option>
        <:option
          :for={opt <- @option}
          value={opt.value}
          selected={to_string(opt.value) == to_string(@value)}
          disabled={opt[:disabled]}
        >
          {render_slot(opt)}
        </:option>
      </NativeSelect.native_select>
      <p :for={msg <- @errors} class="mt-[var(--space-1)] text-sm text-danger">{msg}</p>
    </div>
    """
  end

  # native_select's `select_class` attr is declared as a plain :string, so
  # the usual `class={[...]}` list idiom trips a compile-time type warning —
  # build the token class string ourselves instead.
  defp select_class(errors, class) do
    [
      "w-full rounded-[var(--radius-sm)] border border-border bg-surface text-text",
      "px-[var(--space-3)] py-[var(--space-2)] text-sm",
      "focus:outline focus:outline-2 focus:outline-offset-2 focus:outline-focus-ring",
      errors != [] && "border-danger",
      class
    ]
    |> List.flatten()
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end
end

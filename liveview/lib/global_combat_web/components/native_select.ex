defmodule GlobalCombatWeb.Components.NativeSelect do
  @moduledoc """
  The `GlobalCombatWeb.Components.NativeSelect` module provides a customizable native select component
  for forms in Phoenix LiveView. It supports a variety of styles, colors, and sizes, making
  it adaptable to different design requirements. The module allows for flexible configuration
  of the select element, including options for multi-selection, custom labels, and error handling.

  This component is highly versatile, with extensive theming options such as border styles,
  color variants, and rounded corners. It also provides a convenient way to render select
  options through slots, enabling dynamic rendering of form elements based on the passed data.

  With built-in error handling and custom error messages, `GlobalCombatWeb.Components.NativeSelect`
  enhances the user experience by providing clear feedback and interaction states,
  ensuring a polished and user-friendly interface for form-based applications.

  **Documentation:** https://mishka.tools/chelekom/docs/forms/native-select
  """

  use Phoenix.Component
  import GlobalCombatWeb.Components.Icon, only: [icon: 1]

  @doc """
  Renders a customizable `native_select` input component with options for single or multiple selections.
  Supports validation and various styling options.

  ## Examples

  ```elixir
  <.native_select name="name" description="This is description" label="This is outline label">
    <:option value="usa">USA</:option>
    <:option value="uae" selected>UAE</:option>
  </.native_select>

  <.native_select
    name="name"
    space="small"
    color="danger"
    variant="default"
    multiple
    min_height="min-h-36"
    size="extra_small"
    description="This is multiple option group"
    label="This is outline label"
  >
    <.select_option_group label="group 1">
      <:option value="usa">USA</:option>
      <:option value="uae" selected>UAE</:option>
    </.select_option_group>

    <.select_option_group label="group 2">
      <:option value="usa">USA</:option>
      <:option value="uae">UAE</:option>
      <:option value="br" selected>Great Britain</:option>
    </.select_option_group>
  </.native_select>
  ```
  """
  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :color, :string, default: "natural", doc: "Determines color theme"
  attr :border, :string, default: "extra_small", doc: "Determines border style"
  attr :rounded, :string, default: "small", doc: "Determines the border radius"
  attr :variant, :string, default: "base", doc: "Determines the style"
  attr :description, :string, default: nil, doc: "Determines a short description"
  attr :space, :string, default: "medium", doc: "Space between items"
  attr :min_height, :string, default: nil, doc: "Determines min height style"
  attr :description_class, :string, default: "text-[12px]", doc: "Custom classes for description"
  attr :label_class, :string, default: nil, doc: "Custom CSS class for the label styling"
  attr :field_wrapper_class, :string, default: nil, doc: "Custom CSS class field wrapper"
  attr :select_class, :string, default: nil, doc: "Custom CSS class for additional styling"

  attr :description_wrapper_class, :string,
    default: nil,
    doc: "Custom classes for description wrapper"

  attr :size, :string,
    default: "extra_large",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  attr :ring, :boolean,
    default: true,
    doc:
      "Determines a ring border on focused input, utilities for creating outline rings with box-shadows."

  attr :error_icon, :string, default: nil, doc: "Icon to be displayed alongside error messages"
  attr :label, :string, default: nil, doc: "Specifies text for the label"

  attr :multiple, :boolean,
    default: false,
    doc: "Specifies if the select input allows multiple selections"

  attr :errors, :list, default: [], doc: "List of error messages to be displayed"
  attr :name, :any, doc: "Name of input"

  slot :inner_block, required: false, doc: "Inner block that renders HEEx content"

  slot :option, required: false do
    attr :value, :string, doc: "Value of each select option"
    attr :selected, :boolean, required: false, doc: "Specifies this option is selected"
    attr :disabled, :string, required: false, doc: "Specifies this option is disabled"
  end

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :rest, :global,
    include: ~w(autocomplete disabled form readonly multiple required title autofocus tabindex),
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  @spec native_select(map()) :: Phoenix.LiveView.Rendered.t()
  def native_select(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn ->
      if assigns.rest[:multiple], do: field.name <> "[]", else: field.name
    end)
    |> assign_new(:value, fn -> field.value end)
    |> native_select()
  end

  def native_select(assigns) do
    ~H"""
    <div class={[
      @variant != "native" && color_variant(@variant, @color),
      rounded_size(@rounded),
      border_class(@border, @variant),
      size_class(@size),
      space_class(@space),
      "[&_.select-field]:focus-within:outline-none",
      @ring && "[&_.select-field]:focus-within:ring-1",
      @class
    ]}>
      <div
        :if={@label || @description}
        class={["select-label-wrapper", @description_wrapper_class]}
      >
        <.label :if={@label} for={@id} class={@label_class}>{@label}</.label>
        <div :if={@description} class={@description_class}>
          {@description}
        </div>
      </div>

      <select
        name={@name}
        id={@id}
        multiple={@multiple}
        class={[
          "select-field appearance-none block w-full text-[16px] sm:font-inherit py-1 px-2",
          @multiple && "select-multiple-option",
          @errors != [] && "select-field-error",
          @min_height,
          @select_class
        ]}
        {@rest}
      >
        <option
          :for={{option, index} <- Enum.with_index(@option, 1)}
          id={"#{@id}-option-#{index}"}
          value={option[:value]}
          selected={option[:selected]}
          disabled={option[:disabled]}
        >
          {render_slot(option)}
        </option>
      </select>

      <.error :for={msg <- @errors} icon={@error_icon}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a group (`select_option_group`) of selectable options within a native select input.
  The group can have a label and multiple options, with support for selected and disabled states.

  ## Examples

  ```elixir
  <.select_option_group label="group 2">
    <:option value="usa">USA</:option>
    <:option value="uae">UAE</:option>
    <:option value="br" selected>Great Britain</:option>
  </.select_option_group>
  ```
  """
  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :label, :string, default: nil, doc: "Specifies text for the label"
  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"

  slot :option, required: false, doc: "Option slot for select" do
    attr :value, :string, doc: "Value of each select option"
    attr :selected, :boolean, required: false, doc: "Specifies this option is selected"
    attr :disabled, :string, required: false, doc: "Specifies this option is disabled"
  end

  def select_option_group(assigns) do
    ~H"""
    <optgroup label={@label} class={@class}>
      <option
        :for={{option, index} <- Enum.with_index(@option, 1)}
        id={"#{@id}-option-#{index}"}
        value={option[:value]}
        selected={option[:selected]}
        disabled={option[:disabled]}
      >
        {render_slot(option)}
      </option>
    </optgroup>
    """
  end

  attr :for, :string, default: nil, doc: "Specifies the form which is associated with"
  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  defp label(assigns) do
    ~H"""
    <label for={@for} class={["font-semibold", @class]}>
      {render_slot(@inner_block)}
    </label>
    """
  end

  attr :icon, :string, default: nil, doc: "Icon displayed alongside of an item"
  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  defp error(assigns) do
    ~H"""
    <p class="mt-3 flex items-center gap-3 text-sm text-rose-700">
      <.icon :if={!is_nil(@icon)} name={@icon} class="shrink-0" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  defp size_class("extra_small") do
    [
      "text-xs [&_.select-field]:text-xs [&_.select-field:not(.select-multiple-option)]:h-8"
    ]
  end

  defp size_class("small") do
    [
      "text-sm [&_.select-field]:text-sm [&_.select-field:not(.select-multiple-option)]:h-9"
    ]
  end

  defp size_class("medium") do
    [
      "text-base [&_.select-field]:text-base [&_.select-field:not(.select-multiple-option)]:h-10"
    ]
  end

  defp size_class("large") do
    [
      "text-lg [&_.select-field]:text-lg [&_.select-field:not(.select-multiple-option)]:h-11"
    ]
  end

  defp size_class("extra_large") do
    [
      "text-xl [&_.select-field]:text-xl [&_.select-field:not(.select-multiple-option)]:h-12"
    ]
  end

  defp size_class(params) when is_binary(params), do: params

  defp rounded_size("extra_small"), do: "[&_.select-field]:rounded-sm"

  defp rounded_size("small"), do: "[&_.select-field]:rounded"

  defp rounded_size("medium"), do: "[&_.select-field]:rounded-md"

  defp rounded_size("large"), do: "[&_.select-field]:rounded-lg"

  defp rounded_size("extra_large"), do: "[&_.select-field]:rounded-xl"

  defp rounded_size("full"), do: "[&_.select-field]:rounded-full"

  defp rounded_size("none"), do: nil

  defp rounded_size(params) when is_binary(params), do: params

  defp border_class(_, variant)
       when variant in [
              "default",
              "shadow",
              "native"
            ],
       do: nil

  defp border_class("none", _), do: "[&_.select-field]:border-0"
  defp border_class("extra_small", _), do: "[&_.select-field]:border"
  defp border_class("small", _), do: "[&_.select-field]:border-2"
  defp border_class("medium", _), do: "[&_.select-field]:border-[3px]"
  defp border_class("large", _), do: "[&_.select-field]:border-4"
  defp border_class("extra_large", _), do: "[&_.select-field]:border-[5px]"
  defp border_class(params, _) when is_binary(params), do: params

  defp space_class("none"), do: nil

  defp space_class("extra_small"), do: "space-y-1"

  defp space_class("small"), do: "space-y-1.5"

  defp space_class("medium"), do: "space-y-2"

  defp space_class("large"), do: "space-y-2.5"

  defp space_class("extra_large"), do: "space-y-3"

  defp space_class(params) when is_binary(params), do: params

  defp color_variant("default", "primary") do
    [
      "text-black dark:text-white [&_.select-field:not(:has(.select-field-error))]:bg-primary-light",
      "dark:[&_.select-field:not(:has(.select-field-error))]:bg-primary-dark",
      "[&_.select-field.select-field-error]:bg-rose-700",
      "[&_.select-field]:text-white dark:[&_.select-field]:text-black",
      "focus-within:[&_.select-field]:ring-primary-light dark:focus-within:[&_.select-field]:ring-primary-dark"
    ]
  end

  defp color_variant("default", "success") do
    [
      "text-black dark:text-white [&_.select-field:not(:has(.select-field-error))]:bg-success-light",
      "dark:[&_.select-field:not(:has(.select-field-error))]:bg-success-dark",
      "[&_.select-field.select-field-error]:bg-rose-700",
      "[&_.select-field]:text-white dark:[&_.select-field]:text-black",
      "focus-within:[&_.select-field]:ring-success-light dark:focus-within:[&_.select-field]:ring-success-dark"
    ]
  end

  defp color_variant("default", "warning") do
    [
      "text-black dark:text-white [&_.select-field:not(:has(.select-field-error))]:bg-warning-light",
      "dark:[&_.select-field:not(:has(.select-field-error))]:bg-warning-dark",
      "[&_.select-field.select-field-error]:bg-rose-700",
      "[&_.select-field]:text-white dark:[&_.select-field]:text-black",
      "focus-within:[&_.select-field]:ring-warning-light dark:focus-within:[&_.select-field]:ring-warning-dark"
    ]
  end

  defp color_variant("default", "danger") do
    [
      "text-black dark:text-white [&_.select-field:not(:has(.select-field-error))]:bg-danger-light",
      "dark:[&_.select-field:not(:has(.select-field-error))]:bg-danger-dark",
      "[&_.select-field.select-field-error]:bg-rose-700",
      "[&_.select-field]:text-white dark:[&_.select-field]:text-black",
      "focus-within:[&_.select-field]:ring-danger-light dark:focus-within:[&_.select-field]:ring-danger-dark"
    ]
  end

  defp color_variant("default", "info") do
    [
      "text-black dark:text-white [&_.select-field:not(:has(.select-field-error))]:bg-info-light",
      "dark:[&_.select-field:not(:has(.select-field-error))]:bg-info-dark",
      "[&_.select-field.select-field-error]:bg-rose-700",
      "[&_.select-field]:text-white dark:[&_.select-field]:text-black",
      "focus-within:[&_.select-field]:ring-info-light dark:focus-within:[&_.select-field]:ring-info-dark"
    ]
  end

  defp color_variant(params, _) when is_binary(params), do: params

  defp translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(GlobalCombatWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(GlobalCombatWeb.Gettext, "errors", msg, opts)
    end
  end
end

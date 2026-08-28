defmodule GlobalCombatWeb.Components.Modal do
  @moduledoc """
  The `GlobalCombatWeb.Components.Modal` module provides a versatile and customizable modal component for
  Phoenix LiveView applications. It supports various configurations for size, style, color,
  padding, and border radius to match different design requirements. The module is designed
  to facilitate user interactions with dynamic content, such as forms,
  confirmation dialogs, or notifications.

  The modal component includes JavaScript hooks for showing and hiding the modal,
  which are triggered based on user actions or programmatic events.

  The component is equipped to handle accessibility features like focus management
  and keyboard navigation to ensure a seamless user experience.

  This module can be integrated with other components and tailored for various use cases
  in web applications, making it a powerful tool for enhancing user interfaces and interaction workflows.

  **Documentation:** https://mishka.tools/chelekom/docs/modal
  """

  use Phoenix.Component
  use Gettext, backend: GlobalCombatWeb.Gettext
  alias Phoenix.LiveView.JS
  import GlobalCombatWeb.Components.Icon, only: [icon: 1]

  @doc """
  Renders a customizable `modal` component that displays overlay content with optional title and inner content.
  It can be controlled with the `show` attribute and includes actions for closing the modal.

  ## Examples

  ```elixir
  <.modal id="modal-1" title="default">
    <div>
      Lorem ipsum dolor sit amet consectetur adipisicing elit.
      Commodi ea atque soluta praesentium quidem dicta sapiente accusamus nihil.
    </div>
  </.modal>

  <.modal id="modal-2" title="Info Modal" show>
    <div>
      Lorem ipsum dolor sit amet consectetur adipisicing elit.
      Commodi ea atque soluta praesentium quidem dicta sapiente accusamus nihil.
    </div>
  </.modal>

  <.modal id="modal-3" color="primary" rounded="large" title="Custom Modal">
    <p>Customize the modal appearance by changing attributes like `color` and `rounded`.</p>
  </.modal>
  ```
  """
  @doc type: :component
  attr :id, :string,
    required: true,
    doc: "A unique identifier is used to manage state and interaction"

  attr :title, :string, default: nil, doc: "Specifies the title of the element"
  attr :variant, :string, default: "base", doc: "Determines the style"
  attr :color, :string, default: "natural", doc: "Determines color theme"
  attr :rounded, :string, default: "small", doc: "Determines the border radius"
  attr :border, :string, default: "extra_small", doc: "Determines border style"
  attr :padding, :string, default: "medium", doc: "Determines padding for items"

  attr :size, :string,
    default: "extra_large",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"

  attr :title_class, :string,
    default: "text-base md:text-lg xl:text-2xl",
    doc: "Custom CSS class for additional styling to title"

  attr :icon_class, :string,
    default: "size-5",
    doc: "Custom CSS class for additional styling to icons close button"

  attr :content_class, :string,
    default: nil,
    doc: "Custom CSS class for additional styling to content"

  attr :close_class, :string,
    default: nil,
    doc: "Custom CSS class for additional styling to content"

  attr :focus_wrap_class, :string,
    default: nil,
    doc: "Custom CSS class for additional styling to focus wrapper"

  attr :inner_wrapper_class, :string,
    default: nil,
    doc: "Custom CSS class for additional styling to inner wrap"

  attr :wrapper_class, :string,
    default: nil,
    doc: "Custom CSS class for additional styling to wrapper"

  attr :overlay_class, :string,
    default: nil,
    doc: "Custom CSS class for additional styling to overlay"

  attr :show, :boolean, default: false, doc: "Show element"
  attr :on_cancel, JS, default: %JS{}, doc: "Custom JS module for on_cancel action"
  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class={["relative z-50 hidden", @class]}
    >
      <div
        id={"#{@id}-bg"}
        class={["fixed inset-0 transition-opacity", @overlay_class]}
        aria-hidden="true"
      />
      <div
        class={["fixed inset-0 overflow-y-auto", @wrapper_class]}
        aria-labelledby={@title && "#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class={["flex min-h-full items-center justify-center", @inner_wrapper_class]}>
          <div class="w-full">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class={[
                "relative hidden transition",
                color_variant(@variant, @color),
                border_size(@border, @variant),
                rounded_size(@rounded),
                padding_size(@padding),
                size_class(@size),
                @focus_wrap_class
              ]}
            >
              <div class="flex items-center justify-between mb-4">
                <div :if={@title} id={"#{@id}-title"} class={["font-semibold", @title_class]}>
                  {@title}
                </div>
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class={["p-2 hover:opacity-60", @close_class]}
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class={@icon_class} />
                </button>
              </div>

              <div id={"#{@id}-description"} class={@content_class}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp border_size(_, variant)
       when variant in [
              "default",
              "shadow",
              "gradient"
            ],
       do: nil

  defp border_size("none", _), do: nil
  defp border_size("extra_small", _), do: "border"
  defp border_size("small", _), do: "border-2"
  defp border_size("medium", _), do: "border-[3px]"
  defp border_size("large", _), do: "border-4"
  defp border_size("extra_large", _), do: "border-[5px]"
  defp border_size(params, _) when is_binary(params), do: params

  defp rounded_size("extra_small"), do: "rounded-sm"

  defp rounded_size("small"), do: "rounded"

  defp rounded_size("medium"), do: "rounded-md"

  defp rounded_size("large"), do: "rounded-lg"

  defp rounded_size("extra_large"), do: "rounded-xl"

  defp rounded_size("none"), do: nil

  defp rounded_size(params) when is_binary(params), do: params

  defp padding_size("extra_small"), do: "p-2"

  defp padding_size("small"), do: "p-3"

  defp padding_size("medium"), do: "p-4"

  defp padding_size("large"), do: "p-5"

  defp padding_size("extra_large"), do: "p-6"

  defp padding_size("none"), do: "p-0"

  defp padding_size(params) when is_binary(params), do: params

  defp size_class("extra_small"), do: "mx-auto max-w-xs"

  defp size_class("small"), do: "mx-auto max-w-sm"

  defp size_class("medium"), do: "mx-auto max-w-md"

  defp size_class("large"), do: "mx-auto max-w-lg"

  defp size_class("extra_large"), do: "mx-auto max-w-xl"

  defp size_class("double_large"), do: "mx-auto max-w-2xl"

  defp size_class("triple_large"), do: "mx-auto max-w-3xl"

  defp size_class("quadruple_large"), do: "mx-auto max-w-4xl"

  defp size_class("screen"), do: "w-full h-screen overflow-y-scroll"

  defp size_class(params) when is_binary(params), do: params

  defp color_variant("default", "primary") do
    [
      "bg-primary-light text-white dark:bg-primary-dark dark:text-black"
    ]
  end

  defp color_variant("default", "success") do
    [
      "bg-success-light text-white dark:bg-success-dark dark:text-black"
    ]
  end

  defp color_variant("default", "warning") do
    [
      "bg-warning-light text-white dark:bg-warning-dark dark:text-black"
    ]
  end

  defp color_variant("default", "danger") do
    [
      "bg-danger-light text-white dark:bg-danger-dark dark:text-black"
    ]
  end

  defp color_variant("default", "info") do
    [
      "bg-info-light text-white dark:bg-info-dark dark:text-black"
    ]
  end

  defp color_variant(params, _) when is_binary(params), do: params

  ## JS Commands

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> transition_show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> transition_hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  defp transition_show(js, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  defp transition_hide(js, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  ## We do not use these functions, just for Phoenix CoreComponent backward compatibility

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end
end

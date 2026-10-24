defmodule GlobalCombatWeb.Components.InlineMessage do
  @moduledoc """
  A one-line status or error message inside a form page — the bordered row the Log On
  card already used for a failed attempt, made shareable so Lost Password, Settings and
  Contact stop each styling their own (and stop reaching for daisyUI's `alert` classes,
  which the design-boutique themes never style).

  `danger` carries `role="alert"` (assertive); `info`/`success` carry `role="status"`
  (polite), the same split as `Boutique.Notification` and `PageState`. This is not a
  `Notification`: these pages are dead views, so its JS dismiss button would do nothing.
  Message text stays `--color-text` for info/success — the light theme's success hue
  sits under 4.5:1 as text — and only the leading icon takes the intent hue.
  """
  use Phoenix.Component

  import GlobalCombatWeb.Components.Icon, only: [icon: 1]

  attr :id, :string, default: nil
  attr :intent, :string, values: ~w(info success danger), default: "info"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def inline_message(assigns) do
    ~H"""
    <p
      id={@id}
      role={role(@intent)}
      class={[
        "flex items-start gap-[var(--space-2)] rounded-[var(--radius-sm)] border",
        "px-[var(--space-3)] py-[var(--space-2)] text-sm",
        intent_class(@intent),
        @class
      ]}
      {@rest}
    >
      <.icon name={icon_name(@intent)} class={["size-5 shrink-0", icon_class(@intent)]} />
      <span>{render_slot(@inner_block)}</span>
    </p>
    """
  end

  defp role("danger"), do: "alert"
  defp role(_), do: "status"

  defp intent_class("danger"), do: "border-danger text-danger"
  defp intent_class("success"), do: "border-success text-text"
  defp intent_class("info"), do: "border-info text-text"

  defp icon_name("danger"), do: "hero-exclamation-circle"
  defp icon_name("success"), do: "hero-check-circle"
  defp icon_name("info"), do: "hero-information-circle"

  defp icon_class("danger"), do: nil
  defp icon_class("success"), do: "text-success"
  defp icon_class("info"), do: "text-info"
end

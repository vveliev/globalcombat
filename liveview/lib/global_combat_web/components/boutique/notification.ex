defmodule GlobalCombatWeb.Components.Boutique.Notification do
  @moduledoc """
  LiveView mirror of `components/react/Notification` (Mantine `Notification`
  wrapper). `intent` resolves through the theme's status hues with a soft
  fill (`/10` background + colored border/title), matching Mantine's
  default visual weight rather than a solid fill. Dismissal is pure
  client-side via `Phoenix.LiveView.JS.hide/2` targeting the notification's
  own `id` — pass `on_close` to compose additional JS (e.g. a server push)
  onto the same click, mirroring the React side's `onClose` callback.

  `danger`/`warning` carry `role="alert"` (assertive — an error or warning
  should interrupt); `info`/`success` carry `role="status"` (polite),
  matching `page_state.ex`'s severity-based role split.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import GlobalCombatWeb.Components.Icon, only: [icon: 1]

  attr :id, :string, required: true, doc: "Wrapper id — the close button's JS.hide target."
  attr :intent, :string, values: ~w(info success warning danger), default: "info"
  attr :title, :string, default: nil
  attr :class, :any, default: nil

  attr :on_close, JS,
    default: %JS{},
    doc: "Extra JS command(s) composed onto the close button's client-side hide."

  slot :inner_block, required: true, doc: "Message body — mirrors the React side's `children`."

  def notification(assigns) do
    ~H"""
    <div
      id={@id}
      role={role(@intent)}
      class={[
        "relative flex items-start gap-[var(--space-3)] rounded-[var(--radius-md)]",
        "border p-[var(--space-5)] shadow-md",
        intent_class(@intent),
        @class
      ]}
    >
      <div class="flex-1">
        <p :if={@title} class={["font-semibold", intent_title(@intent)]}>{@title}</p>
        <div class="mt-[var(--space-1)] text-text-muted">
          {render_slot(@inner_block)}
        </div>
      </div>
      <button
        type="button"
        phx-click={JS.hide(@on_close, to: "##{@id}")}
        class={[
          "shrink-0 rounded-[var(--radius-sm)] p-[var(--space-1)] text-text-muted hover:text-text",
          "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
        ]}
        aria-label="Close notification"
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  defp role("danger"), do: "alert"
  defp role("warning"), do: "alert"
  defp role(_), do: "status"

  defp intent_class("info"), do: "bg-info/10 border-info text-text"
  defp intent_class("success"), do: "bg-success/10 border-success text-text"
  defp intent_class("warning"), do: "bg-warning/10 border-warning text-text"
  defp intent_class("danger"), do: "bg-danger/10 border-danger text-text"

  defp intent_title("info"), do: "text-info"
  defp intent_title("success"), do: "text-success"
  defp intent_title("warning"), do: "text-warning"
  defp intent_title("danger"), do: "text-danger"
end

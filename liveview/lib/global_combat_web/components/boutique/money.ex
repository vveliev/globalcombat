defmodule GlobalCombatWeb.Components.Boutique.Money do
  @moduledoc """
  LiveView mirror of `components/react/Money`. An amount is never rendered
  without its currency — the ERP buys in several currencies at a manually
  entered exchange rate, so a bare number is ambiguous at best and wrong at
  worst; where a conversion happened, the rate that produced the figure
  travels with it.

  **Deviation from the React source:** React formats `amount` via
  `Intl.NumberFormat(locale, { style: "currency", currency, currencyDisplay:
  "code" })`. Elixir has no built-in ICU/`Intl` equivalent, and
  reimplementing locale-aware currency formatting inside a presentational
  component would be dishonest work this component has no business doing.
  This mirror therefore accepts `amount` already formatted as a string
  (e.g. `"1,204.00"`) — formatting/i18n is the caller's job, same as any
  other server-rendered currency figure in this stack (via whatever
  currency-formatting library the caller already has, or manual
  formatting) — and only owns layout: tabular figures, the currency-code
  prefix, and the rate tooltip/AT text. `currency` stays required so a
  figure is never shown unlabelled.

  `rate`, when present, records the manually entered conversion and is
  exposed to both pointer (native `title` tooltip) and assistive tech (a
  visually-hidden trailing span), mirroring the React side's
  `<VisuallyHidden>`.
  """
  use Phoenix.Component

  attr :amount, :string,
    required: true,
    doc: ~s(Pre-formatted amount, e.g. "1,204.00" — caller does the i18n/ICU formatting.)

  attr :currency, :string, required: true, doc: ~s(ISO 4217 code, e.g. "CAD".)

  attr :rate, :map,
    default: nil,
    doc: ~s(%{from: "USD", value: 1.35} — the manually entered conversion, if any.)

  attr :class, :any, default: nil
  attr :rest, :global

  def money(assigns) do
    assigns = assign(assigns, :converted, converted_text(assigns.rate))

    ~H"""
    <span title={@converted} class={["tabular-nums whitespace-nowrap", @class]} {@rest}>
      {@currency} {@amount}<span :if={@converted} class="sr-only"> ({@converted})</span>
    </span>
    """
  end

  defp converted_text(%{from: from, value: value}), do: "Converted from #{from} at #{value}"
  defp converted_text(_), do: nil
end

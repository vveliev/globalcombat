defmodule GlobalCombatWeb.Components.Boutique.Quantity do
  @moduledoc """
  LiveView mirror of `components/react/Quantity`. A quantity always carries
  its unit of measure — inventory holds raw material in one unit and parts
  in another, so a bare "48" cannot be reconciled against a minimum stock
  level. Optionally renders against a threshold so a stock breach reads at
  a glance in words as well as by hue.

  **Minor deviation from the React source:** React formats `value` via
  `Intl.NumberFormat` (locale-aware). Elixir has no built-in ICU
  equivalent, so this mirror does its own light rounding/trimming instead
  (no thousands-separator grouping) rather than accept a caller-preformatted
  string — unlike `money.ex`, `value` still has to be a real number here
  since it drives the `min` stock-breach comparison, so keeping one numeric
  source of truth is simpler and more honest than threading a parallel
  formatted string alongside it.
  """
  use Phoenix.Component

  attr :value, :any, required: true, doc: "Numeric quantity (integer or float)."
  attr :unit, :string, required: true, doc: ~s(Unit of measure, e.g. "kg", "ea", "sheet".)

  attr :precision, :integer,
    default: nil,
    doc: "Decimal places; defaults to whatever the value carries, capped at 2."

  attr :min, :any, default: nil, doc: "Below this, the quantity reads as a breach."
  attr :class, :any, default: nil
  attr :rest, :global

  def quantity(assigns) do
    ~H"""
    <span
      class={[
        "tabular-nums whitespace-nowrap",
        below_min?(@value, @min) && "font-bold text-status-offline",
        @class
      ]}
      {@rest}
    >
      {format_value(@value, @precision)} {@unit}<span :if={below_min?(@value, @min)}> · below min</span>
    </span>
    """
  end

  defp below_min?(_value, nil), do: false
  defp below_min?(value, min), do: value < min

  defp format_value(value, precision) when is_integer(precision) do
    :erlang.float_to_binary(to_float(value), decimals: precision)
  end

  defp format_value(value, nil) do
    rounded = Float.round(to_float(value), 2)

    if rounded == Float.round(rounded, 0) do
      rounded |> trunc() |> Integer.to_string()
    else
      rounded
      |> :erlang.float_to_binary(decimals: 2)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    end
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
end

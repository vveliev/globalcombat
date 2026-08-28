defmodule GlobalCombatWeb.Components.Boutique.BarChart do
  @moduledoc """
  Token-driven single-series bar chart — LiveView mirror of
  `components/react/BarChart` (pure tokens, no Mishka primitive: a static
  SVG figure has no interaction to inherit). Geometry constants
  (`@view_w`/`@view_h`/`@plot_h`/`@base_y`/`@end_r`) mirror the shared
  `components/react/chart-frame.tsx` scaffolding that `BarChart` and
  `LineChart` both build on in React — HEEx has no equivalent shared-import
  story for private constants across two component modules, so each module
  keeps its own copy rather than introducing a third shared file for four
  numbers.

  One series by design: the semantic vocabulary has no categorical chart
  palette, so bars carry `--color-primary` and identity lives in the axis
  labels. Values render in text ink, never the series color. Each bar gets
  a native `<title>` tooltip (`"label: display"`); a visually-hidden
  (`sr-only`) `<table>` carries the same data for assistive tech.

  Accessibility scheme: the `<svg role="img" aria-label={@label}>` is the
  named graphic (screen readers announce `@label` on it) and the `sr-only`
  table beneath it is the tabular truth for anyone who needs the exact
  numbers — visually hidden, never `aria-hidden`, so assistive tech can
  still read it. The two are complementary, not redundant: `role="img"`
  gives a one-line summary, the table gives the full breakdown.

  `display` on a datum is a preformatted string (`"$482k"`); it defaults to
  `to_string(value)` when omitted, mirroring React's `d.display ?? String(d.value)`.
  """
  use Phoenix.Component

  @view_w 1000
  @view_h 560
  @plot_h 440
  @base_y 480
  # softened data-end radius, viewBox units
  @end_r 6

  attr :id, :any, default: nil
  attr :class, :any, default: nil

  attr :data, :list,
    required: true,
    doc: "list of %{label: string, value: number, display: string | nil}"

  attr :label, :string,
    required: true,
    doc: "one-line accessible description of what the chart shows"

  attr :show_values, :boolean, default: true, doc: "direct value labels above the bars"
  attr :rest, :global

  def bar_chart(assigns) do
    assigns =
      assigns
      |> assign(:view_w, @view_w)
      |> assign(:view_h, @view_h)
      |> assign(:base_y, @base_y)
      |> assign(:plot_h, @plot_h)
      |> assign(:bars, bars(assigns.data))

    ~H"""
    <figure id={@id} class={@class} {@rest}>
      <svg
        viewBox={"0 0 #{@view_w} #{@view_h}"}
        role="img"
        aria-label={@label}
        class="block h-auto w-full"
      >
        <line
          :for={t <- [0.25, 0.5, 0.75]}
          x1="0"
          x2={@view_w}
          y1={@base_y - @plot_h * t}
          y2={@base_y - @plot_h * t}
          class="stroke-divider"
          vector-effect="non-scaling-stroke"
        />
        <line
          x1="0"
          x2={@view_w}
          y1={@base_y}
          y2={@base_y}
          class="stroke-border"
          vector-effect="non-scaling-stroke"
        />

        <g :for={b <- @bars}>
          <path d={b.path} class="fill-primary">
            <title>{"#{b.label}: #{b.display}"}</title>
          </path>
          <text
            :if={@show_values}
            x={b.mid_x}
            y={b.y - 14}
            text-anchor="middle"
            class="fill-text font-body text-[26px] tabular-nums"
          >
            {b.display}
          </text>
          <text
            x={b.mid_x}
            y={@base_y + 40}
            text-anchor="middle"
            class="fill-text-muted font-body text-[24px]"
          >
            {b.label}
          </text>
        </g>
      </svg>
      <%!-- table fallback: the same data, readable without the graphic --%>
      <table class="sr-only">
        <tbody>
          <tr :for={d <- @data}>
            <th scope="row">{d.label}</th>
            <td>{display_value(d)}</td>
          </tr>
        </tbody>
      </table>
    </figure>
    """
  end

  defp bars(data) do
    max_v = Enum.max([1 | Enum.map(data, & &1.value)])
    count = length(data)
    band = @view_w / max(count, 1)
    bar_w = band * 0.6

    data
    |> Enum.with_index()
    |> Enum.map(fn {d, i} ->
      h = max(d.value / max_v * @plot_h, @end_r)
      x = band * i + (band - bar_w) / 2
      y = @base_y - h
      r = min(@end_r, bar_w / 2)

      %{
        label: d.label,
        display: display_value(d),
        mid_x: round3(x + bar_w / 2),
        y: round3(y),
        path: bar_path(x, y, bar_w, r)
      }
    end)
  end

  # top-rounded, baseline-anchored bar
  defp bar_path(x, y, bar_w, r) do
    x1 = round3(x)
    y1 = round3(y)
    yr = round3(y + r)
    xr = round3(x + r)
    x2 = round3(x + bar_w - r)
    xw = round3(x + bar_w)

    "M #{x1} #{@base_y} V #{yr} Q #{x1} #{y1} #{xr} #{y1} H #{x2} Q #{xw} #{y1} #{xw} #{yr} V #{@base_y} Z"
  end

  defp display_value(%{display: display}) when not is_nil(display), do: display
  defp display_value(%{value: value}), do: to_string(value)

  defp round3(n), do: Float.round(n * 1.0, 3)
end

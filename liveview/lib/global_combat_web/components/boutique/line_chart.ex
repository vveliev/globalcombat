defmodule GlobalCombatWeb.Components.Boutique.LineChart do
  @moduledoc """
  Token-driven line chart, one or two series — LiveView mirror of
  `components/react/LineChart` (pure tokens, no Mishka primitive). The
  semantic vocabulary has no categorical chart palette, so the two allowed
  voices are the accent (`--color-primary`, solid line) and the ink
  (`--color-text`, dashed line) — identity never rides on hue alone. A
  third series raises rather than inventing a color. Two series always
  render a legend (solid swatches + names in text ink); a single series is
  named by `label`/`figcaption` alone. Markers are filled dots ringed with
  `--color-surface` so they "punch through" overlapping lines. A
  visually-hidden (`sr-only`) `<table>` carries the same data as the SVG —
  see `BarChart`'s moduledoc for the accessibility rationale (`role="img"`
  names the graphic, the table is the tabular truth for assistive tech).

  ## `formatValue` deviation

  React's `formatValue` is a client-side callback (`(value: number) =>
  string`) applied to every point for tooltips and the table fallback.
  LiveView renders on the server — there is no callback to invoke per
  point, so this mirror does not accept a function attr. Instead, each
  point in a series carries its own preformatted string alongside the raw
  value: `%{value: 1208, formatted: "1.2k"}`. The caller formats before
  passing data in (the same shift `BarChart.display` already makes for the
  same reason). A bare number (`10`) is also accepted per point and
  defaults its `formatted` string to `to_string(value)`, mirroring React's
  default `formatValue = String`.

  Geometry constants mirror `components/react/chart-frame.tsx` plus
  `LineChart.tsx`'s own `PLOT_H`/`MARKER_R` overrides — see `BarChart`'s
  moduledoc for why they're duplicated per module instead of shared.
  """
  use Phoenix.Component

  @view_w 1000
  @view_h 560
  @base_y 480
  # slightly shorter than the bar plot: markers need headroom
  @plot_h 420
  # viewBox units; keeps markers touch-findable at typical sizes
  @marker_r 9

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :labels, :list, required: true, doc: "shared x-axis labels"

  attr :series, :list,
    required: true,
    doc:
      "1 or 2 series: [%{name: string, points: [%{value: number, formatted: string | nil} | number]}]"

  attr :label, :string,
    required: true,
    doc: "one-line accessible description of what the chart shows"

  attr :rest, :global

  def line_chart(assigns) do
    series = assigns.series

    unless length(series) in 1..2 do
      raise ArgumentError,
            "LineChart renders 1 or 2 series, got #{length(series)} — the semantic vocabulary " <>
              "has no categorical chart palette; split into small multiples instead."
    end

    step_x = step_x(assigns.labels)
    chart_series = chart_series(series, assigns.labels, step_x)

    assigns =
      assigns
      |> assign(:view_w, @view_w)
      |> assign(:view_h, @view_h)
      |> assign(:base_y, @base_y)
      |> assign(:plot_h, @plot_h)
      |> assign(:marker_r, @marker_r)
      |> assign(:step_x, step_x)
      |> assign(:chart_series, chart_series)

    ~H"""
    <figure id={@id} class={@class} {@rest}>
      <svg
        viewBox={"0 0 #{@view_w} #{@view_h}"}
        role="img"
        aria-label={@label}
        class="block h-auto w-full overflow-visible"
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

        <g :for={s <- @chart_series}>
          <polyline
            points={s.polyline_points}
            fill="none"
            class={s.line_class}
            stroke-width="2"
            stroke-dasharray={s.dash}
            stroke-linejoin="round"
            stroke-linecap="round"
            vector-effect="non-scaling-stroke"
          />
          <circle
            :for={p <- s.points}
            cx={p.x}
            cy={p.y}
            r={@marker_r}
            class={[s.marker_class, "stroke-surface"]}
            stroke-width="2"
            vector-effect="non-scaling-stroke"
          >
            <title>{"#{s.name} — #{p.label}: #{p.formatted}"}</title>
          </circle>
        </g>

        <text
          :for={{l, i} <- Enum.with_index(@labels)}
          x={i * @step_x}
          y={@base_y + 40}
          text-anchor={label_anchor(i, length(@labels))}
          class="fill-text-muted font-body text-[24px]"
        >
          {l}
        </text>
      </svg>

      <figcaption
        :if={length(@chart_series) > 1}
        class="mt-[var(--space-2)] flex gap-[var(--space-6)] text-xs text-text"
      >
        <span :for={s <- @chart_series} class="inline-flex items-center gap-[var(--space-2)]">
          <span aria-hidden="true" class={["h-[0.1875rem] w-3 rounded-full", s.swatch_class]} />
          {s.name}
        </span>
      </figcaption>

      <table class="sr-only">
        <thead>
          <tr>
            <th scope="col">x</th>
            <th :for={s <- @chart_series} scope="col">{s.name}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{l, i} <- Enum.with_index(@labels)}>
            <th scope="row">{l}</th>
            <td :for={s <- @chart_series}>{Enum.at(s.points, i).formatted}</td>
          </tr>
        </tbody>
      </table>
    </figure>
    """
  end

  defp chart_series(series, labels, step_x) do
    max_v =
      Enum.max([
        1
        | Enum.flat_map(series, fn s -> Enum.map(s.points, &point_value/1) end)
      ])

    series
    |> Enum.with_index()
    |> Enum.map(fn {s, si} ->
      style = series_style(si)

      points =
        s.points
        |> Enum.with_index()
        |> Enum.map(fn {p, i} ->
          x = round3(i * step_x)
          y = round3(@base_y - point_value(p) / max_v * @plot_h)
          %{x: x, y: y, label: Enum.at(labels, i), formatted: point_formatted(p)}
        end)

      polyline_points = Enum.map_join(points, " ", fn %{x: x, y: y} -> "#{x},#{y}" end)

      %{
        name: s.name,
        dash: style.dash,
        line_class: style.line_class,
        marker_class: style.marker_class,
        swatch_class: style.swatch_class,
        points: points,
        polyline_points: polyline_points
      }
    end)
  end

  defp series_style(0),
    do: %{
      line_class: "stroke-primary",
      marker_class: "fill-primary",
      swatch_class: "bg-primary",
      dash: nil
    }

  defp series_style(1),
    do: %{
      line_class: "stroke-text",
      marker_class: "fill-text",
      swatch_class: "bg-text",
      dash: "10 8"
    }

  defp point_value(%{value: value}), do: value
  defp point_value(value) when is_number(value), do: value

  defp point_formatted(%{formatted: formatted}) when not is_nil(formatted), do: formatted
  defp point_formatted(%{value: value}), do: to_string(value)
  defp point_formatted(value) when is_number(value), do: to_string(value)

  defp step_x(labels), do: @view_w / max(length(labels) - 1, 1)

  defp label_anchor(0, _len), do: "start"
  defp label_anchor(i, len) when i == len - 1, do: "end"
  defp label_anchor(_i, _len), do: "middle"

  defp round3(n), do: Float.round(n * 1.0, 3)
end

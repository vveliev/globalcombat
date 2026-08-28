defmodule GlobalCombatWeb.Components.Boutique.Calendar do
  @moduledoc """
  Month-grid date picker — LiveView mirror of `components/react/Calendar`
  (a thin wrap of Mantine's `DatePicker`). Mishka Chelekom has no grid
  calendar counterpart — its `date_time_field` is just a styled
  `<input type="date">` — so this is a genuinely hand-built component, not
  a restyle.

  ## State ownership

  This is a **stateless function component**: it renders a month grid from
  assigns and owns no state of its own. The calling LiveView owns the
  "which year/month is currently being viewed" and "which date is
  selected" state, and re-renders this component with new
  `year`/`month`/`selected` assigns in response to the `phx-click` events
  it wires up via `prev_event`/`next_event`/`select_event`. That's the
  idiomatic Phoenix pattern for rich interactive UI with no server-side
  identity of its own — a `LiveComponent` would just move the same state
  into a second process for no benefit here.

  `today` is a **required** attr, never defaulted via `Date.utc_today()`
  inside the component: a render function that reaches for wall-clock time
  itself is impure and makes tests non-deterministic. The caller (typically
  the parent LiveView's `mount/3`) supplies "now".

  ## Grid layout

  Computed with `Date`/`Calendar` stdlib only — no dependency added.
  Weeks run Monday..Sunday (`Date.day_of_week/1`'s default, and the ISO
  convention this codebase otherwise follows). Cells for the leading/
  trailing days that spill into the adjacent month are rendered — dimmed
  via `text-text-muted opacity-50` — rather than left blank; that's
  friendlier UX than a ragged first/last row, and matches how Mantine's own
  `DatePicker` renders by default.

  ## Accessibility

  The grid is a real `<table role="grid">` with a `<caption>` carrying the
  month/year — the most robust primitive for tabular date data, with
  screen-reader row/column navigation included for free. Each day is a
  `<button>`, so selection has native keyboard/click semantics without
  extra JS. Today's cell gets `aria-current="date"` plus a visible ring
  *and* bold weight — never hue alone, matching this design system's `Badge
  dot` convention. The selected cell gets `aria-pressed="true"`: each day
  button behaves as an independent toggle control reacting to a click, not
  as a member of a composite selection widget like a listbox, so
  `aria-pressed` (button toggle state) fits better here than
  `aria-selected` (composite-widget selection state).

  `min_date`/`max_date` mirror the React wrapper's Mantine bounds: days
  outside the range render `disabled` and are excluded from
  `select_event`/`phx-click` wiring, matching the React contract's "click
  outside range does not call onChange" behavior.
  """
  use Phoenix.Component
  alias GlobalCombatWeb.Components.Boutique.Button

  attr :year, :integer, required: true
  attr :month, :integer, required: true, values: 1..12
  attr :today, Date, required: true
  attr :selected, Date, default: nil
  attr :min_date, Date, default: nil
  attr :max_date, Date, default: nil
  attr :prev_event, :string, default: nil
  attr :next_event, :string, default: nil
  attr :select_event, :string, default: nil
  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  def calendar(assigns) do
    first_of_month = Date.new!(assigns.year, assigns.month, 1)

    assigns =
      assigns
      |> assign(:caption, Calendar.strftime(first_of_month, "%B %Y"))
      |> assign(:weeks, weeks_for(first_of_month))

    ~H"""
    <div id={@id} class={["inline-block", @class]} {@rest}>
      <div class="flex items-center justify-between gap-[var(--space-2)] mb-[var(--space-2)]">
        <Button.button
          :if={@prev_event}
          intent="neutral"
          phx-click={@prev_event}
          aria-label="Previous month"
        >
          ‹
        </Button.button>
        <span class="text-sm font-semibold">{@caption}</span>
        <Button.button
          :if={@next_event}
          intent="neutral"
          phx-click={@next_event}
          aria-label="Next month"
        >
          ›
        </Button.button>
      </div>

      <table role="grid" class="border-collapse">
        <caption class="sr-only">{@caption}</caption>
        <thead>
          <tr role="row">
            <th
              :for={label <- ~w(Mo Tu We Th Fr Sa Su)}
              scope="col"
              class="text-xs font-medium text-text-muted p-[var(--space-1)]"
            >
              {label}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={week <- @weeks} role="row">
            <td :for={day <- week} role="gridcell" class="p-[var(--space-1)]">
              <button
                type="button"
                class={cell_class(day, @today, @selected)}
                disabled={out_of_range?(day.date, @min_date, @max_date)}
                aria-disabled={to_string(out_of_range?(day.date, @min_date, @max_date))}
                aria-current={if Date.compare(day.date, @today) == :eq, do: "date"}
                aria-pressed={to_string(!!@selected && Date.compare(day.date, @selected) == :eq)}
                phx-click={@select_event}
                phx-value-date={Date.to_iso8601(day.date)}
              >
                {day.date.day}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # Builds Monday..Sunday week rows spanning the full grid for `first_of_month`,
  # including the leading/trailing days that spill into adjacent months.
  defp weeks_for(first_of_month) do
    days_in_month = Date.days_in_month(first_of_month)
    leading = Date.day_of_week(first_of_month) - 1
    trailing = rem(7 - rem(leading + days_in_month, 7), 7)

    for offset <- -leading..(days_in_month - 1 + trailing) do
      date = Date.add(first_of_month, offset)

      %{
        date: date,
        in_month: date.month == first_of_month.month and date.year == first_of_month.year
      }
    end
    |> Enum.chunk_every(7)
  end

  defp cell_class(day, today, selected) do
    is_today = Date.compare(day.date, today) == :eq
    is_selected = !!selected && Date.compare(day.date, selected) == :eq

    [
      "inline-flex items-center justify-center size-[var(--space-8)]",
      "rounded-[var(--radius-sm)] text-sm cursor-pointer",
      "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring",
      "disabled:opacity-40 disabled:cursor-not-allowed",
      !day.in_month && "text-text-muted opacity-50",
      is_today && "ring-1 ring-primary font-bold",
      is_selected && "bg-primary text-primary-contrast"
    ]
  end

  defp out_of_range?(date, min_date, max_date) do
    (min_date && Date.compare(date, min_date) == :lt) ||
      (max_date && Date.compare(date, max_date) == :gt) || false
  end
end

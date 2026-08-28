defmodule GlobalCombatWeb.Components.Boutique.Table do
  @moduledoc """
  Data table — LiveView mirror of `components/react/Table` (pure tokens, no
  Mishka primitive: a `<table>` has no interaction to inherit). robo-hub's
  most-used Mantine surface (403 uses; see `components/COMPONENT-MAP.md`).

  React exposes this as a compound component (`Table.Head/Body/Row/
  HeaderCell/Cell`) hung off a single `Table` function via dot-property
  assignment. HEEx has no equivalent of that — instead this module defines
  one public function component per part (`table/1`, `thead/1`, `tbody/1`,
  `tr/1`, `th/1`, `td/1`), called as `<Table.table>`, `<Table.thead>`, etc.
  once the module is aliased. The caller composes the tree directly, the
  same shape React callers already write, just via HEEx components instead
  of JSX children:

      <Table.table min_width={640}>
        <Table.thead>
          <Table.tr><Table.th>Device</Table.th></Table.tr>
        </Table.thead>
        <Table.tbody>
          <Table.tr><Table.td>Courier Scout</Table.td></Table.tr>
        </Table.tbody>
      </Table.table>

  `dense` (React: set once on the root `Table`, cascades to every row via
  Mantine's internal spacing context) has no equivalent cascade in HEEx —
  each `<Table.th>`/`<Table.td>` in the tree is a fully rendered sibling by
  the time `table/1` sees it, so there's no assign to thread a parent value
  through. `dense` is therefore exposed on `th/1` and `td/1` directly;
  callers opt in per cell (trivial with a `for` loop over columns/rows,
  which is how real tables are built anyway).

  `min_width` mirrors React's `minWidth` — set it to wrap the table in a
  horizontal-scroll container so narrow viewports scroll the table, not the
  page, instead of Mantine's `Table.ScrollContainer`.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :min_width, :integer, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table
        id={@id}
        class={["w-full border-collapse text-sm text-text", @class]}
        style={@min_width && "min-width: #{@min_width}px"}
        {@rest}
      >
        {render_slot(@inner_block)}
      </table>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def thead(assigns) do
    ~H"""
    <thead class={["border-b border-border", @class]} {@rest}>
      {render_slot(@inner_block)}
    </thead>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def tbody(assigns) do
    ~H"""
    <tbody class={@class} {@rest}>
      {render_slot(@inner_block)}
    </tbody>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def tr(assigns) do
    ~H"""
    <tr class={["border-b border-divider last:border-b-0 hover:bg-surface-muted", @class]} {@rest}>
      {render_slot(@inner_block)}
    </tr>
    """
  end

  attr :class, :any, default: nil
  attr :dense, :boolean, default: false
  attr :rest, :global

  slot :inner_block, required: true

  def th(assigns) do
    ~H"""
    <th
      class={[
        "text-left text-xs font-semibold uppercase tracking-wide text-text-muted",
        cell_padding(@dense),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </th>
    """
  end

  attr :class, :any, default: nil
  attr :dense, :boolean, default: false
  attr :rest, :global

  slot :inner_block, required: true

  def td(assigns) do
    ~H"""
    <td class={["text-text", cell_padding(@dense), @class]} {@rest}>
      {render_slot(@inner_block)}
    </td>
    """
  end

  defp cell_padding(true), do: "py-[var(--space-1)] px-[var(--space-3)]"
  defp cell_padding(false), do: "py-[var(--space-2)] px-[var(--space-3)]"
end

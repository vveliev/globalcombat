defmodule GlobalCombatWeb.Components.Boutique.TableTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Table

  test "renders real table semantics with header and body cells" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Table.table>
        <Table.thead>
          <Table.tr>
            <Table.th>Device</Table.th>
            <Table.th>Status</Table.th>
          </Table.tr>
        </Table.thead>
        <Table.tbody>
          <Table.tr>
            <Table.td>Courier Scout</Table.td>
            <Table.td>Online</Table.td>
          </Table.tr>
        </Table.tbody>
      </Table.table>
      """)

    assert html =~ "<table"
    assert html =~ "<thead"
    assert html =~ "<tbody"
    assert html =~ "<th"
    assert html =~ "<td"
    assert html =~ "Device"
    assert html =~ "Courier Scout"
  end

  test "uppercase micro-label header classes on th" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Table.table>
        <Table.thead>
          <Table.tr>
            <Table.th>Device</Table.th>
          </Table.tr>
        </Table.thead>
        <Table.tbody>
          <Table.tr>
            <Table.td>Courier Scout</Table.td>
          </Table.tr>
        </Table.tbody>
      </Table.table>
      """)

    assert html =~ "uppercase"
    assert html =~ "tracking-wide"
    assert html =~ "text-text-muted"
  end

  test "wraps in a scroll container with min-width style when min_width is set" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Table.table min_width={640}>
        <Table.thead>
          <Table.tr>
            <Table.th>Device</Table.th>
          </Table.tr>
        </Table.thead>
        <Table.tbody>
          <Table.tr>
            <Table.td>Courier Scout</Table.td>
          </Table.tr>
        </Table.tbody>
      </Table.table>
      """)

    assert html =~ "overflow-x-auto"
    assert html =~ "min-width: 640px"

    # min-width belongs on the <table> itself, not its overflow-x-auto
    # wrapper — a wrapper that refuses to shrink below min-width overflows
    # its own parent (the page) instead of scrolling internally, which is
    # the exact failure mode min_width exists to prevent.
    [_, wrapper_tag] = Regex.run(~r/(<div[^>]*overflow-x-auto[^>]*>)/, html)
    refute wrapper_tag =~ "min-width"
    assert html =~ ~r/<table[^>]*style="min-width: 640px"/
  end

  test "omits min-width style when min_width is not set" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Table.table>
        <Table.thead>
          <Table.tr>
            <Table.th>Device</Table.th>
          </Table.tr>
        </Table.thead>
        <Table.tbody>
          <Table.tr>
            <Table.td>Courier Scout</Table.td>
          </Table.tr>
        </Table.tbody>
      </Table.table>
      """)

    refute html =~ "min-width"
  end

  test "dense tightens cell padding on th/td when opted in per cell" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Table.table>
        <Table.thead>
          <Table.tr>
            <Table.th dense>Device</Table.th>
          </Table.tr>
        </Table.thead>
        <Table.tbody>
          <Table.tr>
            <Table.td dense>Courier Scout</Table.td>
          </Table.tr>
        </Table.tbody>
      </Table.table>
      """)

    assert html =~ "py-[var(--space-1)]"
  end

  test "defaults to normal (non-dense) cell padding" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Table.table>
        <Table.tbody>
          <Table.tr>
            <Table.td>Courier Scout</Table.td>
          </Table.tr>
        </Table.tbody>
      </Table.table>
      """)

    assert html =~ "py-[var(--space-2)]"
    refute html =~ "py-[var(--space-1)]"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/table.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

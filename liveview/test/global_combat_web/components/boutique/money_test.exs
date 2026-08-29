defmodule GlobalCombatWeb.Components.Boutique.MoneyTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Money

  test "never renders an amount without its currency" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Money.money amount="1,204.00" currency="CAD" />
      """)

    assert html =~ "CAD"
    assert html =~ "1,204.00"
  end

  test "distinguishes currencies for the same figure" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Money.money amount="1,000.00" currency="CAD" />
      <Money.money amount="1,000.00" currency="USD" />
      """)

    assert html =~ "CAD"
    assert html =~ "USD"
  end

  test "carries the manually entered rate that produced a converted figure — reachable by pointer and AT" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Money.money amount="1,350.00" currency="CAD" rate={%{from: "USD", value: 1.35}} />
      """)

    assert html =~ ~s(title="Converted from USD at 1.35")
    assert html =~ "Converted from USD at 1.35"
    assert html =~ "sr-only"
  end

  test "omits the rate tooltip/AT text when there is no conversion" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Money.money amount="42.00" currency="CAD" />
      """)

    refute html =~ "Converted from"
  end

  test "uses tabular figures so columns of money align" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Money.money amount="42.00" currency="CAD" />
      """)

    assert html =~ "tabular-nums"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/money.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

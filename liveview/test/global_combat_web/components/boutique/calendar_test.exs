defmodule GlobalCombatWeb.Components.Boutique.CalendarTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Calendar

  test "renders a full 6-week grid (42 day cells) for a month starting on Saturday" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Calendar.calendar year={2026} month={8} today={~D[2026-08-26]} />
      """)

    # 6 weeks * 7 days = 42 day buttons, each carrying phx-value-date.
    assert Regex.scan(~r/phx-value-date="[^"]+"/, html) |> length() == 42
  end

  test "renders a 5-week grid for February in a non-leap year (28 days)" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Calendar.calendar year={2026} month={2} today={~D[2026-02-01]} />
      """)

    assert Regex.scan(~r/phx-value-date="[^"]+"/, html) |> length() == 35
    assert html =~ "2026-02-28"
    refute html =~ "2026-02-29"
  end

  test "includes Feb 29 for a leap year and stays a 5-week grid" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Calendar.calendar year={2028} month={2} today={~D[2028-02-01]} />
      """)

    assert Regex.scan(~r/phx-value-date="[^"]+"/, html) |> length() == 35
    assert html =~ "2028-02-29"
  end

  test "marks the selected date with aria-pressed and the primary fill" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Calendar.calendar year={2026} month={8} today={~D[2026-08-26]} selected={~D[2026-08-15]} />
      """)

    assert html =~ ~s(phx-value-date="2026-08-15")
    assert html =~ "bg-primary"
    assert html =~ "text-primary-contrast"

    # the selected cell's button carries aria-pressed="true"
    assert html =~
             ~r/aria-pressed="true"[^>]*phx-value-date="2026-08-15"|phx-value-date="2026-08-15"[^>]*aria-pressed="true"/
  end

  test "marks today's cell with aria-current and a distinguishing ring, not color alone" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Calendar.calendar year={2026} month={8} today={~D[2026-08-26]} />
      """)

    assert html =~ ~s(aria-current="date")
    assert html =~ "ring-primary"
    assert html =~ "font-bold"
  end

  test "disables day cells outside the min/max range" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Calendar.calendar
        year={2026}
        month={8}
        today={~D[2026-08-26]}
        min_date={~D[2026-08-10]}
      />
      """)

    assert html =~
             ~r/phx-value-date="2026-08-05"[^>]*aria-disabled="true"|aria-disabled="true"[^>]*phx-value-date="2026-08-05"/

    assert html =~
             ~r/phx-value-date="2026-08-15"[^>]*aria-disabled="false"|aria-disabled="false"[^>]*phx-value-date="2026-08-15"/
  end

  test "month navigation buttons render only when the corresponding event attr is passed" do
    assigns = %{}

    neither =
      rendered_to_string(~H"""
      <Calendar.calendar year={2026} month={8} today={~D[2026-08-26]} />
      """)

    refute neither =~ "Previous month"
    refute neither =~ "Next month"

    both =
      rendered_to_string(~H"""
      <Calendar.calendar
        year={2026}
        month={8}
        today={~D[2026-08-26]}
        prev_event="prev_month"
        next_event="next_month"
      />
      """)

    assert both =~ ~s(phx-click="prev_month")
    assert both =~ ~s(phx-click="next_month")
    assert both =~ "Previous month"
    assert both =~ "Next month"
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/calendar.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end

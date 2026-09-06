defmodule GlobalCombatWeb.Assets.AppCssTest do
  use ExUnit.Case, async: true

  @app_css Path.expand("../../../assets/css/app.css", __DIR__)

  test "fonts.css is imported before \"tailwindcss\"" do
    content = File.read!(@app_css)

    fonts_index =
      :binary.match(content, ~s(@import "../vendor/design-boutique/fonts.css")) |> elem(0)

    tailwind_index = :binary.match(content, ~s(@import "tailwindcss")) |> elem(0)

    assert fonts_index < tailwind_index, """
    fonts.css must be imported before "tailwindcss" in app.css: Tailwind expands
    @import "tailwindcss" in place into thousands of lines of generated output, so
    any @import that comes after it lands after other CSS rules in the built file.
    CSS requires @import to precede all other rules, so browsers silently drop it
    there - meaning fonts.css's Google Fonts @import url(...) statements never fire
    and every brand falls back to system-ui.
    """
  end
end

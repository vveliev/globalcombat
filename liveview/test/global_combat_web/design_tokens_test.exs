defmodule GlobalCombatWeb.DesignTokensTest do
  @moduledoc """
  GIF-89: guards the industry-dark danger/surface pairing against regressing
  below WCAG AA 4.5:1, since re-running sync_design_boutique.sh re-copies
  variables.css from upstream and would silently revert the local override
  documented in assets/vendor/design-boutique/PROVENANCE.md.
  """
  use ExUnit.Case, async: true

  @variables_css Path.join([
                   __DIR__,
                   "..",
                   "..",
                   "assets",
                   "vendor",
                   "design-boutique",
                   "variables.css"
                 ])

  test "industry-dark --color-danger clears 4.5:1 against --color-surface" do
    css = File.read!(@variables_css)

    root_vars = extract_vars(css, ":root")
    theme_vars = extract_vars(css, ~s([data-theme="industry-dark"]))

    danger_hex = resolve(theme_vars["--color-danger"], theme_vars, root_vars)
    surface_hex = resolve(theme_vars["--color-surface"], theme_vars, root_vars)

    ratio = contrast_ratio(danger_hex, surface_hex)

    assert ratio >= 4.5,
           "industry-dark --color-danger (#{theme_vars["--color-danger"]} = #{danger_hex}) " <>
             "only reaches #{Float.round(ratio, 2)}:1 against --color-surface " <>
             "(#{theme_vars["--color-surface"]} = #{surface_hex}); WCAG AA needs >= 4.5:1"
  end

  defp extract_vars(css, selector) do
    with [_, block] <- Regex.run(~r/#{Regex.escape(selector)}\s*\{([^}]*)\}/s, css) do
      ~r/(--[\w-]+):\s*([^;]+);/
      |> Regex.scan(block)
      |> Map.new(fn [_, name, value] -> {name, String.trim(value)} end)
    end
  end

  defp resolve("var(" <> rest, theme_vars, root_vars) do
    name = rest |> String.trim_trailing(")") |> String.trim()
    theme_vars[name] || root_vars[name] || raise "unresolved token #{name}"
  end

  defp resolve(hex, _theme_vars, _root_vars), do: hex

  defp contrast_ratio(hex_a, hex_b) do
    l1 = relative_luminance(hex_a)
    l2 = relative_luminance(hex_b)
    {lighter, darker} = if l1 >= l2, do: {l1, l2}, else: {l2, l1}
    (lighter + 0.05) / (darker + 0.05)
  end

  defp relative_luminance("#" <> hex) do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex

    [r, g, b]
    |> Enum.map(fn channel ->
      c = String.to_integer(channel, 16) / 255
      if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
    end)
    |> then(fn [r, g, b] -> 0.2126 * r + 0.7152 * g + 0.0722 * b end)
  end
end

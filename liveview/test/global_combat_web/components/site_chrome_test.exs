defmodule GlobalCombatWeb.Components.SiteChromeTest do
  use GlobalCombatWeb.ConnCase, async: true

  # Below `lg:` the full 7-link sidebar used to render at full height (~273px)
  # between the topbar and page content on every page. A native
  # `<details>` disclosure collapses it to a single "Menu" row by default;
  # `lg:flex` on the nav forces it open again at `lg:` regardless of the
  # `open` attribute, so the desktop persistent sidebar is unaffected.
  #
  # Routed through a real request (rather than rendering `SiteChrome` in
  # isolation) because the log-off form's `get_csrf_token/0` depends on the
  # CSRF process state a normal plug pipeline sets up.
  test "the sidebar nav is a details disclosure, closed by default, forced open at lg:", %{
    conn: conn
  } do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "<details"
    assert html =~ ~r/<summary[^>]*class="[^"]*lg:hidden[^"]*"/
    assert html =~ ~r/<nav[^>]*class="[^"]*hidden[^"]*group-open:flex[^"]*lg:flex[^"]*"/
    refute html =~ ~r/<details[^>]*\sopen/
  end
end

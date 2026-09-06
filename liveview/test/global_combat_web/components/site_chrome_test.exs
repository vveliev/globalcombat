defmodule GlobalCombatWeb.Components.SiteChromeTest do
  use GlobalCombatWeb.ConnCase, async: true

  # Below `lg:` the full 7-link sidebar used to render at full height (~273px)
  # between the topbar and page content on every page. A single nav toggled
  # between `<details>` and `lg:flex` can't serve both breakpoints: a closed
  # `<details>` hides its content at the UA level (Chromium >=131 via
  # `::details-content { content-visibility: hidden }`, older engines via an
  # unrendered slot) regardless of an author `display` override — reproduced
  # with `checkVisibility() === false` despite a computed `display:flex` at
  # 1280px, so `lg:flex` on the nested `<nav>` never wins back the content
  # once `<details>` owns it. `SiteChrome` now renders two independent
  # branches instead: a plain `<nav class="hidden lg:flex ...">` for `lg:`
  # and above, and a `<details class="... lg:hidden">` disclosure — closed
  # by default — for below `lg:`.
  #
  # Routed through a real request (rather than rendering `SiteChrome` in
  # isolation) because the log-off form's `get_csrf_token/0` depends on the
  # CSRF process state a normal plug pipeline sets up.
  test "the sidebar renders a lg:-only nav plus a details disclosure that's hidden at lg:", %{
    conn: conn
  } do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~r/<nav[^>]*class="[^"]*\bhidden\b[^"]*\blg:flex\b[^"]*"/
    assert html =~ ~r/<details[^>]*class="[^"]*\blg:hidden\b[^"]*"/
    assert html =~ ~r/<summary[^>]*class="[^"]*\[&::-webkit-details-marker\]:hidden[^"]*"/
    refute html =~ ~r/<details[^>]*\sopen/
  end

  describe "active sidebar link" do
    # `aria-current="page"` is rendered server-side from the request path (via
    # `GlobalCombatWeb.Plugs.CurrentPath` on controller pages) so it survives a
    # LiveView patch and needs no client script.
    test "the link matching the request path carries aria-current=page, others don't", %{
      conn: conn
    } do
      html = conn |> get(~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query(~s(nav a[href="/"][aria-current="page"])) |> Enum.any?()
      refute doc |> LazyHTML.query(~s(nav a[href="/Game-Manual"][aria-current])) |> Enum.any?()

      html = conn |> get(~p"/Game-Manual") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc
             |> LazyHTML.query(~s(nav a[href="/Game-Manual"][aria-current="page"]))
             |> Enum.any?()

      refute doc |> LazyHTML.query(~s(nav a[href="/"][aria-current])) |> Enum.any?()
    end
  end

  test "the topbar exposes the theme toggle", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    doc = LazyHTML.from_document(html)

    for theme <- ~w(system light dark) do
      assert doc |> LazyHTML.query(~s(button[data-phx-theme="#{theme}"])) |> Enum.any?()
    end
  end
end

defmodule GlobalCombatWeb.ErrorHTMLTest do
  use GlobalCombatWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html inside the site chrome" do
    html = render_to_string(GlobalCombatWeb.ErrorHTML, "404", "html", [])
    assert html =~ "Error 404"
    assert html =~ "Page not found"
    assert html =~ "GLOBAL COMBAT"
    assert html =~ ~s(href="/")
  end

  test "renders 500.html inside the site chrome" do
    html = render_to_string(GlobalCombatWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Error 500"
    assert html =~ "Something went wrong"
    assert html =~ "GLOBAL COMBAT"
  end

  test "any other status falls back to the same page with Plug's status phrase" do
    html = render_to_string(GlobalCombatWeb.ErrorHTML, "403", "html", [])
    assert html =~ "Error 403"
    assert html =~ "Forbidden"
    assert html =~ "GLOBAL COMBAT"
  end

  test "an unknown route serves the styled 404 as a full document", %{conn: conn} do
    conn = get(conn, "/no-such-page")
    body = html_response(conn, 404)
    assert body =~ "<!DOCTYPE html>"
    assert body =~ ~s(href="/assets/css/app.css")
    assert body =~ "Page not found"
  end

  test "a legacy route that finds nothing serves the same styled 404", %{conn: conn} do
    assert html_response(get(conn, "/PlayerInfo"), 404) =~ "Page not found"
    assert html_response(get(conn, "/Player-Info-abc"), 404) =~ "Page not found"
    assert html_response(get(conn, "/Tournament-999999999"), 404) =~ "Page not found"
  end
end

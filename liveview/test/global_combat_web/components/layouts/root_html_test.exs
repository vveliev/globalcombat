defmodule GlobalCombatWeb.Components.Layouts.RootHtmlTest do
  use GlobalCombatWeb.ConnCase, async: true

  # root.html.heex wraps every page, so any real route exercises it —
  # PWA install metas (mobile-battle-mode.md §4.6) belong on every page,
  # not just the game screen.
  test "carries the PWA manifest link and install metas", %{conn: conn} do
    doc = get(conn, ~p"/") |> html_response(200) |> LazyHTML.from_document()

    for selector <- [
          ~s{head link[rel="manifest"][href="/manifest.webmanifest"]},
          ~s{head meta[name="apple-mobile-web-app-capable"][content="yes"]},
          ~s{head meta[name="apple-mobile-web-app-status-bar-style"][content="black-translucent"]},
          ~s{head meta[name="theme-color"][content="#416180"][media="(prefers-color-scheme: light)"]},
          ~s{head meta[name="theme-color"][content="#94bce3"][media="(prefers-color-scheme: dark)"]}
        ] do
      assert doc |> LazyHTML.query(selector) |> Enum.count() == 1, "missing #{selector}"
    end
  end
end

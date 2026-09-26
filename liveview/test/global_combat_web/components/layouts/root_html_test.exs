defmodule GlobalCombatWeb.Components.Layouts.RootHtmlTest do
  use GlobalCombatWeb.ConnCase, async: true

  # root.html.heex wraps every page, so any real route exercises it —
  # PWA install metas (mobile-battle-mode.md §4.6) belong on every page,
  # not just the game screen.
  test "carries the PWA manifest link and install metas", %{conn: conn} do
    body = get(conn, ~p"/") |> html_response(200)

    assert body =~ ~s[<link rel="manifest" href="/manifest.webmanifest">]
    assert body =~ ~s[<meta name="apple-mobile-web-app-capable" content="yes">]

    assert body =~
             ~s[<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">]

    assert body =~
             ~s[<meta name="theme-color" content="#416180" media="(prefers-color-scheme: light)">]

    assert body =~
             ~s[<meta name="theme-color" content="#94bce3" media="(prefers-color-scheme: dark)">]
  end
end

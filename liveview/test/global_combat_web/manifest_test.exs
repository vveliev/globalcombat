defmodule GlobalCombatWeb.ManifestTest do
  use GlobalCombatWeb.ConnCase, async: true

  test "GET /manifest.webmanifest serves the PWA manifest as application/manifest+json", %{
    conn: conn
  } do
    conn = get(conn, "/manifest.webmanifest")

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["application/manifest+json"]

    manifest = Jason.decode!(conn.resp_body)
    assert manifest["name"] == "Global Combat"
    assert manifest["short_name"] == "Global Combat"
    assert manifest["display"] == "standalone"
    assert manifest["start_url"] == "/"
    assert Enum.map(manifest["icons"], & &1["sizes"]) |> Enum.sort() == ["192x192", "512x512"]
  end
end

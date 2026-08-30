defmodule GlobalCombatWeb.Plugs.LegacyIntegerId do
  @moduledoc """
  Mirrors ASP.NET Core's `{id:int}` route constraint for the legacy slug
  routes (`/Game-:id`, `/Tournament-:id`, `/Player-Info-:id`). Phoenix's
  router has no built-in numeric constraint, so a non-numeric `id` would
  otherwise reach the controller as a raw string.

  `conn.params["id"]` may come from a path segment (`/Game-:id`) or, on the
  id-less `/PlayerInfo` shortcut route, from a `?id=` query string — same as
  the original `HomeController.PlayerInfo(int id)` model-bound `id` from
  either source. If `id` is present (from either source) it must parse as a
  bare integer or the request 404s, same as the old router/model binder
  rejecting it. Only when `id` is missing entirely — no path segment *and*
  no query string — is the plug a no-op.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Map.fetch(conn.params, "id") do
      :error ->
        conn

      {:ok, id_param} ->
        case Integer.parse(id_param) do
          {id, ""} -> assign(conn, :legacy_id, id)
          _ -> conn |> send_resp(404, "Not Found") |> halt()
        end
    end
  end
end

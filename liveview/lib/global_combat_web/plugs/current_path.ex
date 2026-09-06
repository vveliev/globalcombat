defmodule GlobalCombatWeb.Plugs.CurrentPath do
  @moduledoc """
  Assigns `:current_path` (the request path, no query string) so controller templates can
  hand it to `GlobalCombatWeb.Components.SiteChrome.site_chrome/1`, which marks the matching
  sidebar link `aria-current="page"`. LiveViews get the same assign from the `handle_params`
  hook in `GlobalCombatWeb.UserAuth.on_mount/4`, so both kinds of page render the marker
  server-side instead of patching it in with a script LiveView would strip on join.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts), do: assign(conn, :current_path, conn.request_path)
end

defmodule GlobalCombatWeb.GameController do
  @moduledoc """
  Legacy globalcombat.com slug routes: `/Game-:id` and `/Game-:id/:action`
  (see `Web/Controllers/GameController.cs`). Ported as thin acknowledgement
  stubs until the real game view lands in Phoenix; this ticket (GIF-31) only
  guarantees the URL shape and id survive.
  """

  use GlobalCombatWeb, :controller

  plug GlobalCombatWeb.Plugs.LegacyIntegerId when action in [:show]

  def show(conn, params) do
    action = Map.get(params, "action", "Index")
    text(conn, "Game #{conn.assigns.legacy_id} action=#{action}")
  end

  def create(conn, _params) do
    text(conn, "Create Game")
  end
end

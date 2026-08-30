defmodule GlobalCombatWeb.TourneyController do
  @moduledoc """
  Legacy globalcombat.com slug routes: `/Tournament-:id` and
  `/Create-Tournament` (see `Web/Controllers/TourneyController.cs`). Ported
  as thin acknowledgement stubs until the real tourney view lands in
  Phoenix; this ticket (GIF-31) only guarantees the URL shape and id
  survive.
  """

  use GlobalCombatWeb, :controller

  plug GlobalCombatWeb.Plugs.LegacyIntegerId when action in [:index]

  def index(conn, _params) do
    text(conn, "Tournament #{conn.assigns.legacy_id}")
  end

  def create(conn, _params) do
    text(conn, "Create Tournament")
  end
end

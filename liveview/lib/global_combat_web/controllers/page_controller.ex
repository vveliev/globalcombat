defmodule GlobalCombatWeb.PageController do
  use GlobalCombatWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

defmodule GlobalCombatWeb.HomeController do
  @moduledoc """
  Legacy globalcombat.com routes that hung off `HomeController` in the old
  ASP.NET app (see `Web/Controllers/HomeController.cs`): the `/Player-Info-:id`
  slug, `/Game-Manual`, `/Send-Message`, and the `{action}` shortcut set
  (`/Messages`, `/Stats`, `/IpAddresses`, `/GameManual`, `/OptOut`,
  `/PlayerInfo`, `/Chat`, `/LoadChatMessages`, `/CloseChatWindow`,
  `/SendMessage`). `/OptOut` (email preferences) and `/IpAddresses`
  (moderation) are linked from mail sent years ago and stay load-bearing.

  Ported as thin acknowledgement stubs until the real views land in
  Phoenix; this ticket (GIF-31) only guarantees the URL shape and id
  survive.
  """

  use GlobalCombatWeb, :controller

  plug GlobalCombatWeb.Plugs.LegacyIntegerId when action in [:player_info]

  def player_info(conn, _params) do
    case conn.assigns[:legacy_id] do
      nil -> text(conn, "PlayerInfo")
      id -> text(conn, "PlayerInfo #{id}")
    end
  end

  def game_manual(conn, _params), do: text(conn, "GameManual")
  def send_message(conn, _params), do: text(conn, "SendMessage")
  def messages(conn, _params), do: text(conn, "Messages")
  def stats(conn, _params), do: text(conn, "Stats")
  def ip_addresses(conn, _params), do: text(conn, "IpAddresses")
  def opt_out(conn, _params), do: text(conn, "OptOut")
  def chat(conn, _params), do: text(conn, "Chat")
  def load_chat_messages(conn, _params), do: text(conn, "LoadChatMessages")
  def close_chat_window(conn, _params), do: text(conn, "CloseChatWindow")
end

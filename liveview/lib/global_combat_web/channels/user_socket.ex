defmodule GlobalCombatWeb.UserSocket do
  @moduledoc """
  Transport for the chat channel (GIF-33) — the Phoenix Channel analogue of the legacy
  `GameHub` SignalR connection (`Web/wwwroot/Global.js`'s `new signalR.HubConnectionBuilder()`).

  Auth mirrors the classic Phoenix-channel pattern rather than reading the Plug session
  cookie directly out of `connect_info`: `GlobalCombatWeb.UserAuth.fetch_current_account/2`
  signs a short-lived `Phoenix.Token` (assign `:chat_token`) into every logged-in page, the
  client passes it as a socket connect param, and it's verified here. This avoids depending on
  the session cookie's serialization format surviving the round trip through the socket
  transport, at the cost of a page reload being needed after a fresh login before chat
  connects (the token is only minted on the next page render).
  """

  use Phoenix.Socket

  channel "chat:*", GlobalCombatWeb.ChatChannel

  @token_salt "chat socket"
  @max_age_seconds 86_400

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(socket, @token_salt, token, max_age: @max_age_seconds) do
      {:ok, account_id} -> {:ok, assign(socket, :account_id, account_id)}
      {:error, _reason} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.account_id}"
end

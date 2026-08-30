defmodule GlobalCombatWeb.ChatChannel do
  @moduledoc """
  Real-time push half of player-to-player messaging (GIF-33) — the Phoenix Channel analogue of
  the legacy `GameHub`'s per-session SignalR group (`Web/GameHub.cs`'s `SendMessage`, pushed to
  a group keyed by the recipient's `HttpContext.Session.Id`).

  Each logged-in account joins exactly one topic, `"chat:<their own account id>"` — join is
  rejected unless it matches the account id embedded in the socket's verified token
  (`GlobalCombatWeb.UserSocket`), so one account can never eavesdrop on another's topic.
  `GlobalCombat.Messaging.send_message/4` broadcasts `"receive_message"` to this topic when a
  DM arrives and `GlobalCombat.Presence` shows the recipient connected.

  This establishes the `"chat:<id>"` topic convention the GIF-33 issue asks the game board to
  share rather than inventing its own transport — GIF-30's board should broadcast turn/board
  events on `"game:<id>"` on this same endpoint, mirroring the legacy `"Game-{id}"` SignalR
  group.
  """

  use GlobalCombatWeb, :channel

  alias GlobalCombat.{Accounts, Presence}

  @impl true
  def join("chat:" <> account_id_str, _payload, socket) do
    if socket.assigns.account_id == String.to_integer(account_id_str) do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    account_id = socket.assigns.account_id
    name = with %{name: name} <- Accounts.get_account_including_disabled(account_id), do: name

    {:ok, _ref} =
      Presence.track(self(), Presence.lobby_topic(), to_string(account_id), %{name: name})

    {:noreply, socket}
  end
end

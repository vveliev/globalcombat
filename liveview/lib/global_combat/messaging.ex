defmodule GlobalCombat.Messaging do
  @moduledoc """
  Player-to-player messaging and the chat push it shares with the game board's PubSub design
  (per the GIF-33 issue). Ports `Web/Models/GameServer.cs`'s `SendMessage` and
  `Web/Controllers/HomeController.cs`'s `LoadMessages`.

  Real-time delivery: `send_message/4` broadcasts on `"chat:<destination_id>"` via
  `GlobalCombatWeb.Endpoint` when the recipient is present (tracked by
  `GlobalCombatWeb.ChatChannel` on join, checked with `GlobalCombat.Presence`) — the Phoenix
  analogue of the legacy `GameHub.SendMessage` push to the recipient's SignalR session group.
  This establishes the `"chat:<account_id>"` topic convention for DMs; the game board (GIF-30)
  should reuse the same `Endpoint` with a `"game:<id>"` convention for board-wide pushes
  (turn run, forced reload), mirroring the legacy `"Game-{id}"` SignalR group, rather than
  inventing a separate transport. Offline recipients get an email instead, exactly as
  `GameServer.SendMessage` did — only when `forward_emails == :all`, matching the legacy gate
  precisely (`:all_game`/`:game_starts` don't cover plain messages there either).

  `destination_id <= 0` is the legacy game-forum-broadcast sentinel (`-game.Id`, written by
  `GameServer.OnMessage`) — this module still inserts the row for it (matching `SendMessage`'s
  unconditional insert) but never pushes/emails for it (matching its `if (destinationId > 0)`
  gate). Broadcasting game-forum chat to a `"game:<id>"` topic is GIF-30's job.
  """

  import Ecto.Query

  alias GlobalCombat.Accounts.{Account, Notifier}
  alias GlobalCombat.Messaging.Message
  alias GlobalCombat.{Presence, Repo}
  alias GlobalCombatWeb.Endpoint

  @doc """
  Ports `HomeController.LoadMessages` — the last 100 messages sent to or from `account_id`,
  most recent first, with sender/recipient names. The inner joins against `account` (mirroring
  the legacy SQL's `join account as fromAccount`/`toAccount`) silently exclude game-forum rows
  (negative `to_id`) exactly as the legacy join did, since no account has a negative id.
  """
  def list_messages_for_account(account_id) do
    from(m in Message,
      join: from_a in Account,
      on: from_a.id == m.from_id,
      join: to_a in Account,
      on: to_a.id == m.to_id,
      where: m.to_id == ^account_id or m.from_id == ^account_id,
      order_by: [desc: m.id],
      limit: 100,
      select: %{
        id: m.id,
        to_id: m.to_id,
        from_id: m.from_id,
        from_name: from_a.name,
        to_name: to_a.name,
        text: m.text,
        sent_at: m.sent_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Ports `HomeController.LoadChatMessages` — the last 20 messages between `account_id` and
  `partner_id`, chronological (oldest first, matching the JS client's `.reverse()`).
  """
  def list_chat_history(account_id, partner_id) do
    from(m in Message,
      where:
        (m.to_id == ^partner_id and m.from_id == ^account_id) or
          (m.to_id == ^account_id and m.from_id == ^partner_id),
      order_by: [desc: m.id],
      limit: 20,
      select: %{from_id: m.from_id, text: m.text}
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc "Ports `GameServer.SendMessage(db, destinationId, sourceId, sourceName, text)`."
  def send_message(destination_id, source_id, source_name, text) do
    {:ok, message} =
      %Message{}
      |> Message.changeset(%{
        to_id: destination_id,
        from_id: source_id,
        sent_at: DateTime.utc_now(:second),
        text: text
      })
      |> Repo.insert()

    if destination_id > 0 do
      deliver(destination_id, source_id, source_name, text)
    end

    message
  end

  defp deliver(destination_id, source_id, source_name, text) do
    if Map.has_key?(Presence.list(Presence.lobby_topic()), to_string(destination_id)) do
      Endpoint.broadcast("chat:#{destination_id}", "receive_message", %{
        source_id: source_id,
        source_name: source_name,
        text: text
      })
    else
      case Repo.get(Account, destination_id) do
        %Account{forward_emails: :all} = account ->
          Notifier.deliver_new_message(account, source_name, text)

        _ ->
          :ok
      end
    end
  end
end

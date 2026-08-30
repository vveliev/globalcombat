defmodule GlobalCombat.Games.PubSub do
  @moduledoc """
  Port of `Web/GameHub.cs` (GIF-30): the SignalR hub's two group kinds and five
  broadcast events, as `Phoenix.PubSub` topics/messages.

  ## Group -> topic mapping

  `GameHub.OnConnectedAsync` put every connection in two SignalR groups:

    * the ASP.NET session id (`Context.GetHttpContext().Session.Id`) — used to
      deliver a message/notification to one specific logged-in user, wherever
      they're connected. Phoenix has no server-side session-id-keyed group
      primitive to mirror 1:1, and an ASP.NET session id isn't a stable
      identity across reconnects the way it was in the legacy app anyway — the
      thing GameHub actually wanted was "reach this account", so this port
      keys that topic by `account_id` instead (`account_topic/1`). That is a
      *strictly* more useful primitive than the original (delivery survives a
      reconnect or a second open tab) and account id is exactly what
      `Account.SessionKey` was a proxy for at every call site
      (`GameServer.cs`'s `SendMessage`/`OnRunTurn` both resolve `SessionKey`
      from an `Account` they already have in hand).
    * `"Game-" <> gameId` (joined explicitly via `SetGroup`, and opportunistically
      re-derived from the `Referer` header on connect) — becomes `game_topic/1`.

  The `"ProtoGame-"` prefix in `OnConnectedAsync` is dead: nothing ever calls
  `SetGroup`-equivalent for it, and no client code ever joins/broadcasts to a
  `ProtoGame-` group (grepped `Web/wwwroot/**/*.js` and every `.cs` file —
  the only occurrence of the string in the whole repo is that one dead
  `if` branch in `GameHub.cs` itself). Not ported.

  ## Event -> broadcast mapping

  Each `GameHub.*` static method becomes a `broadcast_*/N` function here that
  sends a tagged tuple to the topic's subscribers; `GameLive` (and any other
  LiveView subscribed to the topic) pattern-matches the tuple in
  `handle_info/2`. The tags are named after the original SignalR client
  events they replace, so the mapping stays traceable:

    * `GameHub.Refresh`         -> `broadcast_reload/1`             -> `:reload`
    * `GameHub.Say`             -> `broadcast_add_message/2`        -> `{:add_message, message}`
    * `GameHub.SetDone`         -> `broadcast_set_done/2`           -> `{:set_done, player_number}`
    * `GameHub.SendMessage`     -> `broadcast_receive_message/4`    -> `{:receive_message, source_id, source_name, text}`
    * `GameHub.SendNotification`-> `broadcast_notification/4`       -> `{:notification, title, text, target_uri}`

  One deliberate departure from the original: `GameHub.Say` broadcast pre-rendered
  HTML (`Message.Print()`, built with `StringBuilder` + `Html.Raw` on the client) —
  fine for a same-origin SignalR client that trusted its own server completely, but
  worth not carrying forward verbatim into a rewrite whose brief explicitly calls out
  leak/integrity risk. `broadcast_add_message/2` instead sends the structured message
  (`%{source_id, source_name, text, sent}`); `GameLive`'s HEEx template interpolates
  `text` normally and gets HTML-escaping for free.
  """

  @pubsub GlobalCombat.PubSub

  @doc "Topic for a game's board — was SignalR group `\"Game-\" <> game_id`."
  def game_topic(game_id), do: "game:#{game_id}"

  @doc "Topic for one logged-in account's private messages/notifications — was the SignalR session-id group."
  def account_topic(account_id), do: "account:#{account_id}"

  @doc "Subscribes the calling process to `game_id`'s board topic."
  def subscribe_game(game_id), do: Phoenix.PubSub.subscribe(@pubsub, game_topic(game_id))

  @doc "Subscribes the calling process to `account_id`'s private topic."
  def subscribe_account(account_id),
    do: Phoenix.PubSub.subscribe(@pubsub, account_topic(account_id))

  @doc "Port of `GameHub.Refresh` — tells every socket on the game board to re-fetch and re-render state."
  def broadcast_reload(game_id) do
    Phoenix.PubSub.broadcast(@pubsub, game_topic(game_id), :reload)
  end

  @doc "Port of `GameHub.Say` — a forum/chat message visible to everyone on the game board."
  def broadcast_add_message(game_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, game_topic(game_id), {:add_message, message})
  end

  @doc "Port of `GameHub.SetDone` — cheap incremental update, no full reload needed."
  def broadcast_set_done(game_id, player_number) do
    Phoenix.PubSub.broadcast(@pubsub, game_topic(game_id), {:set_done, player_number})
  end

  @doc "Port of `GameHub.SendMessage` — a private direct message delivered to one account."
  def broadcast_receive_message(account_id, source_id, source_name, text) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      account_topic(account_id),
      {:receive_message, source_id, source_name, text}
    )
  end

  @doc "Port of `GameHub.SendNotification` — a private toast/desktop-notification delivered to one account."
  def broadcast_notification(account_id, title, text, target_uri \\ "") do
    Phoenix.PubSub.broadcast(
      @pubsub,
      account_topic(account_id),
      {:notification, title, text, target_uri}
    )
  end
end

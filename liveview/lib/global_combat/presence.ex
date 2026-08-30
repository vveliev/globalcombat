defmodule GlobalCombat.Presence do
  @moduledoc """
  Tracks which accounts currently have a live chat connection — the Phoenix-idiomatic
  replacement for `GameServer.OnlineAccounts` (`Web/Models/GameServer.cs:40`, a hand-rolled
  locked `List<Account>`). Used by `GlobalCombatWeb.ChatChannel` (tracks on join) and
  `GlobalCombat.Messaging` (checks presence to decide push-vs-email for a DM) and by
  `HomeController.index` for the "Players Currently Online" list.
  """

  use Phoenix.Presence,
    otp_app: :global_combat,
    pubsub_server: GlobalCombat.PubSub

  @lobby_topic "presence:lobby"

  @doc "Topic every connected `GlobalCombatWeb.ChatChannel` tracks itself on, for the sitewide online-accounts roster."
  def lobby_topic, do: @lobby_topic

  @doc "Ports `WebGame.GameServer.OnlineAccounts` (`Web/Models/GameServer.cs:40`) for `HomeController.index`'s 'Players Currently Online' list."
  def list_online_accounts do
    @lobby_topic
    |> list()
    |> Enum.map(fn {id_str, %{metas: [meta | _]}} ->
      %{id: String.to_integer(id_str), name: meta[:name]}
    end)
    |> Enum.sort_by(& &1.name)
  end
end

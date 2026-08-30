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

  @doc """
  Ports `WebGame.GameServer.OnlineAccounts` (`Web/Models/GameServer.cs:40`) for `HomeController.index`'s
  'Players Currently Online' list.

  `GameServer.OnlineAccounts` gains an account the instant its session is established
  (`AccountController.SetSession`, `Web/Controllers/AccountController.cs:229-243`) and keeps it there for
  the whole session, regardless of any live connection. Our presence tracking, by contrast, only starts
  once the browser's chat socket finishes its async `ChatChannel` join (`GlobalCombatWeb.ChatChannel`),
  which hasn't happened yet on the very first server-rendered page after login/registration — so the
  logged-in viewer would otherwise be missing from their own "currently online" list (GIF-75). Passing
  `current_account` here backfills that gap by treating the viewer as online unconditionally, same as
  the legacy session-scoped list did.
  """
  def list_online_accounts(current_account \\ nil) do
    accounts =
      @lobby_topic
      |> list()
      |> Enum.map(fn {id_str, %{metas: [meta | _]}} ->
        %{id: String.to_integer(id_str), name: meta[:name]}
      end)

    accounts =
      if current_account && not Enum.any?(accounts, &(&1.id == current_account.id)) do
        [%{id: current_account.id, name: current_account.name} | accounts]
      else
        accounts
      end

    Enum.sort_by(accounts, & &1.name)
  end
end

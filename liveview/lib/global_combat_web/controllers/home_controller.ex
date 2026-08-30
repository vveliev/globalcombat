defmodule GlobalCombatWeb.HomeController do
  @moduledoc """
  The home, stats, messaging and chat surfaces (GIF-33) — ports
  `Web/Controllers/HomeController.cs` (314 lines) and its views (`Home/Index`, `Stats`,
  `Messages`, `PlayerInfo`, `IpAddresses`, `OptOut`, `GameManual`).

  Chat (`Chat`/`LoadChatMessages`/`CloseChatWindow`/`SendMessage`) is pushed over
  `GlobalCombatWeb.ChatChannel` — see its moduledoc for the `"chat:<account_id>"` PubSub
  convention this establishes for the game board (GIF-30) to share.

  Two deliberate deviations from the legacy behavior, both security-motivated (not silently
  dropped — see `docs/schema-map.md`'s own precedent of flagging rather than hiding issues):

    * `ip_addresses/2` and `player_info/2`'s `ShowLoginHistory` branch are admin-gated here.
      The legacy actions had **no** auth check at all — any visitor could page through any
      account's login IP/browser history via a query param. That's a privacy leak, not a
      feature worth preserving byte-for-byte.
    * `close_chat_window/2` actually persists the removal (see
      `GlobalCombatWeb.UserAuth.remove_open_chat_window/3`'s doc for the legacy bug this fixes).
  """

  use GlobalCombatWeb, :controller

  alias GlobalCombat.{Accounts, Games, Messaging, Presence, Stats, Tourneys}
  alias GlobalCombatWeb.{GameManual, UserAuth}

  plug GlobalCombatWeb.Plugs.LegacyIntegerId when action in [:player_info]

  plug :require_login
       when action in [:messages, :chat, :load_chat_messages, :close_chat_window, :send_message]

  plug :require_admin when action in [:stats, :ip_addresses]

  @doc "Ports `HomeController.Index` (`Web/Controllers/HomeController.cs:16-55`)."
  def index(conn, _params) do
    account = conn.assigns.current_account

    assigns = %{
      new_games: Games.list_new_games(),
      open_tourneys: Tourneys.list_open_tourneys(),
      online_accounts: Presence.list_online_accounts(account)
    }

    assigns =
      if account do
        Map.merge(assigns, %{
          player_games: Games.list_player_games(account.id),
          invited_games: Games.list_invited_games(account.id),
          recent_tourneys: Tourneys.list_recent_tourneys_for_account(account.id)
        })
      else
        assigns
      end

    render(conn, :index, assigns)
  end

  @doc "Ports `HomeController.GameManual` — content carried across verbatim, see `GlobalCombatWeb.GameManual`."
  def game_manual(conn, _params) do
    render(conn, :game_manual, manual_html: GameManual.html())
  end

  @doc "Ports `HomeController.Stats` (admin-only, unchanged from legacy). No `ForceAll` — see moduledoc."
  def stats(conn, _params) do
    render(conn, :stats, overview: Stats.overview())
  end

  @doc "Ports `HomeController.Messages` / `LoadMessages`."
  def messages(conn, _params) do
    account = conn.assigns.current_account

    render(conn, :messages,
      messages: Messaging.list_messages_for_account(account.id),
      viewer_id: account.id
    )
  end

  @doc "Ports `HomeController.IpAddresses` (admin-gated in this port, see moduledoc)."
  def ip_addresses(conn, params) do
    ip = present(params["IPAddress"])
    logins = ip && Accounts.list_logins_for_ip(ip)
    render(conn, :ip_addresses, ip_address: ip, logins: logins)
  end

  @doc "Ports `HomeController.PlayerInfo` (`Web/Controllers/HomeController.cs:75-108`)."
  def player_info(conn, params) do
    id = conn.assigns[:legacy_id]

    if is_nil(id) or id <= 0 do
      send_resp(conn, 404, "Not Found")
    else
      case Accounts.get_account_including_disabled(id) do
        nil ->
          send_resp(conn, 404, "Not Found")

        account ->
          render_player_info(conn, account, id, params)
      end
    end
  end

  defp render_player_info(conn, account, id, params) do
    viewer = conn.assigns.current_account
    viewer_is_admin = viewer != nil and viewer.admin

    {account, error_message} =
      if viewer_is_admin and param_set?(params, "KillAccount") do
        {:ok, disabled} = Accounts.disable_account(account, viewer.id)
        {disabled, "Account Disabled"}
      else
        {account, nil}
      end

    all_games? = param_set?(params, "AllGames")
    games = if id > 1, do: Games.list_player_games(id, all_games: all_games?), else: []

    logins =
      if viewer_is_admin and param_set?(params, "ShowLoginHistory") do
        Accounts.list_logins_for_account(id)
      end

    render(conn, :player_info,
      account: account,
      viewer: viewer,
      games: games,
      all_games?: all_games?,
      logins: logins,
      error_message: error_message,
      online?: Presence.list_online_accounts() |> Enum.any?(&(&1.id == account.id))
    )
  end

  @doc "Ports `HomeController.OptOut` (both the GET confirm form and the POST that flips the flag)."
  def opt_out(%{method: "POST"} = conn, params) do
    account_id = parse_int(params["Account"])
    key = parse_int(params["Key"])

    cond do
      is_nil(account_id) or is_nil(key) ->
        render(conn, :opt_out,
          error_message: "Missing account or opt out key.",
          account_id: nil,
          key: nil
        )

      true ->
        case Accounts.opt_out(account_id, key) do
          {:ok, _account} ->
            render(conn, :opt_out,
              error_message: "You will no longer receive emails about new features.",
              account_id: nil,
              key: nil
            )

          {:error, :not_found} ->
            render(conn, :opt_out, error_message: "Invalid account.", account_id: nil, key: nil)

          {:error, :bad_key} ->
            render(conn, :opt_out,
              error_message: "Incorrect opt out key.",
              account_id: nil,
              key: nil
            )
        end
    end
  end

  def opt_out(conn, params) do
    account_id = parse_int(params["Account"])
    key = parse_int(params["Key"])

    if is_nil(account_id) or is_nil(key) do
      render(conn, :opt_out,
        error_message: "Missing account or opt out key.",
        account_id: nil,
        key: nil
      )
    else
      render(conn, :opt_out, error_message: nil, account_id: account_id, key: key)
    end
  end

  @doc "Ports `HomeController.Chat` — HTTP send side of a DM; the push side is `GlobalCombatWeb.ChatChannel`."
  def chat(conn, params) do
    account = conn.assigns.current_account
    target_id = parse_int(params["targetId"])
    message = params["message"]

    if target_id && present(message) do
      Messaging.send_message(target_id, account.id, account.name, message)
    end

    send_resp(conn, 200, "")
  end

  @doc "Ports `HomeController.LoadChatMessages`."
  def load_chat_messages(conn, params) do
    account = conn.assigns.current_account
    target_id = parse_int(params["targetId"])
    target_name = params["targetName"] || ""

    history =
      account.id
      |> Messaging.list_chat_history(target_id)
      |> Enum.map(fn %{from_id: from_id, text: text} ->
        %{name: if(from_id == account.id, do: "Me", else: target_name), text: text}
      end)

    conn
    |> UserAuth.add_open_chat_window(target_id, target_name)
    |> json(history)
  end

  @doc "Ports `HomeController.CloseChatWindow` (and fixes its persistence bug, see moduledoc)."
  def close_chat_window(conn, params) do
    conn
    |> UserAuth.remove_open_chat_window(params["targetId"], params["targetName"])
    |> send_resp(200, "")
  end

  @doc "Ports `HomeController.SendMessage` — the PlayerInfo 'Contact' form."
  def send_message(conn, params) do
    account = conn.assigns.current_account
    target_id = parse_int(params["AccountId"])
    message = params["Message"]

    if target_id && present(message) do
      Messaging.send_message(target_id, account.id, account.name, message)
    end

    redirect(conn, to: ~p"/Player-Info-#{target_id || -1}")
  end

  defp require_login(conn, _opts) do
    if conn.assigns[:current_account] do
      conn
    else
      conn |> redirect(to: ~p"/") |> halt()
    end
  end

  defp require_admin(conn, _opts) do
    case conn.assigns[:current_account] do
      %{admin: true} -> conn
      _ -> conn |> redirect(to: ~p"/") |> halt()
    end
  end

  # Ports `BaseController.IsSet` — present in params and non-empty (matches
  # `GetField` returning `null` for an absent/empty form or query value).
  defp param_set?(params, key), do: present(params[key]) != nil

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value), do: value

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end
end

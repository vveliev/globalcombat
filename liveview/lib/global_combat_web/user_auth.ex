defmodule GlobalCombatWeb.UserAuth do
  @moduledoc """
  Session-cookie authentication, replacing `Web/Program.cs`'s ASP.NET cookie auth
  (`LoginPath = /Account/LogOn`) plus its 60-minute in-memory session cache.

  Phoenix's own signed session cookie (`GlobalCombatWeb.Endpoint`'s `@session_options`) plays
  the role of the ASP.NET session here: the account id lives in the session, and
  `fetch_current_account/2` resolves it to an `%Account{}` on every request. There is no
  separate server-side session store to expire — the cookie itself carries `:max_age` via the
  endpoint's session options, matching the legacy 60-minute-ish sliding window closely enough
  for this port without inventing a token table the legacy app never had.
  """

  use GlobalCombatWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias GlobalCombat.Accounts

  @account_id_key :account_id

  @doc "Logs `account` in: renews the session (fixation protection) and stores the account id."
  def log_in_account(conn, account, params \\ %{}) do
    account_id = account.id
    return_to = params["return_to"] || ~p"/"

    conn
    |> renew_session()
    |> put_session(@account_id_key, account_id)
    |> redirect(to: return_to)
  end

  @doc "Ports `AccountController.LogOff` — clears the whole session, same as `HttpContext.Session.Clear()`."
  def log_out_account(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  @doc "Plug: assigns `:current_account` from the session, or `nil` if not logged in / stale."
  def fetch_current_account(conn, _opts) do
    account =
      case get_session(conn, @account_id_key) do
        nil -> nil
        account_id -> Accounts.get_account(account_id)
      end

    conn
    |> assign(:current_account, account)
    |> assign(:chat_token, account && chat_token(conn, account.id))
  end

  @doc "Signs the token `GlobalCombatWeb.UserSocket` verifies to authorize a chat channel join."
  def chat_token(conn_or_endpoint, account_id),
    do: Phoenix.Token.sign(conn_or_endpoint, "chat socket", account_id)

  @open_chat_windows_key :open_chat_windows

  @doc """
  Plug: assigns `:open_chat_windows` (a list of `"{account_id}|{account_name}"` strings) from
  the session, `[]` if unset. Ports `BaseController.OpenChatWindows`
  (`Web/Controllers/BaseController.cs:90`) — legacy `_Layout.cshtml` replayed this list into
  every page (`$.popupChat(...)` per entry) so chat windows survive full page reloads; this
  port's root layout does the same (see `root.html.heex`).
  """
  def fetch_open_chat_windows(conn, _opts) do
    assign(conn, :open_chat_windows, get_session(conn, @open_chat_windows_key) || [])
  end

  @doc "Ports `BaseController.AddChatWindow` — adds `\"{id}|{name}\"` to the session list, deduped."
  def add_open_chat_window(conn, target_id, target_name) do
    window_id = "#{target_id}|#{target_name}"
    windows = get_session(conn, @open_chat_windows_key) || []
    windows = if window_id in windows, do: windows, else: windows ++ [window_id]
    put_session(conn, @open_chat_windows_key, windows)
  end

  @doc """
  Ports (and fixes) `HomeController.CloseChatWindow` — the legacy action mutated the list
  returned by the `OpenChatWindows` getter in place but never called `SetOpenChatWindows`, so
  closing a chat window never actually persisted across a reload (GIF-33 research flagged this
  as a bug, not a behavior to preserve). This port persists the removal.
  """
  def remove_open_chat_window(conn, target_id, target_name) do
    window_id = "#{target_id}|#{target_name}"
    windows = get_session(conn, @open_chat_windows_key) || []
    put_session(conn, @open_chat_windows_key, List.delete(windows, window_id))
  end

  @doc "Plug: redirects logged-in visitors away from LogOn/Register, same intent as the legacy `RedirectToAction` after a successful LogOn."
  def redirect_if_account_is_authenticated(conn, _opts) do
    if conn.assigns[:current_account] do
      conn |> redirect(to: ~p"/") |> halt()
    else
      conn
    end
  end

  @doc "Plug: ports the `if (!LoggedIn) return Redirect(\"/\");` guard used by Settings/Contact."
  def require_authenticated_account(conn, _opts) do
    if conn.assigns[:current_account] do
      conn
    else
      conn
      |> put_flash(:error, "You must log on to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/account/log-on")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :account_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end

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

    assign(conn, :current_account, account)
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

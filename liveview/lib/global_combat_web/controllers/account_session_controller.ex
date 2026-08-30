defmodule GlobalCombatWeb.AccountSessionController do
  use GlobalCombatWeb, :controller

  alias GlobalCombat.Accounts

  def new(conn, _params) do
    render(conn, :new, error_message: nil, login: nil)
  end

  # Ports `AccountController.LogOn(LogOnModel, returnUrl)` / `AccountController.Login`.
  def create(conn, %{"account" => %{"login" => login, "password" => password}} = params) do
    case Accounts.authenticate_account(login, password) do
      {:ok, account} ->
        {:ok, account} =
          Accounts.record_login(account,
            ip_address: remote_ip(conn),
            user_agent: user_agent(conn)
          )

        conn
        |> put_flash(:info, "Welcome back, #{account.name}.")
        |> GlobalCombatWeb.UserAuth.log_in_account(account, params)

      {:error, reason} ->
        # Mirrors `AccountController.LogOn` retaining the submitted login name in
        # ModelState after a failed attempt — only the password is cleared.
        render(conn, :new, error_message: error_message(reason), login: login)
    end
  end

  # Ports `AccountController.LogOff` — `HttpContext.Session.Clear()`.
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> GlobalCombatWeb.UserAuth.log_out_account()
  end

  defp error_message(:not_found), do: "Unknown login name or email address."
  defp error_message(:disabled), do: "That account has been permanently disabled."
  defp error_message(:bad_password), do: "Bad Password"

  defp remote_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp user_agent(conn) do
    conn |> get_req_header("user-agent") |> List.first()
  end
end

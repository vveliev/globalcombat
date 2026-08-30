defmodule GlobalCombatWeb.AccountResetPasswordController do
  use GlobalCombatWeb, :controller

  alias GlobalCombat.Accounts
  alias GlobalCombat.Accounts.Notifier

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  # Ports `AccountController.LostPassword` / `ResetPassword(email)`. Unlike the legacy path,
  # the generated password is hashed before it's written (ADR-0002) — only the outgoing email
  # ever carries it in cleartext, same as before.
  def create(conn, %{"account" => %{"login" => login}}) do
    if String.trim(login) == "" do
      render(conn, :new, error_message: "Invalid login name or email address.")
    else
      case Accounts.reset_password(login) do
        {:ok, account, new_password} ->
          Notifier.deliver_reset_password(account, new_password)

          conn
          |> put_flash(:info, "A new password was sent to your email.")
          |> redirect(to: ~p"/account/log-on")

        {:error, :not_found} ->
          render(conn, :new, error_message: "Account not found.")
      end
    end
  end
end

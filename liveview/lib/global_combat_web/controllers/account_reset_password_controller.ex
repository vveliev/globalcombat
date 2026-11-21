defmodule GlobalCombatWeb.AccountResetPasswordController do
  use GlobalCombatWeb, :controller

  alias GlobalCombat.{Accounts, RateLimiter}
  alias GlobalCombat.Accounts.Notifier

  @max_requests 10

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  # Ports `AccountController.LostPassword` / `ResetPassword(email)`, but instead of replacing
  # the password for whoever typed a name, it emails a one-time link to the account's owner.
  # The response is identical whether or not the account exists.
  def create(conn, %{"account" => %{"login" => login}}) do
    keys = [{:reset_ip, remote_ip(conn)}, {:reset, String.downcase(String.trim(login))}]

    cond do
      String.trim(login) == "" ->
        render(conn, :new, error_message: "Invalid login name or email address.")

      not Enum.all?(keys, &RateLimiter.allow?(&1, @max_requests)) ->
        conn
        |> put_status(429)
        |> render(:new, error_message: "Too many requests. Try again in a few minutes.")

      true ->
        Enum.each(keys, &RateLimiter.hit/1)

        with {:ok, account, token} <- Accounts.request_password_reset(login) do
          Notifier.deliver_reset_password(account, url(~p"/account/reset-password/#{token}"))
        end

        conn
        |> put_flash(
          :info,
          "If an account matches, a password reset link was sent to its email address."
        )
        |> redirect(to: ~p"/account/log-on")
    end
  end

  def edit(conn, %{"token" => token}) do
    case Accounts.get_account_by_reset_token(token) do
      nil -> invalid_token(conn)
      _account -> render(conn, :edit, token: token, error_message: nil)
    end
  end

  def update(conn, %{"token" => token, "account" => %{"password" => password} = params}) do
    if password != params["password_confirmation"] do
      render(conn, :edit, token: token, error_message: "The passwords you entered do not match.")
    else
      case Accounts.reset_password_with_token(token, password) do
        {:ok, _account} ->
          conn
          |> put_flash(:info, "Your password was changed. You can log on now.")
          |> redirect(to: ~p"/account/log-on")

        {:error, :invalid_token} ->
          invalid_token(conn)

        {:error, %Ecto.Changeset{}} ->
          render(conn, :edit,
            token: token,
            error_message: "Password must be at least five letters."
          )
      end
    end
  end

  defp invalid_token(conn) do
    conn
    |> put_flash(:error, "That reset link is invalid or has expired.")
    |> redirect(to: ~p"/account/reset-password")
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end

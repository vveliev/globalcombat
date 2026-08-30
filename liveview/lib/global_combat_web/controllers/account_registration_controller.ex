defmodule GlobalCombatWeb.AccountRegistrationController do
  use GlobalCombatWeb, :controller

  alias GlobalCombat.Accounts
  alias GlobalCombat.Accounts.Account

  def new(conn, _params) do
    render(conn, :new, changeset: Account.registration_changeset(%Account{}, %{}))
  end

  # Ports `AccountController.Register(RegisterModel)` / `BaseController.CreateAccount`.
  def create(conn, %{"account" => account_params}) do
    case Accounts.register_account(account_params) do
      {:ok, account} ->
        {:ok, account} =
          Accounts.record_login(account,
            ip_address: conn.remote_ip |> :inet.ntoa() |> to_string(),
            user_agent: conn |> get_req_header("user-agent") |> List.first()
          )

        conn
        |> put_flash(:info, "Welcome, #{account.name}!")
        |> GlobalCombatWeb.UserAuth.log_in_account(account)

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end

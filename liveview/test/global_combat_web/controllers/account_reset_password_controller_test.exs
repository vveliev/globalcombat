defmodule GlobalCombatWeb.AccountResetPasswordControllerTest do
  use GlobalCombatWeb.ConnCase, async: true

  import Swoosh.TestAssertions
  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Accounts

  describe "GET /account/reset-password" do
    test "renders the lost password form", %{conn: conn} do
      conn = get(conn, ~p"/account/reset-password")
      assert html_response(conn, 200) =~ "Lost Password"
    end
  end

  describe "POST /account/reset-password" do
    test "generates a new password, emails it, and lets the account log in with it", %{conn: conn} do
      account = account_fixture()

      conn = post(conn, ~p"/account/reset-password", account: %{login: account.name})

      assert redirected_to(conn) == ~p"/account/log-on"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "A new password was sent"

      assert_email_sent(fn email ->
        assert email.subject == "Global Combat Password Reset"
        assert email.text_body =~ "Login Name: #{account.name}"

        [_, new_password] = Regex.run(~r/Password: (\S+)/, email.text_body)
        assert {:ok, _} = Accounts.authenticate_account(account.name, new_password)
      end)
    end

    test "shows an error for an unknown login without leaking whether the account exists", %{
      conn: conn
    } do
      conn = post(conn, ~p"/account/reset-password", account: %{login: "nobody-here"})
      assert html_response(conn, 200) =~ "Account not found."
    end

    test "shows an error for a blank login", %{conn: conn} do
      conn = post(conn, ~p"/account/reset-password", account: %{login: ""})
      assert html_response(conn, 200) =~ "Invalid login name or email address."
    end
  end
end

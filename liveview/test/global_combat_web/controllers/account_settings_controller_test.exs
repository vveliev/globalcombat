defmodule GlobalCombatWeb.AccountSettingsControllerTest do
  use GlobalCombatWeb.ConnCase, async: true

  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Accounts

  describe "GET /account/settings" do
    test "requires a logged-in account", %{conn: conn} do
      conn = get(conn, ~p"/account/settings")
      assert redirected_to(conn) == ~p"/account/log-on"
    end

    test "renders for a logged-in account", %{conn: conn} do
      account = account_fixture()

      conn =
        conn
        |> log_in_account(account)
        |> get(~p"/account/settings")

      assert html_response(conn, 200) =~ "Account Settings"
    end
  end

  describe "PUT /account/settings/password" do
    setup %{conn: conn} do
      account = account_fixture()
      %{conn: log_in_account(conn, account), account: account}
    end

    test "changes the password with a correct old password", %{conn: conn, account: account} do
      conn =
        put(conn, ~p"/account/settings/password", %{
          "old_password" => valid_account_password(),
          "new_password" => "newpassword1",
          "new_password_confirmation" => "newpassword1"
        })

      html = html_response(conn, 200)
      assert html =~ "Password modified successfully."
      assert html =~ ~s(id="result-message")
      assert html =~ ~s(role="status")
      assert {:ok, _} = Accounts.authenticate_account(account.name, "newpassword1")
    end

    test "rejects an incorrect old password", %{conn: conn, account: account} do
      conn =
        put(conn, ~p"/account/settings/password", %{
          "old_password" => "wrongoldpassword",
          "new_password" => "newpassword1",
          "new_password_confirmation" => "newpassword1"
        })

      html = html_response(conn, 200)
      assert html =~ "did not enter the correct current password"
      assert html =~ ~s(id="result-message")
      assert html =~ ~s(role="alert")
      assert html =~ ~s(aria-describedby="result-message")
      assert {:ok, _} = Accounts.authenticate_account(account.name, valid_account_password())
    end

    test "rejects mismatched new passwords", %{conn: conn} do
      conn =
        put(conn, ~p"/account/settings/password", %{
          "old_password" => valid_account_password(),
          "new_password" => "newpassword1",
          "new_password_confirmation" => "somethingelse"
        })

      html = html_response(conn, 200)
      assert html =~ "do not match"
      assert html =~ ~s(role="alert")
      assert html =~ ~s(aria-describedby="result-message")
    end

    test "rejects a too-short new password", %{conn: conn} do
      conn =
        put(conn, ~p"/account/settings/password", %{
          "old_password" => valid_account_password(),
          "new_password" => "ab",
          "new_password_confirmation" => "ab"
        })

      assert html_response(conn, 200) =~ "at least five letters"
    end
  end
end

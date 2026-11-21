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

  describe "/account/reset-password/:token" do
    setup do
      account = account_fixture()
      {:ok, _, token} = Accounts.request_password_reset(account.name)
      %{account: account, token: token}
    end

    test "sets a new password once", %{conn: conn, account: account, token: token} do
      assert html_response(get(conn, ~p"/account/reset-password/#{token}"), 200) =~ "New password"

      params = %{password: "brandnewpw", password_confirmation: "brandnewpw"}
      conn2 = post(conn, ~p"/account/reset-password/#{token}", account: params)
      assert redirected_to(conn2) == ~p"/account/log-on"
      assert {:ok, _} = Accounts.authenticate_account(account.name, "brandnewpw")

      # Used token: rejected on both GET and POST.
      assert redirected_to(get(conn, ~p"/account/reset-password/#{token}")) ==
               ~p"/account/reset-password"

      conn3 =
        post(conn, ~p"/account/reset-password/#{token}",
          account: %{params | password: "x1x1x1x1", password_confirmation: "x1x1x1x1"}
        )

      assert redirected_to(conn3) == ~p"/account/reset-password"
      assert {:error, :bad_password} = Accounts.authenticate_account(account.name, "x1x1x1x1")
    end

    test "rejects a mismatched confirmation", %{conn: conn, token: token} do
      params = %{password: "brandnewpw", password_confirmation: "different"}
      conn = post(conn, ~p"/account/reset-password/#{token}", account: params)
      assert html_response(conn, 200) =~ "do not match"
    end

    test "rejects an unknown token", %{conn: conn} do
      conn = get(conn, ~p"/account/reset-password/not-a-real-token")
      assert redirected_to(conn) == ~p"/account/reset-password"
    end
  end

  describe "POST /account/reset-password" do
    test "emails a reset link and leaves the password untouched", %{conn: conn} do
      account = account_fixture()

      conn = post(conn, ~p"/account/reset-password", account: %{login: account.name})

      assert redirected_to(conn) == ~p"/account/log-on"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "reset link was sent"

      # The chrome shows no flash of its own, so the Log On card has to surface it.
      conn = get(recycle(conn), ~p"/account/log-on")
      assert html_response(conn, 200) =~ "reset link was sent"

      assert {:ok, _} = Accounts.authenticate_account(account.name, valid_account_password())

      assert_email_sent(fn email ->
        assert email.subject == "Global Combat Password Reset"
        assert email.text_body =~ "/account/reset-password/"
      end)
    end

    test "responds identically for an unknown login", %{conn: conn} do
      conn = post(conn, ~p"/account/reset-password", account: %{login: "nobody-here"})
      assert redirected_to(conn) == ~p"/account/log-on"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "reset link was sent"
      assert_no_email_sent()
    end

    test "is rate limited per IP", %{conn: conn} do
      conn = %{conn | remote_ip: {203, 0, 113, 77}}

      for _ <- 1..10, do: post(conn, ~p"/account/reset-password", account: %{login: "x"})

      assert post(conn, ~p"/account/reset-password", account: %{login: "x"}).status == 429
    end

    test "shows an error for a blank login", %{conn: conn} do
      conn = post(conn, ~p"/account/reset-password", account: %{login: ""})
      assert html_response(conn, 200) =~ "Invalid login name or email address."
    end
  end
end

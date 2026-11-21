defmodule GlobalCombatWeb.AccountSessionControllerTest do
  use GlobalCombatWeb.ConnCase, async: true

  import GlobalCombat.AccountsFixtures

  describe "GET /account/log-on" do
    test "renders the log on form", %{conn: conn} do
      conn = get(conn, ~p"/account/log-on")
      assert html_response(conn, 200) =~ "Log On"
    end
  end

  describe "POST /account/log-on" do
    test "logs in a modern (already-hashed) account and redirects home", %{conn: conn} do
      account = account_fixture()

      conn =
        post(conn, ~p"/account/log-on",
          account: %{login: account.name, password: valid_account_password()}
        )

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :account_id) == account.id
    end

    test "logs in with a legacy plaintext password", %{conn: conn} do
      account = legacy_plaintext_account_fixture(password: "plaintextpw")

      conn =
        post(conn, ~p"/account/log-on", account: %{login: account.name, password: "plaintextpw"})

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :account_id) == account.id
    end

    test "logs in by email address", %{conn: conn} do
      account = account_fixture()

      conn =
        post(conn, ~p"/account/log-on",
          account: %{login: account.email, password: valid_account_password()}
        )

      assert get_session(conn, :account_id) == account.id
    end

    test "re-renders with an error for a bad password", %{conn: conn} do
      account = account_fixture()

      conn =
        post(conn, ~p"/account/log-on",
          account: %{login: account.name, password: "wrongpassword"}
        )

      html = html_response(conn, 200)
      assert html =~ "Bad Password"
      assert html =~ ~s(id="login-error")
      assert html =~ ~s(role="alert")
      assert html =~ ~s(aria-describedby="login-error")
      refute get_session(conn, :account_id)
    end

    test "preserves the submitted login name after a bad password", %{conn: conn} do
      account = account_fixture()

      conn =
        post(conn, ~p"/account/log-on",
          account: %{login: account.name, password: "wrongpassword"}
        )

      html = html_response(conn, 200)
      assert html =~ "Bad Password"
      assert html =~ ~s(value="#{account.name}")
    end

    test "re-renders with an error for an unknown login", %{conn: conn} do
      conn =
        post(conn, ~p"/account/log-on", account: %{login: "nobody-here", password: "whatever1"})

      assert html_response(conn, 200) =~ "Unknown login name or email address."
    end

    test "returns 429 after too many failures and a success clears the login counter", %{
      conn: conn
    } do
      account = account_fixture()
      bad = [account: %{login: account.name, password: "wrongpassword"}]

      # Distinct client IPs so only the per-login counter is in play.
      for i <- 1..10, do: post(%{conn | remote_ip: {198, 51, 100, i}}, ~p"/account/log-on", bad)

      limited = post(%{conn | remote_ip: {198, 51, 100, 99}}, ~p"/account/log-on", bad)
      assert html_response(limited, 429) =~ "Too many failed attempts"

      # A different login from a fresh IP is unaffected, and a failure counter resets on success.
      other = account_fixture()
      ok = [account: %{login: other.name, password: valid_account_password()}]
      assert get_session(post(%{conn | remote_ip: {198, 51, 100, 98}}, ~p"/account/log-on", ok), :account_id)
    end

    test "returns 429 after too many failures from one IP", %{conn: conn} do
      conn = %{conn | remote_ip: {203, 0, 113, 5}}

      for _ <- 1..10 do
        post(conn, ~p"/account/log-on", account: %{login: "nobody-#{System.unique_integer()}", password: "x"})
      end

      conn = post(conn, ~p"/account/log-on", account: %{login: "someone-else", password: "x"})
      assert html_response(conn, 429) =~ "Too many failed attempts"
    end

    test "blocks a disabled account", %{conn: conn} do
      account = legacy_plaintext_account_fixture(password: "plaintextpw")
      disable_account!(account)

      conn =
        post(conn, ~p"/account/log-on", account: %{login: account.name, password: "plaintextpw"})

      assert html_response(conn, 200) =~ "permanently disabled"
      refute get_session(conn, :account_id)
    end
  end

  describe "DELETE /account/log-off" do
    test "clears the session", %{conn: conn} do
      account = account_fixture()

      conn =
        conn
        |> log_in_account(account)
        |> delete(~p"/account/log-off")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :account_id)
    end
  end
end

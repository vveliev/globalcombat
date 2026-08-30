defmodule GlobalCombatWeb.AccountContactControllerTest do
  use GlobalCombatWeb.ConnCase, async: true

  import Swoosh.TestAssertions
  import GlobalCombat.AccountsFixtures

  describe "GET /account/contact" do
    test "requires a logged-in account", %{conn: conn} do
      conn = get(conn, ~p"/account/contact")
      assert redirected_to(conn) == ~p"/account/log-on"
    end

    test "renders the contact form for a logged-in account", %{conn: conn} do
      account = account_fixture()

      conn =
        conn
        |> log_in_account(account)
        |> get(~p"/account/contact")

      assert html_response(conn, 200) =~ "Contact Us"
    end
  end

  describe "POST /account/contact" do
    setup %{conn: conn} do
      account = account_fixture()
      %{conn: log_in_account(conn, account), account: account}
    end

    test "emails the contact address and shows a thank-you", %{conn: conn, account: account} do
      conn =
        post(conn, ~p"/account/contact", %{
          "subject" => "A question",
          "comments" => "Does this work?"
        })

      assert html_response(conn, 200) =~ "Thank you for your feedback."

      assert_email_sent(fn email ->
        assert email.subject == "[Global Combat] A question"
        assert email.text_body =~ "Does this work?"
        assert email.text_body =~ account.name
        assert email.text_body =~ account.email
        assert email.reply_to == {"", account.email}
      end)
    end

    test "rejects a blank subject", %{conn: conn} do
      conn = post(conn, ~p"/account/contact", %{"subject" => "  ", "comments" => "Hello"})
      assert html_response(conn, 200) =~ "Subject cannot be empty."
    end

    test "rejects a blank message", %{conn: conn} do
      conn = post(conn, ~p"/account/contact", %{"subject" => "Hi", "comments" => ""})
      assert html_response(conn, 200) =~ "Message cannot be empty."
    end
  end
end

defmodule GlobalCombatWeb.AccountRegistrationControllerTest do
  use GlobalCombatWeb.ConnCase, async: true

  import GlobalCombat.AccountsFixtures

  describe "GET /account/register" do
    test "renders the registration form", %{conn: conn} do
      conn = get(conn, ~p"/account/register")
      response = html_response(conn, 200)
      assert response =~ "Register"
    end

    test "renders the code of conduct", %{conn: conn} do
      conn = get(conn, ~p"/account/register")
      response = html_response(conn, 200)
      assert response =~ "Code of Conduct"
      assert response =~ "Don't play with multiple accounts, that's just lame."
      assert response =~ "Be respectful and don't abuse fellow players."
      assert response =~
               "If you break these rules your account will be disabled and your IP address will be banned."
    end
  end

  describe "POST /account/register" do
    test "creates an account, logs the account in, and redirects home", %{conn: conn} do
      attrs = valid_account_attributes()

      conn = post(conn, ~p"/account/register", account: attrs)

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :account_id)

      account = GlobalCombat.Accounts.get_account_by_login(attrs["name"])
      assert account
      assert account.num_logins == 1
    end

    test "re-renders the form with errors on a duplicate login name", %{conn: conn} do
      existing = account_fixture()
      attrs = valid_account_attributes(%{"name" => existing.name})

      conn = post(conn, ~p"/account/register", account: attrs)

      response = html_response(conn, 200)
      assert response =~ "Login name already taken"
    end

    test "re-renders the form with errors when passwords do not match", %{conn: conn} do
      attrs = valid_account_attributes(%{"password_confirmation" => "somethingelse"})

      conn = post(conn, ~p"/account/register", account: attrs)

      response = html_response(conn, 200)
      assert response =~ "do not match"
    end
  end
end

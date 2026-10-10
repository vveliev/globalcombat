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

  describe "registration end to end" do
    test "register button keeps its btn styling alongside the layout class", %{conn: conn} do
      html = conn |> get(~p"/account/register") |> html_response(200)

      doc = LazyHTML.from_fragment(html)
      button = LazyHTML.query(doc, "form button")
      assert LazyHTML.attribute(button, "class") |> hd() =~ ~r/\bbtn\b/
      assert LazyHTML.attribute(button, "class") |> hd() =~ "btn-primary"
      assert LazyHTML.text(button) =~ "Register"
    end

    test "form -> submit -> logged in -> can log off and back on; re-register is rejected", %{
      conn: conn
    } do
      attrs = valid_account_attributes()

      # 1. load the form, as the browser does (sets session + CSRF)
      conn = get(conn, ~p"/account/register")
      assert html_response(conn, 200) =~ "Register"

      # 2. submit it
      conn = post(conn, ~p"/account/register", account: attrs)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome"

      # 3. follow the redirect: the new account is the signed-in one
      conn = conn |> recycle() |> get(~p"/")
      assert conn.assigns.current_account.name == attrs["name"]

      # 4. a second submit of the same form (e.g. a double tap) is a clean validation error
      again = build_conn() |> post(~p"/account/register", account: attrs)
      assert html_response(again, 200) =~ "Login name already taken"

      # 5. the account really works: log on with the password just registered
      assert {:ok, _} =
               GlobalCombat.Accounts.authenticate_account(attrs["name"], attrs["password"])
    end
  end
end

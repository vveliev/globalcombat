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
    test "register button is a styled, touch-sized submit button", %{conn: conn} do
      html = conn |> get(~p"/account/register") |> html_response(200)

      doc = LazyHTML.from_fragment(html)
      button = LazyHTML.query(doc, "form button")
      assert LazyHTML.attribute(button, "type") == ["submit"]
      assert LazyHTML.attribute(button, "class") |> hd() =~ "bg-primary"
      assert LazyHTML.attribute(button, "class") |> hd() =~ "min-h-[var(--size-touch-target)]"
      assert LazyHTML.text(button) =~ "Register"
    end

    test "form -> submit -> logged in -> can log off and back on; re-register is rejected", %{
      conn: conn
    } do
      attrs = valid_account_attributes()

      # 1. load the form, as the browser does (sets session + CSRF)
      conn = get(conn, ~p"/account/register")
      form = conn |> html_response(200) |> LazyHTML.from_document() |> LazyHTML.query("form")

      # 2. fill in and submit the inputs the form actually renders, so a field that lost its
      #    `name` (and would be dropped from a real browser submit) fails here
      params =
        fill_form(form, %{
          "account[name]" => attrs["name"],
          "account[email]" => attrs["email"],
          "account[password]" => attrs["password"],
          "account[password_confirmation]" => attrs["password_confirmation"]
        })

      conn = post(conn, LazyHTML.attribute(form, "action") |> hd(), params)
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

  # Builds the POST body from the form's own named inputs: hidden inputs (CSRF) keep their
  # rendered values, visible ones take `values`; every key in `values` must exist as a field.
  defp fill_form(form, values) do
    names =
      form
      |> LazyHTML.query("input[name]")
      |> Enum.map(fn input -> {hd(LazyHTML.attribute(input, "name")), input} end)

    for key <- Map.keys(values) do
      assert List.keymember?(names, key, 0), "form has no input named #{key}"
    end

    body =
      Enum.map_join(names, "&", fn {name, input} ->
        value = Map.get(values, name) || LazyHTML.attribute(input, "value") |> List.first() || ""
        URI.encode_www_form(name) <> "=" <> URI.encode_www_form(value)
      end)

    Plug.Conn.Query.decode(body)
  end
end

defmodule GlobalCombatWeb.HomeControllerTest do
  use GlobalCombatWeb.ConnCase, async: true

  import GlobalCombat.AccountsFixtures
  import GlobalCombat.GamesFixtures

  alias GlobalCombat.{Accounts, Messaging, Repo}

  defp admin_fixture(attrs \\ %{}) do
    account_fixture(attrs) |> Ecto.Changeset.change(admin: true) |> Repo.update!()
  end

  describe "GET / (index)" do
    test "shows the marketing pitch and games-to-join list when logged out", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Elo based rating system"
      assert html_response(conn, 200) =~ "Games to Join"
    end

    test "shows the account dashboard when logged in", %{conn: conn} do
      account = account_fixture()
      conn = conn |> log_in_account(account) |> get(~p"/")

      body = html_response(conn, 200)
      assert body =~ account.name
      assert body =~ "Your Current Games"
    end

    test "lists the account's current games and invites", %{conn: conn} do
      account = account_fixture()
      game_fixture(%{game_name: "My Current Game", started: true}, [{account.id, []}])
      game_fixture(%{game_name: "My Invite"}, [{account.id, [is_invite: true]}])

      body = conn |> log_in_account(account) |> get(~p"/") |> html_response(200)

      assert body =~ "My Current Game"
      assert body =~ "My Invite"
    end
  end

  describe "GET /Game-Manual" do
    test "renders the verbatim manual content", %{conn: conn} do
      body = get(conn, ~p"/Game-Manual") |> html_response(200)
      assert body =~ "Introduction"
      assert body =~ "The Rating System"
      assert body =~ "Your rating changes by"
    end
  end

  describe "GET /Stats" do
    test "redirects a non-admin (logged in or not) to /", %{conn: conn} do
      account = account_fixture()
      conn = conn |> log_in_account(account) |> get(~p"/Stats")
      assert redirected_to(conn) == ~p"/"
    end

    test "renders the overview for an admin", %{conn: conn} do
      admin = admin_fixture()
      body = conn |> log_in_account(admin) |> get(~p"/Stats") |> html_response(200)
      assert body =~ "Accounts"
      assert body =~ "Running Games"
    end
  end

  describe "GET /Messages" do
    test "requires login", %{conn: conn} do
      assert conn |> get(~p"/Messages") |> redirected_to() == ~p"/"
    end

    test "shows a sent message", %{conn: conn} do
      a = account_fixture()
      b = account_fixture()
      Messaging.send_message(a.id, b.id, b.name, "hi there")

      body = conn |> log_in_account(a) |> get(~p"/Messages") |> html_response(200)
      assert body =~ "hi there"
      assert body =~ b.name
    end

    test "shows the empty state", %{conn: conn} do
      account = account_fixture()
      body = conn |> log_in_account(account) |> get(~p"/Messages") |> html_response(200)
      assert body =~ "You have no messages."
    end
  end

  describe "GET /Player-Info-:id" do
    test "404s for an unknown account", %{conn: conn} do
      assert get(conn, ~p"/Player-Info-999999").status == 404
    end

    test "renders the account's rating/rank/games", %{conn: conn} do
      account = account_fixture() |> Ecto.Changeset.change(rating: 9300) |> Repo.update!()
      body = get(conn, ~p"/Player-Info-#{account.id}") |> html_response(200)

      assert body =~ account.name
      assert body =~ "9300"
      assert body =~ "Sergeant"
    end

    test "an admin viewer can permanently disable the account via ?KillAccount=1", %{conn: conn} do
      admin = admin_fixture()
      target = account_fixture()

      conn =
        conn |> log_in_account(admin) |> get(~p"/Player-Info-#{target.id}?KillAccount=1")

      assert html_response(conn, 200) =~ "Account Disabled"
      assert Accounts.get_account(target.id) == nil
    end

    test "a non-admin viewer cannot disable the account", %{conn: conn} do
      viewer = account_fixture()
      target = account_fixture()

      conn |> log_in_account(viewer) |> get(~p"/Player-Info-#{target.id}?KillAccount=1")

      assert Accounts.get_account(target.id) != nil
    end
  end

  describe "GET /IpAddresses" do
    test "redirects a non-admin to /", %{conn: conn} do
      assert conn |> get(~p"/IpAddresses") |> redirected_to() == ~p"/"
    end

    test "renders the search results for an admin", %{conn: conn} do
      admin = admin_fixture()

      body =
        conn
        |> log_in_account(admin)
        |> get(~p"/IpAddresses?IPAddress=1.2.3.4")
        |> html_response(200)

      assert body =~ "IP Address"
    end
  end

  describe "OptOut" do
    test "GET with no params shows the missing-key error", %{conn: conn} do
      assert get(conn, ~p"/OptOut") |> html_response(200) =~ "Missing account or opt out key."
    end

    test "GET with a valid Account/Key shows the confirm form", %{conn: conn} do
      account = account_fixture()

      body =
        get(conn, ~p"/OptOut?Account=#{account.id}&Key=#{account.opt_out_key}")
        |> html_response(200)

      assert body =~ "Confirm"
    end

    test "POST with the correct key opts the account out", %{conn: conn} do
      account = account_fixture()

      body =
        post(conn, ~p"/OptOut", %{"Account" => account.id, "Key" => account.opt_out_key})
        |> html_response(200)

      assert body =~ "You will no longer receive emails"
      assert Repo.get!(GlobalCombat.Accounts.Account, account.id).opt_out
    end

    test "POST with the wrong key shows an error and does not opt out", %{conn: conn} do
      account = account_fixture()

      body =
        post(conn, ~p"/OptOut", %{"Account" => account.id, "Key" => account.opt_out_key + 1})
        |> html_response(200)

      assert body =~ "Incorrect opt out key."
      refute Repo.get!(GlobalCombat.Accounts.Account, account.id).opt_out
    end
  end

  describe "chat endpoints" do
    setup %{conn: conn} do
      sender = account_fixture()
      recipient = account_fixture()
      %{conn: log_in_account(conn, sender), sender: sender, recipient: recipient}
    end

    test "POST /Home/Chat sends a message", %{conn: conn, sender: sender, recipient: recipient} do
      post(conn, ~p"/Home/Chat", %{"targetId" => recipient.id, "message" => "yo"})

      [message] = Messaging.list_messages_for_account(recipient.id)
      assert message.text == "yo"
      assert message.from_id == sender.id
    end

    test "POST /Home/LoadChatMessages returns JSON history and remembers the open window", %{
      conn: conn,
      sender: sender,
      recipient: recipient
    } do
      Messaging.send_message(sender.id, recipient.id, recipient.name, "hello")

      conn =
        post(conn, ~p"/Home/LoadChatMessages", %{
          "targetId" => recipient.id,
          "targetName" => recipient.name
        })

      assert [%{"name" => name, "text" => "hello"}] = json_response(conn, 200)
      assert name == recipient.name
      assert get_session(conn, :open_chat_windows) == ["#{recipient.id}|#{recipient.name}"]
    end

    test "POST /Home/CloseChatWindow persists the removal (fixes the legacy no-op bug)", %{
      conn: conn,
      recipient: recipient
    } do
      conn =
        conn
        |> put_session(:open_chat_windows, ["#{recipient.id}|#{recipient.name}"])
        |> post(~p"/Home/CloseChatWindow", %{
          "targetId" => to_string(recipient.id),
          "targetName" => recipient.name
        })

      assert get_session(conn, :open_chat_windows) == []
    end

    test "unauthenticated requests are redirected home", %{recipient: recipient} do
      conn = build_conn()
      conn = post(conn, ~p"/Home/Chat", %{"targetId" => recipient.id, "message" => "hi"})
      assert redirected_to(conn) == ~p"/"
    end
  end
end

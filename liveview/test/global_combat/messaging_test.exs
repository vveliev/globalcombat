defmodule GlobalCombat.MessagingTest do
  use GlobalCombat.DataCase, async: true

  import GlobalCombat.AccountsFixtures
  import Swoosh.TestAssertions

  alias GlobalCombat.Messaging

  describe "send_message/4" do
    test "inserts a message row" do
      sender = account_fixture()
      recipient = account_fixture()

      message = Messaging.send_message(recipient.id, sender.id, sender.name, "hello there")

      assert message.to_id == recipient.id
      assert message.from_id == sender.id
      assert message.text == "hello there"
    end

    test "emails an offline recipient with forward_emails: :all (ports GameServer.SendMessage's fallback)" do
      sender = account_fixture()
      recipient = account_fixture()

      Messaging.send_message(recipient.id, sender.id, sender.name, "hello there")

      assert_email_sent(subject: "Message from #{sender.name}")
    end

    test "does not email an offline recipient whose forward_emails excludes plain messages" do
      sender = account_fixture()

      recipient =
        account_fixture()
        |> Ecto.Changeset.change(forward_emails: :none)
        |> GlobalCombat.Repo.update!()

      Messaging.send_message(recipient.id, sender.id, sender.name, "hello there")

      refute_email_sent()
    end

    test "still inserts the row for a game-forum broadcast (to_id <= 0) but never emails/pushes" do
      sender = account_fixture()

      message = Messaging.send_message(-42, sender.id, sender.name, "turn ran")

      assert message.to_id == -42
      refute_email_sent()
    end
  end

  describe "list_messages_for_account/1" do
    test "returns messages to or from the account, most recent first, with names joined" do
      a = account_fixture()
      b = account_fixture()

      Messaging.send_message(b.id, a.id, a.name, "first")
      Messaging.send_message(a.id, b.id, b.name, "second")

      [newest, oldest] = Messaging.list_messages_for_account(a.id)
      assert newest.text == "second"
      assert newest.from_name == b.name
      assert oldest.text == "first"
    end

    test "excludes game-forum broadcasts (negative to_id has no matching account row to join)" do
      a = account_fixture()
      Messaging.send_message(-1, a.id, a.name, "broadcast")

      assert Messaging.list_messages_for_account(a.id) == []
    end
  end

  describe "list_chat_history/2" do
    test "returns the last 20 messages between two accounts, chronological" do
      a = account_fixture()
      b = account_fixture()

      Messaging.send_message(b.id, a.id, a.name, "hi")
      Messaging.send_message(a.id, b.id, b.name, "hey")

      assert [%{from_id: from1, text: "hi"}, %{from_id: from2, text: "hey"}] =
               Messaging.list_chat_history(a.id, b.id)

      assert from1 == a.id
      assert from2 == b.id
    end
  end
end

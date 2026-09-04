defmodule GlobalCombat.Accounts.Notifier do
  @moduledoc "Ports the account-related emails sent from `AccountController.cs`."

  import Swoosh.Email

  alias GlobalCombat.Mailer

  defp deliver(to, subject, body, opts \\ []) do
    email =
      new()
      |> to(to)
      |> from(sender())
      |> subject(subject)
      |> text_body(body)

    email = if reply_to = opts[:reply_to], do: reply_to(email, reply_to), else: email

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "Ports the reset-password email body from `AccountController.ResetPassword`."
  def deliver_reset_password(%{email: email, name: name}, new_password) do
    deliver(
      email,
      "Global Combat Password Reset",
      """
      Login Name: #{name}
      Password: #{new_password}

      If you have a hard time remembering it, change it from Account Settings after logging in.
      """
    )
  end

  @doc "Ports `GameServer.SendMessage`'s offline-recipient email fallback (`Web/Models/GameServer.cs:206-207`)."
  def deliver_new_message(%{email: email}, source_name, text) do
    deliver(
      email,
      "Message from #{source_name}",
      """
      #{source_name} wrote:
      #{text}

      These emails will only be sent when you are not logged in.

      To change what kind of messages you receive, login to Global Combat and go to your account settings.
      """
    )
  end

  @contact_email "contact@globalcombat.com"

  @doc "Ports `AccountController.ContactEmail` (`Web/Controllers/AccountController.cs:311-327`) — the Contact Us form's send-to-support notification."
  def deliver_contact_email(%{email: email, name: name, id: id}, subject, comments) do
    deliver(
      @contact_email,
      "[Global Combat] #{subject}",
      """
      #{comments}
      #{name}
      #{email}
      https://globalcombat.com/Player-Info-#{id}
      """,
      reply_to: email
    )
  end

  # `MAILER_FROM` (config/runtime.exs via `GlobalCombat.MailerConfig`, docs/launch.md §2.3) when
  # a production mailer is configured; the legacy `AccountController.cs` address otherwise.
  defp sender do
    Application.get_env(:global_combat, :mailer_from, GlobalCombat.MailerConfig.legacy_sender())
  end
end

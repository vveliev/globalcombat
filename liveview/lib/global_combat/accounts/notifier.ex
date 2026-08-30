defmodule GlobalCombat.Accounts.Notifier do
  @moduledoc "Ports the account-related emails sent from `AccountController.cs`."

  import Swoosh.Email

  alias GlobalCombat.Mailer

  defp deliver(to, subject, body) do
    email =
      new()
      |> to(to)
      |> from({"Global Combat", "noreply@globalcombat.com"})
      |> subject(subject)
      |> text_body(body)

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
end

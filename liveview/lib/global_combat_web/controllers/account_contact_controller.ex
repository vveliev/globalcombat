defmodule GlobalCombatWeb.AccountContactController do
  use GlobalCombatWeb, :controller

  alias GlobalCombat.Accounts.Notifier

  # Ports `AccountController.Contact` (`Web/Controllers/AccountController.cs:299-307`).
  def new(conn, _params) do
    render(conn, :new, result_message: nil)
  end

  # Ports `AccountController.Contact`'s POST branch -> `ContactEmail(subject, comments)`
  # (`Web/Controllers/AccountController.cs:311-327`).
  def create(conn, %{"subject" => subject, "comments" => comments}) do
    cond do
      String.trim(subject) == "" ->
        render(conn, :new, result_message: "Subject cannot be empty.")

      comments == "" ->
        render(conn, :new, result_message: "Message cannot be empty.")

      true ->
        Notifier.deliver_contact_email(conn.assigns.current_account, subject, comments)
        render(conn, :new, result_message: "Thank you for your feedback.")
    end
  end
end

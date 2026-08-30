defmodule GlobalCombatWeb.AccountSettingsController do
  use GlobalCombatWeb, :controller

  alias GlobalCombat.Accounts

  def edit(conn, _params) do
    render(conn, :edit, result_message: nil)
  end

  # Ports `AccountController.Settings` -> `ModifyPassword(oldPassword, newPassword, newPasswordVerify)`.
  def update_password(conn, %{
        "old_password" => old_password,
        "new_password" => new_password,
        "new_password_confirmation" => new_password_confirmation
      }) do
    cond do
      new_password != new_password_confirmation ->
        render(conn, :edit,
          result_message:
            "Unable to modify your password. The new passwords you entered do not match."
        )

      String.length(new_password) < 5 ->
        render(conn, :edit,
          result_message:
            "Unable to modify your password. Password must be at least five letters."
        )

      true ->
        case Accounts.change_password(conn.assigns.current_account, old_password, new_password) do
          {:ok, account} ->
            conn
            |> assign(:current_account, account)
            |> render(:edit, result_message: "Password modified successfully.")

          {:error, :bad_old_password} ->
            render(conn, :edit,
              result_message:
                "Unable to modify your password. You did not enter the correct current password."
            )

          {:error, %Ecto.Changeset{}} ->
            render(conn, :edit, result_message: "Unable to modify your password.")
        end
    end
  end
end

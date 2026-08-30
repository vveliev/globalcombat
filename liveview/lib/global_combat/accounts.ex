defmodule GlobalCombat.Accounts do
  @moduledoc """
  Account registration, authentication, and session-history recording.

  Ports `Web/Controllers/AccountController.cs` and the `CreateAccount`/`SetSession` helpers in
  `Web/Controllers/BaseController.cs`. Password handling follows
  `docs/adr/0002-account-password-migration.md`: verify against whichever legacy shape matches
  (plaintext or the old truncated SHA-512 hash), then transparently rehash to PBKDF2 on success
  — no forced reset for the general player base.
  """

  import Ecto.Query

  alias GlobalCombat.Repo
  alias GlobalCombat.Accounts.{Account, AccountLogin, Password}

  @legacy_password_generator_chars ~c"abcdefghijklmnopqrstuvwxyz0123456789"

  @doc "Ports `BaseController.CreateAccount(loginName, password, passwordVerify, email, ...)`."
  def register_account(attrs) do
    %Account{}
    |> Account.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Ports the `select * from account where name = '{0}' or email = '{0}'` lookup used throughout AccountController."
  def get_account_by_login(login) when is_binary(login) do
    Repo.one(from a in Account, where: a.name == ^login or a.email == ^login)
  end

  @doc """
  Looks up an account by id for session resolution — `nil` if the id is unknown or the account
  has since been disabled, so a disabled account's live sessions stop resolving on their next
  request rather than only being blocked at the next LogOn.
  """
  def get_account(id) do
    Repo.one(from a in Account, where: a.id == ^id and is_nil(a.disabled_by))
  end

  @type auth_error :: :not_found | :disabled | :bad_password

  @doc """
  Ports `AccountController.Login`. Returns `{:ok, account}` on success (with `password`
  transparently rehashed to PBKDF2 if it matched a legacy shape) or `{:error, reason}`.
  """
  @spec authenticate_account(String.t(), String.t()) ::
          {:ok, Account.t()} | {:error, auth_error()}
  def authenticate_account(login, password) when is_binary(login) and is_binary(password) do
    case get_account_by_login(login) do
      nil ->
        # Still run a hash so lookup-by-name and lookup-by-unknown-name take roughly the same
        # time; the legacy code has no such protection, but there's no reason not to have it.
        Password.hash_password(password)
        {:error, :not_found}

      %Account{disabled_by: disabled_by} when not is_nil(disabled_by) ->
        {:error, :disabled}

      %Account{} = account ->
        case verify_and_maybe_rehash(account, password) do
          {:ok, account} -> {:ok, account}
          # A legacy shape matched but the fresh hash failed to persist (e.g. a connection
          # blip) — don't let a rehash failure turn into a login failure; the port's own rule
          # is that existing users can't be locked out.
          {:error, %Ecto.Changeset{}} -> {:ok, account}
          :error -> {:error, :bad_password}
        end
    end
  end

  defp verify_and_maybe_rehash(%Account{password: stored} = account, password) do
    cond do
      Password.verify_password(password, stored) ->
        {:ok, account}

      stored == password or Password.legacy_hash_matches?(password, stored) ->
        account |> Account.password_changeset(password) |> Repo.update()

      true ->
        :error
    end
  end

  @doc """
  Ports `AccountController.SetSession`'s bookkeeping: bumps `last_on`/`num_logins` and inserts
  an `account_login` audit row. Idempotent per (account, second) the same way the legacy
  `insert ignore` was.
  """
  def record_login(%Account{} = account, opts \\ []) do
    now = DateTime.utc_now(:second)
    ip = Keyword.get(opts, :ip_address)
    browser = Keyword.get(opts, :user_agent)
    admin_used = Keyword.get(opts, :admin_used, false)

    Repo.transaction(fn ->
      # MySQL has no `UPDATE ... RETURNING`, so update_all can't select the updated row —
      # apply the same increment/set locally to the struct we already hold instead of re-reading.
      {1, nil} =
        from(a in Account, where: a.id == ^account.id)
        |> Repo.update_all(inc: [num_logins: 1], set: [last_on: now])

      account = %{account | num_logins: account.num_logins + 1, last_on: now}

      # `conflict_target` isn't supported by the MyXQL adapter (MySQL's `INSERT IGNORE` has no
      # column-targeted form) — `on_conflict: :nothing` alone maps to `INSERT IGNORE`, which is
      # exactly the legacy `insert ignore into account_login (...)` this ports.
      %AccountLogin{}
      |> AccountLogin.changeset(%{
        account_id: account.id,
        logged_in_at: now,
        ipaddress: ip,
        browser: browser,
        adminused: admin_used
      })
      |> Repo.insert(on_conflict: :nothing)

      account
    end)
  end

  @doc """
  Ports `AccountController.ResetPassword` (reached from LostPassword). Generates a new
  8-character password the same way `UserPage<int>.GeneratePassword(8)` did, hashes it before
  it ever touches the database (ADR-0002 — the legacy path wrote it in cleartext), and returns
  the generated plaintext so the caller can email it, matching the legacy UX.
  """
  def reset_password(login) when is_binary(login) do
    case get_account_by_login(login) do
      nil ->
        {:error, :not_found}

      %Account{} = account ->
        new_password = generate_password(8)

        account
        |> Account.password_changeset(new_password)
        |> Repo.update()
        |> case do
          {:ok, account} -> {:ok, account, new_password}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Ports `AccountController.ModifyPassword` (Settings). Verifies `old_password` against
  whichever shape is currently stored (same three-way match as login) before accepting
  `new_password`.
  """
  def change_password(%Account{} = account, old_password, new_password) do
    matches? =
      Password.verify_password(old_password, account.password) or
        account.password == old_password or
        Password.legacy_hash_matches?(old_password, account.password)

    if matches? do
      account
      |> Account.password_changeset(new_password)
      |> Repo.update()
    else
      {:error, :bad_old_password}
    end
  end

  defp generate_password(length) do
    for _ <- 1..length, into: "", do: <<Enum.random(@legacy_password_generator_chars)>>
  end
end

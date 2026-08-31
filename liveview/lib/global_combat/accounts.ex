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

  @doc """
  Ports the plain `Account.Load(db.EvaluateRow("select * from account where id = {0}", id))`
  used by `HomeController.PlayerInfo` — unlike `get_account/1`, this does *not* exclude
  disabled accounts, since PlayerInfo shows a disabled account's page rather than 404ing it.
  """
  def get_account_including_disabled(id), do: Repo.get(Account, id)

  @doc "Ports the login-history query behind `PlayerInfo?ShowLoginHistory=1` (admin-gated in this port, see `HomeController`)."
  def list_logins_for_account(account_id) do
    Repo.all(
      from l in AccountLogin,
        where: l.account_id == ^account_id,
        order_by: [desc: l.logged_in_at],
        limit: 100
    )
  end

  @doc "Ports `HomeController.IpAddresses`' reverse IP-to-logins lookup (admin-gated in this port)."
  def list_logins_for_ip(ip_address) do
    Repo.all(
      from l in AccountLogin,
        where: l.ipaddress == ^ip_address,
        order_by: [desc: l.logged_in_at],
        limit: 100
    )
  end

  @doc """
  Ports `HomeController.OptOut(int account)` — validates the `OptOutKey` capability token
  (`docs/schema-map.md` §2.6, not a sequential id) before flipping `opt_out`.
  """
  def opt_out(account_id, key) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :not_found}
      %Account{opt_out_key: k} when k != key -> {:error, :bad_key}
      %Account{} = account -> account |> Ecto.Changeset.change(opt_out: true) |> Repo.update()
    end
  end

  @doc "Ports `HomeController.PlayerInfo`'s admin `KillAccount` action (`update account set disabled_by = <admin id>`)."
  def disable_account(%Account{} = account, admin_account_id) do
    account |> Ecto.Changeset.change(disabled_by: admin_account_id) |> Repo.update()
  end

  @doc """
  Ports the loser-side half of `GameServer.OnEliminated`'s non-training branch (`update account
  set games = games + 1 where id = ...`) — fired when a player is eliminated before the game
  itself ends. `GlobalCombat.Games.Server` is responsible for the `!IsTraining` gate, same as
  every other function here that mirrors a `db.Execute` from that file.
  """
  def record_game_played(account_id) do
    from(a in Account, where: a.id == ^account_id) |> Repo.update_all(inc: [games: 1])
    :ok
  end

  @doc "Ports the winner-side half of `GameServer.OnEnd`'s non-training branch (`update account set wins = wins + 1, games = games + 1 where id = winner.AccountId`)."
  def record_win(account_id) do
    from(a in Account, where: a.id == ^account_id) |> Repo.update_all(inc: [wins: 1, games: 1])
    :ok
  end

  @doc "Ports `GameServer.OnEnd`'s per-player rating award (`update account set rating = rating + RatingChange`)."
  def apply_rating_change(account_id, rating_change) do
    from(a in Account, where: a.id == ^account_id)
    |> Repo.update_all(inc: [rating: rating_change])

    :ok
  end
end

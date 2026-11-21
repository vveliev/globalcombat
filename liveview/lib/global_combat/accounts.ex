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

  # The legacy convention every game relies on: account 1 is the "Computer" — the Training Mode
  # opponent's seat (always done, never waited on) and the author of system chat lines. The
  # reserve_computer_account migration claims this id on a fresh database.
  @computer_account_id 1
  @computer_name "Computer"

  @doc "The reserved account id of the \"Computer\" (Training Mode opponent, system messages)."
  def computer_account_id, do: @computer_account_id

  @doc "The display name the \"Computer\" account plays and posts under."
  def computer_name, do: @computer_name

  @doc "Whether `account_id` is the reserved \"Computer\" account."
  def computer_account?(account_id), do: account_id == @computer_account_id

  @doc "Ports `BaseController.CreateAccount(loginName, password, passwordVerify, email, ...)`."
  def register_account(attrs) do
    %Account{}
    |> Account.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Ports the `select * from account where name = '{0}' or email = '{0}'` lookup used throughout AccountController."
  def get_account_by_login(login) when is_binary(login) do
    # Legacy rows may have an `@` name equal to someone else's email; a name match wins.
    Repo.one(
      from a in Account,
        where: a.name == ^login or a.email == ^login,
        order_by: [desc: a.name == ^login],
        limit: 1
    )
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
      # Apply the same increment/set locally to the struct we already hold instead of
      # re-reading (written when the DB was MySQL, which had no `UPDATE ... RETURNING`).
      {1, nil} =
        from(a in Account, where: a.id == ^account.id)
        |> Repo.update_all(inc: [num_logins: 1], set: [last_on: now])

      account = %{account | num_logins: account.num_logins + 1, last_on: now}

      # `ON CONFLICT (account_id, logged_in_at) DO NOTHING` — the legacy
      # `insert ignore into account_login (...)`, scoped to the de-dup index so any other
      # constraint violation still raises instead of being swallowed.
      %AccountLogin{}
      |> AccountLogin.changeset(%{
        account_id: account.id,
        logged_in_at: now,
        ipaddress: ip,
        browser: browser,
        adminused: admin_used
      })
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :logged_in_at])

      account
    end)
  end

  @reset_token_ttl_seconds 3600

  @doc """
  Starts a password reset: stores the SHA-256 of a fresh random token with a one-hour expiry
  and returns the raw token for the caller to email. Nothing about the account's password
  changes. `:error` for an unknown or disabled account (callers must not reveal which).
  """
  def request_password_reset(login) when is_binary(login) do
    case get_account_by_login(login) do
      %Account{disabled_by: nil} = account ->
        token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

        {:ok, account} =
          account
          |> Ecto.Changeset.change(
            reset_token_hash: hash_reset_token(token),
            reset_token_expires_at: DateTime.add(DateTime.utc_now(:second), @reset_token_ttl_seconds)
          )
          |> Repo.update()

        {:ok, account, token}

      _ ->
        :error
    end
  end

  @doc "The account a live (unexpired, unused) reset token belongs to, or `nil`."
  def get_account_by_reset_token(token) when is_binary(token) do
    # Looked up by the token's hash: a 256-bit random preimage can't be probed through
    # equality-lookup timing, so no separate constant-time compare is needed.
    hash = hash_reset_token(token)
    now = DateTime.utc_now()

    Repo.one(
      from a in Account,
        where:
          a.reset_token_hash == ^hash and a.reset_token_expires_at > ^now and
            is_nil(a.disabled_by)
    )
  end

  @doc "Sets a new password for a live reset token and burns the token. Single-use."
  def reset_password_with_token(token, new_password) when is_binary(token) do
    hash = hash_reset_token(token)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      # Row lock so two concurrent submissions can't both spend the same token.
      account =
        Repo.one(
          from a in Account,
            where:
              a.reset_token_hash == ^hash and a.reset_token_expires_at > ^now and
                is_nil(a.disabled_by),
            lock: "FOR UPDATE"
        )

      with %Account{} <- account,
           {:ok, account} <-
             account
             |> Account.password_changeset(new_password)
             |> Ecto.Changeset.change(reset_token_hash: nil, reset_token_expires_at: nil)
             |> Repo.update() do
        account
      else
        nil -> Repo.rollback(:invalid_token)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp hash_reset_token(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

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

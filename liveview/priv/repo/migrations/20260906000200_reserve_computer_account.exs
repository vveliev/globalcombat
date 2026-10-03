defmodule GlobalCombat.Repo.Migrations.ReserveComputerAccount do
  use Ecto.Migration

  # `Games.Server`/`Engine.Game` treat account 1 (`Accounts.computer_account_id/0`) as "the
  # Computer seat" (`server.ex`'s `computer_seat?/1`, `Engine.Game.reset_done_flags/1`) — a
  # convention that
  # only held in the legacy database because a real `Computer` row had occupied id 1 since
  # whenever that production table was first seeded. Nothing recreates that fact for a fresh
  # `mix ecto.create && mix ecto.migrate` database: on a from-scratch DB (every CI run, every
  # dev/test setup), `account.id` starts its AUTO_INCREMENT at 1 with no seed claiming it, so
  # whichever account happens to be the first one ever registered in the whole run — including,
  # intermittently, a test's own throwaway account — silently becomes "the Computer". When that
  # coincidence lands on a test that then creates a Training Mode game as that same account,
  # `GameCreateLive`'s `Games.join(game_id, account.id, account.name)` (as itself) followed by
  # `Games.join(game_id, 1, "Computer")` both target the same seat, and the second join crashes
  # its LiveView with `{:error, :already_joined}` — this is what actually made `smoke_test.exs`
  # (and `main`) intermittently red, not the combat-resolution assertion also fixed alongside this.
  #
  # Inserting this row here, in a migration, claims id 1 before the application (or a test) ever
  # gets a chance to — migrations run to completion before `mix coveralls`/`mix phx.server`
  # accepts any registration, so this is deterministic, not a race won most of the time.
  #
  # Safe on a database that already has rows. The insert only happens when id 1 is free, so it no
  # longer fails with a duplicate key — which, run as part of the dev container's `migrate &&
  # phx.server` boot chain, stopped the server from starting at all. When id 1 is already taken:
  #
  #   * by a `Computer` row (a legacy import, or this migration run before) — nothing to do;
  #   * by some other account (a dev database seeded before this migration existed, where e.g.
  #     `modern_player` got id 1) — it is left exactly as it is, with a warning. Renumbering a
  #     real account would mean rewriting every row that references it (logins, seats, tourney
  #     entries, messages), and deleting it would lose data; neither is a migration's call to
  #     make. On such a database that account keeps acting as the Computer seat, which only
  #     matters if it also creates Training Mode games; `mix ecto.reset` gives a clean one.
  #
  # Production (the legacy data) always had the Computer at id 1, so there it is a no-op.
  def up do
    case repo().query!("SELECT name FROM account WHERE id = 1").rows do
      [] ->
        repo().query!("""
        INSERT INTO account (id, name, email, password, signed_up, inserted_at, updated_at)
        VALUES (
          1,
          'Computer',
          'computer@reserved.globalcombat.invalid',
          '!reserved-system-account-not-a-real-login!',
          UTC_TIMESTAMP(),
          UTC_TIMESTAMP(),
          UTC_TIMESTAMP()
        )
        """)

      [["Computer"]] ->
        :ok

      [[name]] ->
        IO.warn(
          "account id 1 is #{inspect(name)}, not the reserved Computer account; leaving it " <>
            "in place (it will act as the Training Mode Computer seat). Run `mix ecto.reset` " <>
            "for a database with a real Computer account.",
          []
        )
    end
  end

  def down do
    execute("DELETE FROM account WHERE id = 1 AND name = 'Computer'")
  end
end

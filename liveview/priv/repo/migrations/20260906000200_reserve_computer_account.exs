defmodule GlobalCombat.Repo.Migrations.ReserveComputerAccount do
  use Ecto.Migration

  # `Games.Server`/`Engine.Game` hardcode `account_id == 1` as "the Computer seat"
  # (`server.ex`'s `computer_seat?/1`, `Engine.Game.reset_done_flags/1`) — a convention that
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
  def up do
    execute("""
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
  end

  def down do
    execute("DELETE FROM account WHERE id = 1 AND name = 'Computer'")
  end
end

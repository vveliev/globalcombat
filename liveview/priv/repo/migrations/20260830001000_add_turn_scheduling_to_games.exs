defmodule GlobalCombat.Repo.Migrations.AddTurnSchedulingToGames do
  use Ecto.Migration

  # GIF-68: the fields a periodic scheduler needs to decide "is this game due for a turn" —
  # ported from `globalcombat.game`'s `turn`/`turn_length`/`prev_turn_time`/`last_turn_time`
  # (docs/schema-map.md §3.5, all listed `dead` there because that table itself is dead — see
  # §1.1) onto the live `games` table (`gc_games.game`), the same move §3.8 already made for
  # `id`/`status`/`serialized`/`private`.
  #
  # `realtime` (also in globalcombat.game §3.5) is deliberately NOT carried forward: the schema
  # map already noted "no corresponding Game.cs field found... may have been dead even before
  # the blob model, not just superseded", and GIF-68's own design pass confirmed it — every
  # `RunTurn()` call site (`Game.Done`'s all-players-done fast path, `Game.ForceTurn`'s lazy
  # `TimeLeft <= 0` check) runs off the same single `TurnLength`/`LastTurnTime` mechanism
  # regardless of any per-game mode flag. There is no dual "realtime vs turn-based" game type to
  # resurrect a column for; a null `turn_length` already means "not scheduler-managed".
  def change do
    alter table(:games) do
      add :turn, :integer, null: false, default: 1
      add :turn_length, :integer
      add :prev_turn_time, :utc_datetime
      add :last_turn_time, :utc_datetime
    end

    # Matches GlobalCombat.Games.Scheduling.list_due/1's WHERE clause (status, non-null
    # turn_length/last_turn_time, then the datetime_add comparison) so the periodic sweep does
    # an index scan instead of a table scan as the games table grows.
    create index(:games, [:status, :turn_length, :last_turn_time])
  end
end

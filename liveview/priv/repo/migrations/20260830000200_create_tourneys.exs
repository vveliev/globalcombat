defmodule GlobalCombat.Repo.Migrations.CreateTourneys do
  use Ecto.Migration

  # Column shape follows docs/schema-map.md §3.11-§3.13 (`globalcombat.tourney`/`tourneygame`/
  # `tourneyplayer`, all live). Table names are kept verbatim from the legacy DDL (no rename
  # needed -- no collision like `game`/`player`, see §1.1). Field names are normalized to
  # idiomatic snake_case (this is a fresh target-shape table, same approach as the `account`
  # migration): `gamesize` -> `game_size`, `doubleelim` -> `double_elimination`,
  # `AutoStart`/`Recurring`/`OptionGameId` -> `auto_start`/`recurring`/`option_game_id`,
  # `players` -> `max_players` (matches `Tourney.MaxPlayers`).
  #
  # Dropped: `curplayers` (never actually read back in `Tourney.Load` -- `CurrentPlayers` is
  # computed from `Players.Count` in the live C# model, so it's derived here too, via a
  # `tourneyplayer` count, rather than trusted as a stored counter that can drift). `kitty`/
  # `cost`/`Options` -- dead columns tied to the payment subsystem per the schema-map, and
  # `Web/Models/Tourney.cs` itself has them commented out of the live model (Tourney.cs:25-27).
  def change do
    create table(:tourney) do
      add :name, :string, null: false
      add :description, :string
      add :status, :string, null: false, default: "New"

      add :max_players, :integer, null: false, default: 0
      add :create_time, :utc_datetime
      add :start_time, :utc_datetime
      add :end_time, :utc_datetime

      add :game_size, :integer, null: false, default: 2
      add :winners, :integer, null: false, default: 1
      add :double_elimination, :boolean, null: false, default: false

      add :auto_start, :boolean, null: false, default: true
      add :recurring, :boolean, null: false, default: false
      add :option_game_id, :integer, null: false, default: 700_460
    end

    # `tourneygame` (docs/schema-map.md §3.12). `game_size` is a deliberate addition beyond the
    # legacy 7 columns: the original app got a bracket round's per-game player count from the
    # live in-memory `TourneyRound`/`Game.MaxPlayers` (the latter inside the GIF-25 blob), which
    # this port doesn't have -- BuildRounds already computes it per round, so it's persisted
    # here instead of re-derived, bridging the gap until full game persistence (GIF-30) lands.
    create table(:tourneygame) do
      add :tourney_id, references(:tourney, on_delete: :delete_all), null: false
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :game_num, :integer, null: false
      add :round, :integer, null: false
      add :game_size, :integer, null: false
      add :winners, :integer, null: false
      add :winner_round, :integer, null: false, default: 0
      add :loser_round, :integer, null: false, default: 0
    end

    create unique_index(:tourneygame, [:game_id])
    create index(:tourneygame, [:tourney_id, :round])

    # `tourneyplayer` (docs/schema-map.md §3.13) -- composite PK in the legacy DDL, modeled here
    # as a surrogate id + unique index, same approach as `account_login`.
    create table(:tourneyplayer) do
      add :tourney_id, references(:tourney, on_delete: :delete_all), null: false
      add :account_id, references(:account, on_delete: :delete_all), null: false
    end

    create unique_index(:tourneyplayer, [:tourney_id, :account_id])
  end
end

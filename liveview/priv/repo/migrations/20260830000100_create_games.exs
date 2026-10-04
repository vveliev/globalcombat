defmodule GlobalCombat.Repo.Migrations.CreateGames do
  use Ecto.Migration

  # Minimal live-table port of `gc_games.game`/`gc_games.player` (docs/schema-map.md §1.1,
  # §3.8-3.9) -- the *only* columns confirmed live by GameServer.cs's `CreateDB()` call sites.
  # `serialized` (the ProtoBuf game-state blob holding turn state, player roster, elimination
  # places, etc.) belongs to the game-state transport decision (ADR-0001), not this migration.
  # This table exists in this port only so a tourney bracket round has something concrete for
  # `tourneygame.game_id` to point at and to record who has joined which bracket slot -- full
  # live play (turn resolution wired to persistence, the real board LiveView) is the board
  # port's scope.
  def change do
    create table(:games) do
      add :status, :integer, null: false, default: 0
      add :private, :boolean, null: false, default: false
    end

    create index(:games, [:status])

    create table(:game_players) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :account_id, references(:account, on_delete: :delete_all), null: false
      add :is_invite, :boolean, null: false, default: false
    end

    create unique_index(:game_players, [:account_id, :game_id])
  end
end

defmodule GlobalCombat.Repo.Migrations.CreateGamePlayers do
  use Ecto.Migration

  # `gc_games.player` (docs/schema-map.md §3.9) — the live join table between `games` and
  # `account`, distinct from the dead `globalcombat.player` (per-area game state, superseded by
  # `games.serialized`). `is_invite` distinguishes an accepted seat (false, `PlayerJoined`) from
  # a pending invite (true, `PlayerInvited`).
  def change do
    create table(:game_players) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :account_id, references(:account, on_delete: :delete_all), null: false
      add :is_invite, :boolean, null: false, default: false
    end

    create index(:game_players, [:account_id, :is_invite])
    create unique_index(:game_players, [:game_id, :account_id])
  end
end

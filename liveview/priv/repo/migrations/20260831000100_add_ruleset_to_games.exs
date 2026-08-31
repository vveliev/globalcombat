defmodule GlobalCombat.Repo.Migrations.AddRulesetToGames do
  use Ecto.Migration

  # GIF-112: the `games` row never persisted the ruleset a lobby was created with (map/fog/
  # non-random/reverse-attack-order/minimum-armies live only in `GlobalCombat.Games.Server`'s
  # in-memory state today, mirrored into `serialized` only once a game starts). That made
  # `tourney.option_game_id` -- meant to let a tourney admin point every bracket game at an
  # existing game's ruleset, the way `Web/Models/Tourney.cs`'s `OptionGame` getter reads a real
  # DB-backed `Game` row -- unimplementable: there was nothing durable to read back regardless
  # of whether the referenced game had ever been played. These columns close that gap; see
  # `GlobalCombat.Games.Live.create_game/1` (writes them alongside starting the live process)
  # and `GlobalCombat.Tourneys.create_round_games/3` (reads them off `option_game_id`).
  def change do
    alter table(:games) do
      add :map_name, :string, null: false, default: "original"
      add :is_fogged, :boolean, null: false, default: false
      add :is_non_random, :boolean, null: false, default: false
      add :reverse_attack_order, :boolean, null: false, default: false
      add :minimum_armies, :integer, null: false, default: 3
    end
  end
end

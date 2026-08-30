defmodule GlobalCombat.Games.Game do
  use Ecto.Schema

  # `gc_games.game` — the live game table (docs/schema-map.md §1.1), not the dead
  # `globalcombat.game`. `serialized` is the ProtoBuf blob `GlobalCombat.Core.Game.Save()`
  # writes; see `GlobalCombat.Games.GameSummary` for how it's decoded for display.
  schema "games" do
    field :status, :integer, default: 0
    field :serialized, :binary
    field :private, :boolean, default: false

    has_many :game_players, GlobalCombat.Games.GamePlayer
  end
end

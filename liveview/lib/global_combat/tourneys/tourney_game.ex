defmodule GlobalCombat.Tourneys.TourneyGame do
  @moduledoc "Port of the `tourneygame` row (docs/schema-map.md §3.12) linking a bracket slot to a `GlobalCombat.Games.Game`."

  use Ecto.Schema

  schema "tourneygame" do
    belongs_to :tourney, GlobalCombat.Tourneys.Tourney
    belongs_to :game, GlobalCombat.Games.Game

    field :game_num, :integer
    field :round, :integer
    field :game_size, :integer
    field :winners, :integer
    field :winner_round, :integer, default: 0
    field :loser_round, :integer, default: 0
  end
end

defmodule GlobalCombat.Games.GamePlayer do
  @moduledoc "Port of the live `gc_games.player` row (docs/schema-map.md §3.9)."

  use Ecto.Schema

  schema "game_players" do
    field :is_invite, :boolean, default: false

    belongs_to :game, GlobalCombat.Games.Game
    belongs_to :account, GlobalCombat.Accounts.Account
  end
end

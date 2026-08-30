defmodule GlobalCombat.Tourneys.TourneyPlayer do
  @moduledoc "Port of the `tourneyplayer` row (docs/schema-map.md §3.13) -- a signed-up seat."

  use Ecto.Schema

  schema "tourneyplayer" do
    belongs_to :tourney, GlobalCombat.Tourneys.Tourney
    belongs_to :account, GlobalCombat.Accounts.Account
  end
end

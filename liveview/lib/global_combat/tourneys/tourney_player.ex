defmodule GlobalCombat.Tourneys.TourneyPlayer do
  use Ecto.Schema

  # `globalcombat.tourneyplayer` (docs/schema-map.md §3.13), composite-keyed in the legacy
  # schema; a surrogate id is fine here since nothing depends on the composite PK shape.
  schema "tourneyplayer" do
    belongs_to :tourney, GlobalCombat.Tourneys.Tourney
    belongs_to :account, GlobalCombat.Accounts.Account
  end
end

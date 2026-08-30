defmodule GlobalCombat.Tourneys.Tourney do
  use Ecto.Schema

  @statuses [new: "New", running: "Running", finished: "Finished"]

  # Minimal slice of `globalcombat.tourney` (docs/schema-map.md §3.11) — only what
  # `HomeController.Index` needs to list/link tourneys (GIF-33). The bracket itself
  # (`tourneygame`, `TourneyController`) is out of scope here.
  schema "tourney" do
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :new
  end
end

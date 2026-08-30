defmodule GlobalCombat.Repo.Migrations.CreateTourneys do
  use Ecto.Migration

  # Minimal slice of `globalcombat.tourney`/`tourneyplayer` (docs/schema-map.md §3.11/§3.13) —
  # only what Home/Index needs to render "Tournaments to Join" and "Your Recent Tourneys"
  # (`Web/Controllers/HomeController.cs:24-50`). The tournament bracket itself
  # (`Web/Controllers/TourneyController.cs`, `tourneygame`) is out of scope for GIF-33; this
  # table exists so Home can list/link tourneys, not to run them.
  def change do
    create table(:tourney) do
      add :name, :string, null: false
      add :status, :string, null: false, default: "New"
    end

    create table(:tourneyplayer, primary_key: false) do
      add :tourney_id, references(:tourney, on_delete: :delete_all), null: false
      add :account_id, references(:account, on_delete: :delete_all), null: false
    end

    create unique_index(:tourneyplayer, [:tourney_id, :account_id])
    create index(:tourney, [:status])
  end
end

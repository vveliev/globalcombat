defmodule GlobalCombat.Repo.Migrations.AddLastTurnEventsToGames do
  use Ecto.Migration

  # GIF-185: the resolution log `GlobalCombat.Engine.Game.resolve_turn/1` returns alongside the
  # (unchanged) resolved state -- kept in its own column rather than folded into `serialized`,
  # since that column is the ProtoBuf `Game` message the .NET oracle and the differential harness
  # both speak, and this log has no oracle-side counterpart to keep in sync with.
  def change do
    alter table(:games) do
      add :last_turn_events, :binary
    end
  end
end

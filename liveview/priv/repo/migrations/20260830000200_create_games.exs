defmodule GlobalCombat.Repo.Migrations.CreateGames do
  use Ecto.Migration

  # This is `gc_games.game` from the legacy two-schema split, not the dead `globalcombat.game`
  # — see docs/schema-map.md §1.1. Renamed `games`/`game_players` in this single-repo port to
  # avoid colliding with the dead `globalcombat.game`/`globalcombat.player` tables, which are
  # out of scope (superseded by `serialized`, per §1.1) and never modeled here.
  #
  # `serialized` is the ProtoBuf blob GIF-25's gRPC boundary owns; GIF-33 (this port) reads it
  # locally with the already-generated `GlobalCombat.GrpcHost.Game` protobuf module purely to
  # render read-only game-list summaries (name/turn/players) on Home/PlayerInfo — no gRPC round
  # trip needed for that, since the module already speaks this exact wire format (ADR-0001).
  def change do
    create table(:games) do
      add :status, :integer, null: false, default: 0
      add :serialized, :binary
      add :private, :boolean, null: false, default: false
    end

    create index(:games, [:status, :private])
  end
end

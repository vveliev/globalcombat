defmodule GlobalCombat.Repo.Migrations.AddSerializedToGames do
  use Ecto.Migration

  # `serialized` is the ProtoBuf blob GIF-25's gRPC boundary owns; GIF-33 reads it locally with
  # the already-generated `GlobalCombat.GrpcHost.Game` protobuf module purely to render
  # read-only game-list summaries (name/turn/players) on Home/PlayerInfo -- no gRPC round trip
  # needed for that, since the module already speaks this exact wire format (ADR-0001). Added as
  # a follow-up migration rather than folded into `20260830000100_create_games.exs` because that
  # migration landed on main (GIF-32) before this column's need was merged in.
  def change do
    alter table(:games) do
      add :serialized, :binary
    end
  end
end

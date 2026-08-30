defmodule GlobalCombat.Games.Game do
  @moduledoc """
  Port of the live `gc_games.game` row (docs/schema-map.md §3.8) -- id/status/private, plus the
  ProtoBuf blob `GlobalCombat.Core.Game.Save()` writes to `serialized`. `GlobalCombat.Games.
  GameSummary` decodes that blob locally to render read-only game-list summaries on Home/
  PlayerInfo (GIF-33) -- no gRPC round trip needed for that, since the already-generated wire
  module speaks this exact format (ADR-0001). The blob's actual play-state semantics (turn
  resolution, the board LiveView) are GIF-25/GIF-28/GIF-30's scope, not this schema's.
  """

  use Ecto.Schema

  @statuses [new: 0, active: 1, finished: 2]

  schema "games" do
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :serialized, :binary
    field :private, :boolean, default: false

    # GIF-68: scheduler-read turn-timing fields (docs/schema-map.md §3.5's `dead` columns,
    # carried forward onto this live table — see the migration for why `realtime` is not among
    # them). `turn_length` nil means "not scheduler-managed"; `GlobalCombat.Games.Scheduling`
    # never selects such a row as due.
    field :turn, :integer, default: 1
    field :turn_length, :integer
    field :prev_turn_time, :utc_datetime
    field :last_turn_time, :utc_datetime

    has_many :game_players, GlobalCombat.Games.GamePlayer
  end
end

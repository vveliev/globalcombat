defmodule GlobalCombat.Games.Game do
  @moduledoc """
  Port of the live `gc_games.game` row (docs/schema-map.md §3.8) -- id/status/private only.
  The actual turn state (`GlobalCombat.Core/Game.cs`'s `[ProtoMember]` fields) lives in the
  `serialized` blob column, out of scope here (GIF-25); see `priv/repo/migrations/*_create_games.exs`.
  """

  use Ecto.Schema

  @statuses [new: 0, active: 1, finished: 2]

  schema "games" do
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :private, :boolean, default: false

    has_many :game_players, GlobalCombat.Games.GamePlayer
  end
end

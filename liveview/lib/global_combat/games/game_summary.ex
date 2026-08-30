defmodule GlobalCombat.Games.GameSummary do
  @moduledoc """
  Read-only projection of a decoded game, for the game-list displays on Home/PlayerInfo
  (GIF-33) — ports the display-relevant subset of `GlobalCombat.Core/Game.cs`'s
  `DisplayGameStatus` (`Web/Views/Home/Index.cshtml`, `PlayerInfo.cshtml`).

  Decodes `games.serialized` locally with the already-generated `GlobalCombat.GrpcHost.Game`
  protobuf module (from `proto/game_engine.proto`) instead of round-tripping through gRPC:
  ADR-0001 picked `Game`/`Player`/`Area` as the wire contract precisely so no shadow DTO would
  be needed, and protobuf-net's wire format for a `[ProtoContract]` class with explicit field
  numbers *is* standard protobuf — the same bytes `GlobalCombat.Core.Game.Save()` writes to
  `gc_games.game.serialized` decode directly with this module. No .NET process needs to be
  running to render this read-only list.

  Deliberately omits `TimeLeft` (needs a `Bcl.DateTime` → `DateTime` conversion — protobuf-net's
  epoch/scale surrogate for .NET's `DateTime`, not modeled anywhere in this port yet) and the
  per-player status pips (`p.gif`/`pc.gif`/`pd.gif`/etc., `Game.cs:791-826`) — both are
  turn-countdown/board-status concerns that belong to the live game board (GIF-30), not this
  read-only summary list.
  """

  defstruct [
    :id,
    :name,
    :status,
    :max_players,
    :current_players,
    :turn,
    :is_private,
    :is_fogged,
    :tourney_id,
    :players
  ]

  alias GlobalCombat.GrpcHost

  @doc "Builds a summary from a `GlobalCombat.Games.Game` row."
  def from_row(%{id: id, serialized: nil}) do
    %__MODULE__{id: id, name: "Game ##{id}", status: :open, current_players: 0, players: []}
  end

  def from_row(%{id: id, serialized: bytes}) do
    game = GrpcHost.Game.decode(bytes)
    players = Map.fetch!(game, :Players)

    %__MODULE__{
      id: id,
      name: present(Map.fetch!(game, :GameName)) || "Game ##{id}",
      status: status(game),
      max_players: Map.fetch!(game, :MaxPlayers),
      current_players: length(players),
      turn: Map.fetch!(game, :Turn),
      is_private: Map.fetch!(game, :IsPrivate),
      is_fogged: Map.fetch!(game, :IsFogged),
      tourney_id: Map.fetch!(game, :TourneyId),
      players: Enum.map(players, &player_summary/1)
    }
  end

  defp player_summary(p) do
    place = Map.fetch!(p, :Place)

    %{
      account_id: Map.fetch!(p, :AccountId),
      name: Map.fetch!(p, :Name),
      done: Map.fetch!(p, :Done),
      eliminated: place > 0,
      place: place
    }
  end

  # Mirrors `Game.cs`'s `Status` computed property (`GlobalCombat.Core/Game.cs:126-134`).
  defp status(game) do
    cond do
      not Map.fetch!(game, :Started) -> :open
      Map.fetch!(game, :Ended) -> :finished
      true -> :running
    end
  end

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(name), do: name
end

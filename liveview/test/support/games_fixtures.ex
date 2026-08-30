defmodule GlobalCombat.GamesFixtures do
  @moduledoc "Test helpers for `GlobalCombat.Games` — builds `games`/`game_players` rows with real protobuf-encoded state."

  alias GlobalCombat.Games.{Game, GamePlayer}
  alias GlobalCombat.GrpcHost
  alias GlobalCombat.Repo

  @doc """
  Encodes a minimal but valid `GlobalCombat.GrpcHost.Game` with `GlobalCombat.GrpcHost.Game.
  encode/1` (the same generated protobuf module `GlobalCombat.Games.GameSummary` decodes with)
  and inserts a `games` row wrapping it, plus one `game_players` row per `{account_id, opts}`
  pair in `players`.
  """
  def game_fixture(attrs \\ %{}, players \\ []) do
    attrs = Map.new(attrs)
    started = Map.get(attrs, :started, false)
    ended = Map.get(attrs, :ended, false)

    wire_game = %GrpcHost.Game{
      Id: 0,
      GameName: Map.get(attrs, :game_name, ""),
      MaxPlayers: Map.get(attrs, :max_players, 4),
      Turn: Map.get(attrs, :turn, 0),
      Started: started,
      Ended: ended,
      IsPrivate: Map.get(attrs, :is_private, false),
      IsFogged: Map.get(attrs, :is_fogged, false),
      TourneyId: Map.get(attrs, :tourney_id, 0),
      Players:
        Enum.map(players, fn {account_id, opts} ->
          opts = Map.new(opts)

          %GrpcHost.Player{
            AccountId: account_id,
            Number: Map.get(opts, :number, account_id),
            Name: Map.get(opts, :name, "player#{account_id}"),
            Done: Map.get(opts, :done, false),
            Place: Map.get(opts, :place, 0)
          }
        end)
    }

    status =
      case Map.get(attrs, :status) do
        nil -> if(started, do: if(ended, do: 2, else: 1), else: 0)
        explicit -> explicit
      end

    game =
      %Game{
        status: status,
        private: Map.get(attrs, :is_private, false),
        serialized: GrpcHost.Game.encode(wire_game)
      }
      |> Repo.insert!()

    Enum.each(players, fn {account_id, opts} ->
      opts = Map.new(opts)

      %GamePlayer{
        game_id: game.id,
        account_id: account_id,
        is_invite: Map.get(opts, :is_invite, false)
      }
      |> Repo.insert!()
    end)

    game
  end
end

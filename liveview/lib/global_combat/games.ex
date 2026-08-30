defmodule GlobalCombat.Games do
  @moduledoc """
  Minimal port of the live-table slice of `Web/Models/GameServer.cs` -- just enough
  (`SaveNewGame`, `PlayerJoined`, `GetGame`) to let a tourney bracket round (GIF-32) create
  games and seat players in them. Turn resolution, the board LiveView, and the ProtoBuf blob
  that holds a game's actual play state are GIF-25/GIF-28/GIF-30's scope, not this module's.
  """

  import Ecto.Query

  alias GlobalCombat.Repo
  alias GlobalCombat.Games.{Game, GamePlayer}

  @doc "Port of `GameServer.SaveNewGame` for a freshly-created game (insert only, no blob to save)."
  def create_game(attrs \\ %{}) do
    %Game{}
    |> Ecto.Changeset.cast(attrs, [:status, :private])
    |> Repo.insert()
  end

  @doc "Port of `GameServer.GetGame`."
  def get_game(id), do: Repo.get(Game, id)

  @doc """
  Port of `GameServer.PlayerJoined`'s persistence half (the seat itself -- the live code's
  `Game.Join` in-memory roster mutation belongs to the not-yet-ported board/blob layer).
  """
  def join(%Game{} = game, account_id) do
    %GamePlayer{}
    |> Ecto.Changeset.cast(%{game_id: game.id, account_id: account_id}, [:game_id, :account_id])
    |> Ecto.Changeset.unique_constraint([:account_id, :game_id])
    |> Repo.insert()
  end

  @doc "Sets a game active once its bracket slot has filled -- there is no in-memory `Game.Start()` yet to do this implicitly."
  def mark_active(%Game{} = game) do
    game |> Ecto.Changeset.change(status: :active) |> Repo.update()
  end

  @doc "Accounts seated in a game, in join order (mirrors `Game.Players` list order pre-play)."
  def players(%Game{} = game) do
    from(gp in GamePlayer,
      join: a in assoc(gp, :account),
      where: gp.game_id == ^game.id,
      order_by: gp.id,
      select: a
    )
    |> Repo.all()
  end

  @doc "Number of seats currently filled in a game."
  def player_count(%Game{} = game) do
    Repo.aggregate(from(gp in GamePlayer, where: gp.game_id == ^game.id), :count)
  end
end

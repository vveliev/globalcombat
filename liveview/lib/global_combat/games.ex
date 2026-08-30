defmodule GlobalCombat.Games do
  @moduledoc """
  Port of the live-table slice of `Web/Models/GameServer.cs` -- both mutation (`SaveNewGame`,
  `PlayerJoined`, `GetGame`, just enough to let a tourney bracket round (GIF-32) create games
  and seat players in them) and the read-side game listings for Home/PlayerInfo
  (`GetNewGames`/`GetPlayerGames`, GIF-33) against `gc_games.game`/`player` (renamed `games`/
  `game_players` in this single-repo port, docs/schema-map.md §1.1). Turn resolution, the board
  LiveView, and the ProtoBuf blob's actual play-state semantics are GIF-25/GIF-28/GIF-30's
  scope, not this module's -- the read side only ever decodes `serialized` for display, via
  `GlobalCombat.Games.GameSummary`. The GIF-30 in-memory board lives in `GlobalCombat.Games.Live`
  (renamed from an original `GlobalCombat.Games` to avoid colliding with this module once the
  two landed together); the two don't share state yet -- see `GlobalCombat.Games.Server`'s
  moduledoc for that follow-up.
  """

  import Ecto.Query

  alias GlobalCombat.Games.{Game, GamePlayer, GameSummary}
  alias GlobalCombat.Repo

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

  @doc "Ports `GameServer.GetNewGames()` — open, public games, most recent first."
  def list_new_games do
    from(g in Game, where: g.status == :new and g.private == false, order_by: [desc: g.id])
    |> Repo.all()
    |> Enum.map(&GameSummary.from_row/1)
  end

  @doc """
  Ports `GameServer.GetPlayerGames(accountId, allGames, invites)`.

    * default (`invites: false, all_games: false`) — the account's accepted, still-open seats
      (`is_invite = false and status != finished`), matching `HomeController.Index`'s "Your
      Current Games".
    * `all_games: true` — every accepted seat regardless of status, most recent first, capped
      at 100 (matches the C#'s `limit 100`), used by `PlayerInfo?AllGames=1`.
    * `invites: true` — pending invites, matching "Games Invites" / `list_invited_games/1`.
  """
  def list_player_games(account_id, opts \\ []) do
    all_games = Keyword.get(opts, :all_games, false)
    invites = Keyword.get(opts, :invites, false)

    base =
      from gp in GamePlayer,
        join: g in Game,
        on: g.id == gp.game_id,
        where: gp.account_id == ^account_id,
        select: g

    query =
      cond do
        invites ->
          from [gp, g] in base,
            where: gp.is_invite == true and g.status != :finished,
            order_by: [desc: g.id]

        all_games ->
          from [gp, g] in base,
            where: gp.is_invite == false,
            order_by: [desc: g.id],
            limit: 100

        true ->
          from [gp, g] in base,
            where: gp.is_invite == false and g.status != :finished,
            order_by: [desc: g.id]
      end

    query |> Repo.all() |> Enum.map(&GameSummary.from_row/1)
  end

  @doc "Ports `GetPlayerGames(accountId, false, true)` — the account's pending invites."
  def list_invited_games(account_id), do: list_player_games(account_id, invites: true)
end

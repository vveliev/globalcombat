defmodule GlobalCombat.Games do
  @moduledoc """
  Read-side game listing for Home/PlayerInfo (GIF-33) — ports `Web/Models/GameServer.cs`'s
  `GetNewGames`/`GetPlayerGames` against `gc_games.game`/`player` (renamed `games`/
  `game_players` in this single-repo port, docs/schema-map.md §1.1). Game *mutation*
  (create/join/turn resolution) is out of scope here — that belongs to the board (GIF-30) and
  the already-ported turn engine (GIF-28); this module only ever reads.
  """

  import Ecto.Query

  alias GlobalCombat.Games.{Game, GamePlayer, GameSummary}
  alias GlobalCombat.Repo

  @doc "Ports `GameServer.GetNewGames()` — open, public games, most recent first."
  def list_new_games do
    from(g in Game, where: g.status == 0 and g.private == false, order_by: [desc: g.id])
    |> Repo.all()
    |> Enum.map(&GameSummary.from_row/1)
  end

  @doc """
  Ports `GameServer.GetPlayerGames(accountId, allGames, invites)`.

    * default (`invites: false, all_games: false`) — the account's accepted, still-open seats
      (`is_invite = false and status < 2`), matching `HomeController.Index`'s "Your Current
      Games".
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
            where: gp.is_invite == true and g.status < 2,
            order_by: [desc: g.id]

        all_games ->
          from [gp, g] in base,
            where: gp.is_invite == false,
            order_by: [desc: g.id],
            limit: 100

        true ->
          from [gp, g] in base,
            where: gp.is_invite == false and g.status < 2,
            order_by: [desc: g.id]
      end

    query |> Repo.all() |> Enum.map(&GameSummary.from_row/1)
  end

  @doc "Ports `GetPlayerGames(accountId, false, true)` — the account's pending invites."
  def list_invited_games(account_id), do: list_player_games(account_id, invites: true)
end

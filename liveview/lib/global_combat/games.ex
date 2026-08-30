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

  @doc """
  Port of `GameServer.SaveNewGame` for a freshly-created game (insert only, no blob to save).

  `turn_length` (minutes) is optional and, per GIF-68, opts this game into the periodic turn
  scheduler once it's `mark_active/1`'d -- a `nil` `turn_length` (the default) leaves it outside
  `GlobalCombat.Games.Scheduling.list_due/1` entirely, same as today.
  """
  def create_game(attrs \\ %{}) do
    %Game{}
    |> Ecto.Changeset.cast(attrs, [:status, :private, :turn_length])
    |> Repo.insert()
  end

  @doc "Port of `GameServer.GetGame`."
  def get_game(id), do: Repo.get(Game, id)

  @doc "Same as `get_game/1` but raises if `id` has no row — for callers where a missing row is an invariant violation, not a normal outcome (e.g. `GlobalCombat.Games.Server` acting on the DB row it was started against)."
  def get_game!(id), do: Repo.get!(Game, id)

  @doc """
  Games currently `:active` — the boot-time rehydration set (GIF-74): every row a resolved
  turn-scheduler claim might target, so `GlobalCombat.Games.Supervisor` knows which
  `GlobalCombat.Games.Server` children to restart from persisted state after a node restart.
  """
  def list_active_games, do: Repo.all(from(g in Game, where: g.status == :active))

  @doc """
  Overwrites `serialized` for `game_id` (GIF-74) — `GlobalCombat.Games.Server` calls this after
  every turn it runs, win or claimed, so `games.serialized` always holds the live board's latest
  snapshot for boot-time rehydration/offline resolution to read back. A plain `update_all` by id
  rather than a fetch-then-update: the caller (`Games.Server`) is the sole writer for its own
  `game_id` by construction (one GenServer per game, `GlobalCombat.Games.TurnScheduler`'s live-
  process resolve path also routes through it rather than writing directly), so there is no
  concurrent writer to race.
  """
  def persist_serialized(game_id, serialized) do
    from(g in Game, where: g.id == ^game_id)
    |> Repo.update_all(set: [serialized: serialized])

    :ok
  end

  @doc """
  Advances `games.turn`/`prev_turn_time`/`last_turn_time` for a turn `GlobalCombat.Games.Server`
  ran on its own initiative (a player forcing the turn, or every seat marking done) rather than
  one `GlobalCombat.Games.TurnScheduler` already claimed via `GlobalCombat.Games.Scheduling.
  claim_turn/2` — that path already advanced these columns before handing off to the resolver, so
  `Games.Server` must not double-advance them there. Same reasoning as `persist_serialized/2` for
  why this is a plain `update_all`, not an optimistically-locked claim: `Games.Server` is the
  sole writer of its own game's clock columns outside a scheduler claim.
  """
  def advance_turn(game_id, turn, prev_turn_time, now) do
    from(g in Game, where: g.id == ^game_id)
    |> Repo.update_all(set: [turn: turn, prev_turn_time: prev_turn_time, last_turn_time: now])

    :ok
  end

  @doc "Marks `game_id` `:finished` (GIF-74) — once `GlobalCombat.Engine.Game.run_turn/1` sets `ended: true`, the game must stop showing up in `GlobalCombat.Games.Scheduling.list_due/1`, or the scheduler would keep claiming and bumping its turn counter forever on a game with no more turns to run."
  def finish_game(game_id) do
    from(g in Game, where: g.id == ^game_id and g.status != :finished)
    |> Repo.update_all(set: [status: :finished])

    :ok
  end

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

  @doc """
  Sets a game active once its bracket slot has filled -- there is no in-memory `Game.Start()`
  yet to do this implicitly. Stamps `last_turn_time` the same way `Game.cs`'s `Start()` does
  (`LastTurnTime = DateTime.UtcNow`), so a `turn_length`-bearing game becomes schedulable the
  moment it goes active rather than needing a first turn to run manually before the scheduler
  can see it.
  """
  def mark_active(%Game{} = game) do
    game
    |> Ecto.Changeset.change(
      status: :active,
      last_turn_time: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update()
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

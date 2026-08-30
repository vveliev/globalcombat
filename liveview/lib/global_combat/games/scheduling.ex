defmodule GlobalCombat.Games.Scheduling do
  @moduledoc """
  DB-level query + atomic claim primitives for GIF-68's turn scheduler.

  `GlobalCombat.Games.TurnScheduler` is a supervised GenServer that periodically sweeps for
  games due for a turn and needs a double-resolve guard that survives a node restart. Since a
  restarted node has no in-memory schedule to lose — the sweep just re-evaluates "is this game
  due" from `games` on every tick — that guard has to live in the database, not in the
  scheduler's process state: `claim_turn/2` is a single conditional `UPDATE ... WHERE id = ?
  AND last_turn_time = ?`, so two sweepers (or two nodes) racing on the same due game can't both
  advance it, and a crash between "found it due" and "advanced it" just leaves the row where the
  next sweep will find it due again.
  """

  import Ecto.Query

  alias GlobalCombat.Games.Game
  alias GlobalCombat.Repo

  @doc """
  Games due for a turn as of `now`: `:active`, scheduler-managed (`turn_length` set), already
  ran at least one turn (`last_turn_time` set — set on activation, mirroring `Game.cs`'s
  `Start()`), and that turn's window has elapsed. Mirrors `Game.ForceTurn`'s
  `TimeLeft.TotalSeconds <= 0` gate (`TimeLeft = LastTurnTime + TurnLength minutes - UtcNow`).
  """
  def list_due(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    from(g in Game,
      where: g.status == :active,
      where: not is_nil(g.turn_length),
      where: not is_nil(g.last_turn_time),
      where: datetime_add(g.last_turn_time, g.turn_length, "minute") <= ^now
    )
    |> Repo.all()
  end

  @doc """
  Atomically claims `game`'s current turn slot: advances `turn`/`prev_turn_time`/
  `last_turn_time` in one conditional `UPDATE`, guarded on `last_turn_time` still matching what
  `game` was read with. Returns `{:ok, claimed_game}` on the winning claim (exactly one row
  affected) or `{:error, :already_claimed}` if another sweep already claimed this game's turn
  first (zero rows affected — `game` was stale).

  Only the clock bookkeeping happens here; running the actual turn (the engine + persisting its
  resulting state) is the caller's job via a separate step, so a claim failure downstream
  doesn't get retried as "still due" until the next window elapses — same semantics as the
  original's `RunTurn()` being effectively infallible game logic, not a fallible external call.
  """
  def claim_turn(%Game{} = game, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    {count, _} =
      from(g in Game,
        where: g.id == ^game.id and g.last_turn_time == ^game.last_turn_time
      )
      |> Repo.update_all(
        set: [prev_turn_time: game.last_turn_time, last_turn_time: now, turn: game.turn + 1]
      )

    case count do
      1 ->
        {:ok,
         %{game | prev_turn_time: game.last_turn_time, last_turn_time: now, turn: game.turn + 1}}

      0 ->
        {:error, :already_claimed}
    end
  end
end

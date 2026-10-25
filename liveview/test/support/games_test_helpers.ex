defmodule GlobalCombat.GamesTestHelpers do
  @moduledoc """
  Shared helpers for tests that drive a live `GlobalCombat.Games.Server` — killing it to
  exercise rehydration, and synchronising with it (and a LiveView attached to it) without
  `Process.sleep/1`.
  """

  import ExUnit.Assertions

  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Registry, as: GamesRegistry
  alias GlobalCombat.Games.Server
  alias GlobalCombat.Games.Supervisor, as: GamesSupervisor
  alias GlobalCombat.Games.TurnLog

  @doc """
  Terminates `game_id`'s `Games.Server` and returns once its Registry entry is gone.

  Registry's own de-registration runs off a *separate* monitor on the pid than the one this
  takes, so the :DOWN landing first doesn't guarantee the ETS entry is gone yet — without the
  second wait, `Supervisor.ensure_started/1` can still see the dead pid via `Server.alive?/1`
  and skip rehydrating.
  """
  def kill_server!(game_id) do
    [{pid, _}] = Registry.lookup(GamesRegistry, game_id)
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(GamesSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    wait_until_deregistered(game_id)
  end

  @doc """
  Crashes `game_id`'s `Games.Server` with an untrappable `:kill` — unlike `kill_server!/1`'s
  `terminate_child/2`, the DynamicSupervisor sees an abnormal exit and applies the child's own
  restart strategy. Returns once the supervisor has handled the exit (and any restart it
  decided on), and the dead pid is no longer registered.
  """
  def crash_server!(game_id) do
    [{pid, _}] = Registry.lookup(GamesRegistry, game_id)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    # The supervisor's restart (if any) runs inside its own :EXIT handling, so once it has
    # answered a call that exit has been dealt with.
    _ = :sys.get_state(GamesSupervisor)
    wait_until_not_registered(game_id, pid)
  end

  defp wait_until_not_registered(game_id, pid) do
    if match?([{^pid, _}], Registry.lookup(GamesRegistry, game_id)) do
      wait_until_not_registered(game_id, pid)
    end
  end

  @doc "Spins (no sleep) until `game_id` has no Registry entry."
  def wait_until_deregistered(game_id) do
    unless Registry.lookup(GamesRegistry, game_id) == [] do
      wait_until_deregistered(game_id)
    end
  end

  @doc """
  Waits until `game_id`'s server has handled every message sent so far (a cast such as
  `set_done`, whose turn run broadcasts `:reload`), then until the LiveView behind `view` has
  handled everything in its own mailbox (that `:reload`) — `:sys.get_state/1` on each in turn,
  per the test guidelines, instead of polling `render/1` with sleeps.
  """
  def sync_game(game_id, view) do
    _ = :sys.get_state(Server.via(game_id))
    _ = :sys.get_state(view.pid)
    view
  end

  @doc """
  The attack and transfer events `seat` issued in `game_id`'s last resolved turn, read from the
  persisted `games.last_turn_events` log. An event's source area is matched against the log's
  `before_owners`, so captures made during the turn don't hide who ordered them.
  """
  def seat_moves(game_id, seat) do
    log = TurnLog.decode(GamesDb.get_game!(game_id).last_turn_events)

    Enum.filter(log.events, fn
      {:transfer, from, _to, _amount} -> log.before_owners[from] == seat
      {:attack, from, _to, _amount, _al, _dl, _captured?} -> log.before_owners[from] == seat
      _event -> false
    end)
  end
end

defmodule GlobalCombat.GamesTestHelpers do
  @moduledoc """
  Shared helpers for tests that drive a live `GlobalCombat.Games.Server` — killing it to
  exercise rehydration, and synchronising with it (and a LiveView attached to it) without
  `Process.sleep/1`.
  """

  import ExUnit.Assertions

  alias GlobalCombat.Games.Registry, as: GamesRegistry
  alias GlobalCombat.Games.Server
  alias GlobalCombat.Games.Supervisor, as: GamesSupervisor

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
end

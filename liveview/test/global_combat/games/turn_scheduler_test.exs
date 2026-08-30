defmodule GlobalCombat.Games.TurnSchedulerTest do
  use GlobalCombat.DataCase, async: true

  import ExUnit.CaptureLog
  import GlobalCombat.GamesFixtures

  alias GlobalCombat.Games.Game
  alias GlobalCombat.Games.TurnScheduler
  alias GlobalCombat.Games.TurnScheduler.SpyResolver

  # Long enough that the timer never fires during a test — every assertion drives the sweep
  # explicitly via sweep_now/1, matching how a real node's restart-recovery works (each sweep
  # re-evaluates "is this game due" from the DB with no in-memory schedule of its own).
  @never :timer.hours(1)

  defp start_scheduler(opts) do
    {:ok, pid} = TurnScheduler.start_link(Keyword.merge([name: nil, interval_ms: @never], opts))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    pid
  end

  test "claims a due game and hands it to the configured resolver" do
    game = game_fixture(%{status: :active, turn_length: 5, last_turn_time: minutes_ago(10)})
    SpyResolver.register(game.id, self())

    scheduler = start_scheduler(resolver: SpyResolver)
    assert :ok = TurnScheduler.sweep_now(scheduler)

    assert_receive {:resolved, %Game{id: id, turn: 2}}
    assert id == game.id

    assert %{turn: 2} = Repo.get!(Game, game.id)
  end

  test "leaves a game alone whose turn window has not elapsed" do
    game = game_fixture(%{status: :active, turn_length: 60, last_turn_time: minutes_ago(1)})
    SpyResolver.register(game.id, self())

    scheduler = start_scheduler(resolver: SpyResolver)
    assert :ok = TurnScheduler.sweep_now(scheduler)

    refute_receive {:resolved, _}, 50
    assert %{turn: 1} = Repo.get!(Game, game.id)
  end

  test "with no resolver configured, logs due games instead of claiming them" do
    game = game_fixture(%{status: :active, turn_length: 5, last_turn_time: minutes_ago(10)})
    scheduler = start_scheduler(resolver: nil)

    log = capture_log(fn -> assert :ok = TurnScheduler.sweep_now(scheduler) end)
    assert log =~ "1 game(s) due for a turn but no resolver is configured"

    unchanged = Repo.get!(Game, game.id)
    assert unchanged.turn == game.turn
    assert unchanged.last_turn_time == game.last_turn_time
  end

  test "a resolver error is logged, but the claim already went through and the scheduler keeps running" do
    game = game_fixture(%{status: :active, turn_length: 5, last_turn_time: minutes_ago(10)})
    SpyResolver.register(game.id, self(), {:error, :boom})

    scheduler = start_scheduler(resolver: SpyResolver)

    log = capture_log(fn -> assert :ok = TurnScheduler.sweep_now(scheduler) end)
    assert log =~ "resolver failed for game #{game.id}"
    assert Process.alive?(scheduler)

    assert %{turn: 2} = Repo.get!(Game, game.id)
  end

  defp minutes_ago(n) do
    DateTime.utc_now() |> DateTime.add(-n * 60, :second) |> DateTime.truncate(:second)
  end
end

defmodule GlobalCombat.Games.ScheduledTurnDriftTest do
  @moduledoc """
  `games.turn` has to name the same turn as the engine snapshot in `games.serialized`, however
  the turn got run. The 2026-10-23 playtest found a training game with the column at 7 while the
  board said 4: a second app instance against the same database (a host-side `mix` run next to
  the dev container) claimed three of its turns. That node had no live `Games.Server`, so it
  resolved them offline; the real node's live Server then overwrote `serialized` with its own,
  older engine on the next order, and only the claims' `turn + 1` bumps survived.
  """
  use GlobalCombat.DataCase, async: true

  alias GlobalCombat.Accounts
  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Game
  alias GlobalCombat.Games.Live, as: GamesLive
  alias GlobalCombat.Games.LiveResolver
  alias GlobalCombat.Games.Scheduling
  alias GlobalCombat.Games.Server
  alias GlobalCombat.Games.TurnScheduler
  alias GlobalCombat.GrpcHost

  @alice 101

  test "games.turn follows the engine across scheduler claims on a live training game" do
    game_id = start_training_game()
    scheduler = start_scheduler()
    assert_turn_in_sync(game_id, 1)

    for expected <- 2..4 do
      make_due(game_id)
      assert :ok = TurnScheduler.sweep_now(scheduler)
      assert_turn_in_sync(game_id, expected)
    end
  end

  test "a claim resolved somewhere other than the live Server doesn't move games.turn on its own" do
    game_id = start_training_game()
    scheduler = start_scheduler()

    # Another node's scheduler wins the claim. Whatever it then resolves, this node's live
    # Server still holds turn 1 and rewrites `serialized` from it on the next order.
    make_due(game_id)
    assert {:ok, _claimed} = game_id |> GamesDb.get_game!() |> Scheduling.claim_turn()
    queue_an_order(game_id)
    assert_turn_in_sync(game_id, 1)

    make_due(game_id)
    assert :ok = TurnScheduler.sweep_now(scheduler)
    assert_turn_in_sync(game_id, 2)
  end

  defp start_training_game do
    game_id =
      GamesLive.create_game(%{map_name: :original, is_training: true, turn_length_minutes: 5})

    {:ok, 1} = GamesLive.join(game_id, @alice, "Alice")
    {:ok, 2} = GamesLive.join(game_id, Accounts.computer_account_id(), "Computer")
    :ok = GamesLive.start_game(game_id, @alice)
    game_id
  end

  defp start_scheduler do
    {:ok, pid} =
      TurnScheduler.start_link(name: nil, interval_ms: :timer.hours(1), resolver: LiveResolver)

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    pid
  end

  # Pushes the current turn's window into the past so the next sweep finds the game due.
  defp make_due(game_id) do
    past = DateTime.utc_now() |> DateTime.add(-10 * 60, :second) |> DateTime.truncate(:second)
    from(g in Game, where: g.id == ^game_id) |> Repo.update_all(set: [last_turn_time: past])
    # The live Server guards its own clock writes on the `last_turn_time` it last saw.
    :sys.replace_state(Server.via(game_id), &%{&1 | db_last_turn_time: past})
  end

  defp queue_an_order(game_id) do
    %{engine: engine} = :sys.get_state(Server.via(game_id))
    {area_number, _area} = Enum.find(engine.areas, fn {_n, a} -> a.owner_number == 1 end)
    :ok = GamesLive.assign(game_id, @alice, area_number, 1)
    # assign/4 is a cast; a call behind it waits for it to land.
    {:playing, _view} = GamesLive.player_view(game_id, @alice)
  end

  defp assert_turn_in_sync(game_id, expected) do
    %{engine: engine} = :sys.get_state(Server.via(game_id))
    row = GamesDb.get_game!(game_id)
    snapshot_turn = row.serialized |> GrpcHost.Game.decode() |> Map.fetch!(:Turn)

    assert {engine.turn, snapshot_turn, row.turn} == {expected, expected, expected}
  end
end

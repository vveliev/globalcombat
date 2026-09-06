defmodule GlobalCombat.Games.TurnLogTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Games.TurnLog

  describe "snapshot/3" do
    test "stamps new_engine's turn and captures old_engine's owner numbers only" do
      old_engine = %Engine{
        turn: 2,
        areas: %{
          1 => %Engine.Area{number: 1, owner_number: 1, armies: 99},
          2 => %Engine.Area{number: 2, owner_number: nil, armies: 5}
        }
      }

      new_engine = %Engine{old_engine | turn: 3}
      events = [{:assign, 1, 4}]

      log = TurnLog.snapshot(old_engine, new_engine, events)

      assert log.turn == 3
      assert log.events == events
      assert log.before_owners == %{1 => 1, 2 => nil}
    end
  end

  describe "encode/1 and decode/1" do
    test "round-trips a log" do
      log = %TurnLog{turn: 5, events: [{:eliminated, 2}], before_owners: %{1 => 1}}

      assert log |> TurnLog.encode() |> TurnLog.decode() == log
    end

    test "decode(nil) is the empty log — a rehydrate before this column existed, or no turn resolved yet" do
      assert TurnLog.decode(nil) == %TurnLog{}
    end
  end
end

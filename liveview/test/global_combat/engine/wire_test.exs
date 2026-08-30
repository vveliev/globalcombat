defmodule GlobalCombat.Engine.WireTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game
  alias GlobalCombat.Engine.Game.{Area, Player}
  alias GlobalCombat.Engine.Wire
  alias GlobalCombat.GrpcHost

  describe "to_wire_game/2 + from_wire_snapshot/2" do
    test "round-trips a live GlobalCombat.Games.Server's engine state through games.serialized (GIF-74)" do
      game = %Game{
        map_name: :original,
        rng: DotnetRandom.new(42),
        turn: 3,
        is_non_random: true,
        reverse_attack_order: true,
        minimum_armies: 4,
        is_training: false,
        ended: false,
        areas: %{
          1 => %Area{
            number: 1,
            owner_number: 1,
            armies: 10,
            assigned_armies: 2,
            command: :none,
            target_number: nil,
            amount: 0
          },
          2 => %Area{
            number: 2,
            owner_number: 2,
            armies: 7,
            assigned_armies: 0,
            command: :none,
            target_number: nil,
            amount: 0
          }
        },
        players: %{
          1 => %Player{
            number: 1,
            account_id: 101,
            name: "Alice",
            done: false,
            areas: 1,
            armies: 10,
            unassigned_armies: 2,
            place: 0,
            score: 0,
            score_expected: 0.0,
            rating: 1200,
            rating_change: 0
          },
          2 => %Player{
            number: 2,
            account_id: 102,
            name: "Bob",
            done: true,
            areas: 1,
            armies: 7,
            unassigned_armies: 0,
            place: 0,
            score: 0,
            score_expected: 0.0,
            rating: 1200,
            rating_change: 0
          }
        }
      }

      wire =
        Wire.to_wire_game(game,
          game_id: 55,
          turn_length_minutes: 60,
          max_players: 6,
          is_fogged: true
        )

      # Round-trips through the exact byte encoding games.serialized actually stores.
      decoded = wire |> GrpcHost.Game.encode() |> GrpcHost.Game.decode()

      assert %{engine: rehydrated, is_fogged: true, max_players: 6} =
               Wire.from_wire_snapshot(decoded, DotnetRandom.new(0))

      assert rehydrated.map_name == :original
      assert rehydrated.turn == 3
      assert rehydrated.is_non_random == true
      assert rehydrated.reverse_attack_order == true
      assert rehydrated.minimum_armies == 4
      assert rehydrated.ended == false

      assert Game.area!(rehydrated, 1).owner_number == 1
      assert Game.area!(rehydrated, 1).armies == 10
      assert Game.area!(rehydrated, 1).assigned_armies == 2
      assert Game.area!(rehydrated, 2).owner_number == 2
      assert Game.area!(rehydrated, 2).armies == 7

      assert Game.player!(rehydrated, 1).account_id == 101
      assert Game.player!(rehydrated, 1).name == "Alice"
      assert Game.player!(rehydrated, 1).unassigned_armies == 2
      assert Game.player!(rehydrated, 2).account_id == 102
      assert Game.player!(rehydrated, 2).done == true
    end
  end
end

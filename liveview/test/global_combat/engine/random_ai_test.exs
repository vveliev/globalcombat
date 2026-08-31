defmodule GlobalCombat.Engine.RandomAiTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Engine.{DotnetRandom, Game, MapInfo, RandomAi}
  alias GlobalCombat.Engine.Game.{Area, Player}

  # Round-robin deal across the real `:original` 42-area map/adjacency data (same shape
  # `Games.Server.deal_areas/2` produces), player 1 the human and player 2 the Computer seat.
  defp two_player_game(seed) do
    num_areas = MapInfo.num_areas(:original)

    areas =
      for area_number <- 1..num_areas, into: %{} do
        owner = rem(area_number - 1, 2) + 1
        {area_number, %Area{number: area_number, owner_number: owner, armies: 5}}
      end

    players = %{
      1 => %Player{number: 1, account_id: 101, name: "Human", unassigned_armies: 20},
      2 => %Player{number: 2, account_id: 1, name: "Computer", unassigned_armies: 20}
    }

    %Game{map_name: :original, rng: DotnetRandom.new(seed), areas: areas, players: players}
  end

  describe "think/2 scoped to the Computer seat (GIF-118)" do
    test "never assigns, attacks, or transfers using the human's areas, across many seeds" do
      for seed <- 1..50 do
        game = two_player_game(seed)
        result = RandomAi.think(game, 2)

        for area_number <- 1..MapInfo.num_areas(:original) do
          original = Game.area!(game, area_number)
          area = Game.area!(result, area_number)

          if original.owner_number == 1 do
            assert area.command == :none,
                   "seed #{seed}: human area #{area_number} got command #{inspect(area.command)}"

            assert area.assigned_armies == 0,
                   "seed #{seed}: human area #{area_number} got assigned_armies #{area.assigned_armies}"
          end
        end

        assert Game.player!(result, 1).unassigned_armies == 20,
               "seed #{seed}: human's unassigned army pool was spent by the Computer's think pass"
      end
    end

    test "still issues orders — scoping doesn't leave the Computer doing nothing" do
      game = two_player_game(42)
      result = RandomAi.think(game, 2)

      computer_areas = for n <- 1..MapInfo.num_areas(:original), do: Game.area!(result, n)

      assert Enum.any?(computer_areas, fn a ->
               Game.area!(game, a.number).owner_number == 2 and a.command != :none
             end)

      assert Game.player!(result, 2).unassigned_armies < 20
    end
  end

  describe "think/1 (unscoped, default) — unchanged for Harness's oracle lockstep" do
    test "can still touch areas regardless of ownership" do
      game = two_player_game(7)
      result = RandomAi.think(game)

      touched_any_human_area? =
        Enum.any?(1..MapInfo.num_areas(:original), fn n ->
          Game.area!(game, n).owner_number == 1 and
            (Game.area!(result, n).command != :none or Game.area!(result, n).assigned_armies != 0)
        end)

      assert touched_any_human_area?,
             "expected the unscoped whole-board think/1 to eventually touch a human-owned area at this seed"
    end
  end
end

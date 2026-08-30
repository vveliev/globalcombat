defmodule GlobalCombat.Tourneys.BracketTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Tourneys.Bracket
  alias GlobalCombat.Tourneys.Bracket.Round

  describe "build_rounds/1 -- single elimination" do
    test "4 initial games (8 players, 1 winner/game) shrinks 4 -> 2 -> 1" do
      result =
        Bracket.build_rounds(%{
          initial_games: 4,
          game_size: 2,
          winners: 1,
          losers: 1,
          double_elimination: false
        })

      assert result.loser_bracket == []
      assert result.final_round == nil

      assert result.winner_bracket == [
               %Round{number: 1, start_game: 1, game_count: 4, game_size: 2},
               %Round{number: 2, start_game: 5, game_count: 2, game_size: 2, winners_of_round: 1},
               %Round{number: 3, start_game: 7, game_count: 1, game_size: 2, winners_of_round: 2}
             ]
    end

    test "8 initial games shrinks 8 -> 4 -> 2 -> 1" do
      result =
        Bracket.build_rounds(%{
          initial_games: 8,
          game_size: 2,
          winners: 1,
          losers: 1,
          double_elimination: false
        })

      assert Enum.map(result.winner_bracket, & &1.game_count) == [8, 4, 2, 1]
      assert Enum.map(result.winner_bracket, & &1.number) == [1, 2, 3, 4]
      assert Enum.map(result.winner_bracket, & &1.start_game) == [1, 9, 13, 15]
    end
  end

  describe "build_rounds/1 -- double elimination" do
    test "8 initial games produces the winner bracket, loser bracket, and a final round" do
      result =
        Bracket.build_rounds(%{
          initial_games: 8,
          game_size: 2,
          winners: 1,
          losers: 1,
          double_elimination: true
        })

      assert Enum.map(result.winner_bracket, & &1.number) == [1, 2, 3, 4]
      assert Enum.map(result.loser_bracket, & &1.number) == [5, 6, 7, 8, 9, 10]
      assert result.final_round.number == 11

      # Every loser-bracket round that receives a fresh wave of winner-bracket losers records
      # it via losers_of_round; the final round points back at the last loser-bracket round via
      # the negative-number convention (Tourney.cs's `LosersOfRoundNumber = -(currentRound - 1)`).
      assert Enum.map(result.loser_bracket, & &1.losers_of_round) == [1, 2, 0, 3, 0, 4]
      assert result.final_round.losers_of_round == -10
      assert result.final_round.winners_of_round == 4
    end

    test "a full bracket accounts for every initial player exactly once per round tier" do
      result =
        Bracket.build_rounds(%{
          initial_games: 4,
          game_size: 2,
          winners: 1,
          losers: 1,
          double_elimination: true
        })

      assert Enum.map(result.winner_bracket, & &1.number) == [1, 2, 3]
      assert Enum.map(result.loser_bracket, & &1.number) == [4, 5, 6, 7]
      assert result.final_round.number == 8
    end
  end

  describe "advancement_targets/2" do
    test "round 1 winners feed round 2, no loser round in single elimination" do
      %{winner_bracket: [r1, r2, r3]} =
        Bracket.build_rounds(%{
          initial_games: 4,
          game_size: 2,
          winners: 1,
          losers: 1,
          double_elimination: false
        })

      assert Bracket.advancement_targets(r1, [r1, r2, r3]) == {2, 0}
      assert Bracket.advancement_targets(r2, [r1, r2, r3]) == {3, 0}
      assert Bracket.advancement_targets(r3, [r1, r2, r3]) == {0, 0}
    end

    test "round 1 losers drop into the loser bracket's first round in double elimination" do
      %{winner_bracket: winner_bracket, loser_bracket: loser_bracket, final_round: final_round} =
        Bracket.build_rounds(%{
          initial_games: 4,
          game_size: 2,
          winners: 1,
          losers: 1,
          double_elimination: true
        })

      all = winner_bracket ++ loser_bracket ++ [final_round]
      [r1 | _] = winner_bracket

      assert Bracket.advancement_targets(r1, all) == {2, 4}
    end
  end
end

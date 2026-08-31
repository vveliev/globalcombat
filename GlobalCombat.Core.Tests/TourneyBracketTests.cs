using System.Collections.Generic;
using System.Linq;
using GlobalCombat.Core;
using Xunit;

namespace GlobalCombat.Core.Tests
{
    // Mirrors liveview/test/global_combat/tourneys/bracket_test.exs's cases 1:1 - both suites
    // exercise the same algorithm (Tourney.cs's BuildRounds), so a divergence between them
    // signals the C# extraction or the Elixir port drifted, not just this one implementation.
    public class TourneyBracketTests
    {
        static IEnumerable<TourneyRound> AllRounds(TourneyBracket bracket) =>
            bracket.WinnerBracket
                .Concat(bracket.LoserBracket)
                .Concat(bracket.FinalRound == null ? Enumerable.Empty<TourneyRound>() : new[] { bracket.FinalRound });

        [Fact]
        public void FourInitialGamesSingleEliminationShrinksFourTwoOne()
        {
            var result = TourneyBracket.BuildRounds(initialGames: 4, gameSize: 2, winners: 1, isDoubleElimination: false);

            Assert.Empty(result.LoserBracket);
            Assert.Null(result.FinalRound);

            Assert.Equal(3, result.WinnerBracket.Count);
            Assert.Equal(new[] { 1, 2, 3 }, result.WinnerBracket.Select(r => r.Number));
            Assert.Equal(new[] { 4, 2, 1 }, result.WinnerBracket.Select(r => r.GameCount));
            Assert.Equal(new[] { 1, 5, 7 }, result.WinnerBracket.Select(r => r.StartGame));
            Assert.Equal(new[] { 2, 2, 2 }, result.WinnerBracket.Select(r => r.GameSize));
            Assert.Equal(new[] { 0, 1, 2 }, result.WinnerBracket.Select(r => r.WinnersOfRoundNumber));
        }

        [Fact]
        public void EightInitialGamesSingleEliminationShrinksEightFourTwoOne()
        {
            var result = TourneyBracket.BuildRounds(initialGames: 8, gameSize: 2, winners: 1, isDoubleElimination: false);

            Assert.Equal(new[] { 8, 4, 2, 1 }, result.WinnerBracket.Select(r => r.GameCount));
            Assert.Equal(new[] { 1, 2, 3, 4 }, result.WinnerBracket.Select(r => r.Number));
            Assert.Equal(new[] { 1, 9, 13, 15 }, result.WinnerBracket.Select(r => r.StartGame));
        }

        [Fact]
        public void EightInitialGamesDoubleEliminationProducesWinnerLoserAndFinalRounds()
        {
            var result = TourneyBracket.BuildRounds(initialGames: 8, gameSize: 2, winners: 1, isDoubleElimination: true);

            Assert.Equal(new[] { 1, 2, 3, 4 }, result.WinnerBracket.Select(r => r.Number));
            Assert.Equal(new[] { 5, 6, 7, 8, 9, 10 }, result.LoserBracket.Select(r => r.Number));
            Assert.Equal(11, result.FinalRound.Number);

            Assert.Equal(new[] { 1, 2, 0, 3, 0, 4 }, result.LoserBracket.Select(r => r.LosersOfRoundNumber));
            Assert.Equal(-10, result.FinalRound.LosersOfRoundNumber);
            Assert.Equal(4, result.FinalRound.WinnersOfRoundNumber);
        }

        [Fact]
        public void FourInitialGamesDoubleEliminationAccountsForEveryRoundTier()
        {
            var result = TourneyBracket.BuildRounds(initialGames: 4, gameSize: 2, winners: 1, isDoubleElimination: true);

            Assert.Equal(new[] { 1, 2, 3 }, result.WinnerBracket.Select(r => r.Number));
            Assert.Equal(new[] { 4, 5, 6, 7 }, result.LoserBracket.Select(r => r.Number));
            Assert.Equal(8, result.FinalRound.Number);
        }

        [Fact]
        public void Round1WinnersFeedRound2NoLoserRoundInSingleElimination()
        {
            var result = TourneyBracket.BuildRounds(initialGames: 4, gameSize: 2, winners: 1, isDoubleElimination: false);
            var all = AllRounds(result).ToList();
            var (r1, r2, r3) = (result.WinnerBracket[0], result.WinnerBracket[1], result.WinnerBracket[2]);

            Assert.Equal((2, 0), TourneyBracket.AdvancementTargets(r1, all));
            Assert.Equal((3, 0), TourneyBracket.AdvancementTargets(r2, all));
            Assert.Equal((0, 0), TourneyBracket.AdvancementTargets(r3, all));
        }

        [Fact]
        public void Round1LosersDropIntoLoserBracketFirstRoundInDoubleElimination()
        {
            var result = TourneyBracket.BuildRounds(initialGames: 4, gameSize: 2, winners: 1, isDoubleElimination: true);
            var all = AllRounds(result).ToList();
            var r1 = result.WinnerBracket[0];

            Assert.Equal((2, 4), TourneyBracket.AdvancementTargets(r1, all));
        }
    }
}

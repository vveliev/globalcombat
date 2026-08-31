using System.Collections.Generic;
using ProtoBuf;

namespace GlobalCombat.Core
{
    // Port of Web/Models/TourneyRound.cs's persisted shape, extracted here (DB/Tourney-back-
    // reference-free) so it can travel over the wire as a gRPC response - see GameEngineService's
    // TourneyBracket RPC (GIF-109) and GlobalCombat.Tourneys.Bracket.Round, the Elixir port (GIF-32)
    // this exists to be diffed against.
    [ProtoContract]
    public class TourneyRound
    {
        [ProtoMember(1)]
        public int Number { get; set; }
        [ProtoMember(2)]
        public int StartGame { get; set; }
        [ProtoMember(3)]
        public int GameCount { get; set; }
        [ProtoMember(4)]
        public int GameSize { get; set; }
        [ProtoMember(5)]
        public int WinnersOfRoundNumber { get; set; }
        [ProtoMember(6)]
        public int LosersOfRoundNumber { get; set; }
    }

    [ProtoContract]
    public class TourneyBracket
    {
        [ProtoMember(1)]
        public List<TourneyRound> WinnerBracket { get; set; } = new List<TourneyRound>();
        [ProtoMember(2)]
        public List<TourneyRound> LoserBracket { get; set; } = new List<TourneyRound>();
        [ProtoMember(3)]
        public TourneyRound FinalRound { get; set; }

        // Faithful extraction of Web/Models/Tourney.cs's BuildRounds() - same field-by-field
        // construction, just taking the tourney's shape as parameters instead of reading instance
        // properties (GameSize, Winners, Losers, IsDoubleElimination, InitialGames), so it has no
        // dependency on WebGame.Tourney/DBConnection and can run standalone behind a gRPC RPC.
        // initialGames is assumed already validated (power of two, >= 2, etc.) by the caller,
        // exactly like the original - BuildRounds itself does no such validation either.
        public static TourneyBracket BuildRounds(int initialGames, int gameSize, int winners, bool isDoubleElimination)
        {
            var losers = gameSize - winners;
            var bracket = new TourneyBracket();

            int currentRound = 1;
            int startGame = 1;

            bracket.WinnerBracket.Add(new TourneyRound { Number = currentRound, GameCount = initialGames, GameSize = gameSize, StartGame = startGame });
            startGame += initialGames;

            var previousGameCount = initialGames;
            while (previousGameCount > 1)
            {
                currentRound++;
                previousGameCount = previousGameCount / 2;
                bracket.WinnerBracket.Add(new TourneyRound { Number = currentRound, GameCount = previousGameCount, GameSize = winners * 2, WinnersOfRoundNumber = currentRound - 1, StartGame = startGame });
                startGame += previousGameCount;
            }

            if (isDoubleElimination)
            {
                int winnerRound = 1;
                currentRound++;
                previousGameCount = initialGames / 2;
                bracket.LoserBracket.Add(new TourneyRound { Number = currentRound, GameCount = previousGameCount, GameSize = losers * 2, LosersOfRoundNumber = winnerRound, StartGame = startGame });
                startGame += previousGameCount;

                int winnerRoundGameCount = initialGames / 2;
                while (previousGameCount > 1)
                {
                    int count = previousGameCount / 2;
                    bool addFlag = true;
                    if (winnerRoundGameCount == 2 && count > 1)
                        addFlag = false;
                    if (winnerRoundGameCount < 2)
                        addFlag = false;
                    // TODO (carried from the original): if PrevGameCount(times two?) + ThisRoundGameCount
                    // != power of 2, then AddFlag = 0 - otherwise bad round game counts when initial
                    // game > 16; may replace the above two checks.

                    currentRound++;
                    if (!addFlag)
                    {
                        previousGameCount = previousGameCount / 2;
                        bracket.LoserBracket.Add(new TourneyRound { Number = currentRound, GameCount = previousGameCount, GameSize = winners * 2, WinnersOfRoundNumber = currentRound - 1, StartGame = startGame });
                        startGame += previousGameCount;
                    }
                    else
                    {
                        winnerRound++;
                        winnerRoundGameCount = winnerRoundGameCount / 2;
                        bracket.LoserBracket.Add(new TourneyRound { Number = currentRound, GameCount = previousGameCount, GameSize = winners * 2, WinnersOfRoundNumber = currentRound - 1, LosersOfRoundNumber = winnerRound, StartGame = startGame });
                        startGame += previousGameCount;
                    }
                }

                winnerRound++;
                currentRound++;
                bracket.LoserBracket.Add(new TourneyRound { Number = currentRound, GameCount = 1, GameSize = winners * 2, WinnersOfRoundNumber = currentRound - 1, LosersOfRoundNumber = winnerRound, StartGame = startGame });
                startGame += 1;

                currentRound++;
                bracket.FinalRound = new TourneyRound { Number = currentRound, GameCount = 1, GameSize = winners * 2, WinnersOfRoundNumber = winnerRound, LosersOfRoundNumber = -(currentRound - 1), StartGame = startGame };
            }

            return bracket;
        }

        // Port of the winnerRound/loserRound lookup inline in Tourney.CreateTourneyGame: given one
        // round and the full flattened list of every round in the bracket (winner + loser + final),
        // returns the round numbers this round's winners/losers advance into (0 meaning nowhere -
        // eliminated, or the tournament ends here).
        public static (int WinnerRound, int LoserRound) AdvancementTargets(TourneyRound round, IEnumerable<TourneyRound> allRounds)
        {
            TourneyRound winnerRound = null;
            TourneyRound loserRound = null;

            foreach (var r in allRounds)
            {
                if (winnerRound == null && (r.WinnersOfRoundNumber == round.Number || r.LosersOfRoundNumber == -round.Number))
                    winnerRound = r;
                if (loserRound == null && r.LosersOfRoundNumber == round.Number)
                    loserRound = r;
            }

            return (winnerRound?.Number ?? 0, loserRound?.Number ?? 0);
        }
    }
}

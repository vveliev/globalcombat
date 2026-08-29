using System;
using System.Collections.Generic;
using System.Linq;
using GlobalCombat.Core;
using Xunit;

namespace GlobalCombat.Core.Tests
{
    /// <summary>
    /// The engine has to survive being observed from outside its own heap: read
    /// over a wire, replayed with a fixed seed, compared against another
    /// implementation. These tests cover the two things that stopped it.
    /// </summary>
    public class EngineObservabilityTests
    {
        static Game StartedGame(int seed)
        {
            var game = new Game();
            game.SeedRandom(seed);
            game.Join(1, "Alice", 1500);
            // Join starts the game itself once MaxPlayers is reached (Game.cs
            // Join -> Start), so calling Start again would throw.
            game.Join(2, "Bob", 1500);
            return game;
        }

        /// <summary>
        /// Rebuilds the owner references as distinct objects carrying the same
        /// values — exactly what any deserializer that does not preserve object
        /// identity produces, and the only thing a non-.NET client can produce
        /// at all. The board is unchanged; only reference identity is lost.
        /// </summary>
        static void BreakOwnerReferences(Game game)
        {
            foreach (var area in game.Areas)
            {
                if (area.Owner == null)
                    continue;

                var original = area.Owner;
                area.Owner = new Player
                {
                    AccountId = original.AccountId,
                    Number = original.Number,
                    Name = original.Name,
                    Done = original.Done,
                    Areas = original.Areas,
                    Armies = original.Armies,
                    UnassignedArmies = original.UnassignedArmies,
                    Place = original.Place,
                    Rating = original.Rating
                };
            }
        }

        static int ArmiesOnBoardFor(Game game, Player player)
        {
            return game.Areas.Where(a => a.Owner != null && a.Owner.Number == player.Number)
                             .Sum(a => a.Armies);
        }

        [Fact]
        public void RunTurn_totals_a_players_armies_when_owner_references_are_copies()
        {
            var game = StartedGame(seed: 4242);
            BreakOwnerReferences(game);

            var expected = game.Players.ToDictionary(p => p.Number, p => ArmiesOnBoardFor(game, p));

            game.RunTurn();

            foreach (var player in game.Players)
            {
                // Armies is the board total plus whatever the turn handed out and
                // the player has not placed yet. Comparing by reference dropped
                // the board total entirely and left only the unassigned pool.
                Assert.Equal(expected[player.Number] + player.UnassignedArmies, player.Armies);
                Assert.True(player.Armies > player.UnassignedArmies,
                    $"player {player.Number} counted no territory at all: " +
                    $"Armies={player.Armies}, UnassignedArmies={player.UnassignedArmies}");
            }
        }

        [Fact]
        public void SetAttack_refuses_an_attack_on_your_own_area_when_owner_references_are_copies()
        {
            var game = StartedGame(seed: 99);

            // A linked pair, forced to the same owner as two distinct objects.
            var source = game.Areas.First(a => a.AreaInfo.Inbounds.Count > 0);
            var target = game.Areas.First(a => a.Number == source.AreaInfo.Inbounds[0].Number);

            var owner = game.Players[0];
            source.Owner = new Player { Number = owner.Number, Name = owner.Name, AccountId = owner.AccountId };
            target.Owner = new Player { Number = owner.Number, Name = owner.Name, AccountId = owner.AccountId };
            source.Armies = 10;

            var amount = game.SetAttack(source, target, 5);

            Assert.Equal(0, amount);
            Assert.NotEqual(Command.Attack, source.Command);
        }

        [Fact]
        public void SetTransfer_still_allows_moving_between_your_own_areas_when_references_are_copies()
        {
            var game = StartedGame(seed: 7);

            var source = game.Areas.First(a => a.AreaInfo.Inbounds.Count > 0);
            var target = game.Areas.First(a => a.Number == source.AreaInfo.Inbounds[0].Number);

            var owner = game.Players[0];
            source.Owner = new Player { Number = owner.Number, Name = owner.Name, AccountId = owner.AccountId };
            target.Owner = new Player { Number = owner.Number, Name = owner.Name, AccountId = owner.AccountId };
            source.Armies = 10;

            var amount = game.SetTransfer(source, target, 4);

            Assert.Equal(4, amount);
            Assert.Equal(Command.Transfer, source.Command);
        }

        [Fact]
        public void The_same_seed_deals_the_same_board()
        {
            string Ownership(Game g) => string.Join(",", g.Areas.Select(a => a.Owner == null ? 0 : a.Owner.Number));

            Assert.Equal(Ownership(StartedGame(seed: 1234)), Ownership(StartedGame(seed: 1234)));
        }

        [Fact]
        public void A_different_seed_deals_a_different_board()
        {
            string Ownership(Game g) => string.Join(",", g.Areas.Select(a => a.Owner == null ? 0 : a.Owner.Number));

            // Not a guarantee for every pair of seeds, but two fixed seeds that
            // agreed would mean the seed is not reaching the deal at all.
            Assert.NotEqual(Ownership(StartedGame(seed: 1)), Ownership(StartedGame(seed: 2)));
        }

        [Fact]
        public void The_same_seed_resolves_combat_the_same_way()
        {
            string ResolveOnce(int seed)
            {
                var game = StartedGame(seed);

                // First area that can attack a neighbour it does not own.
                foreach (var source in game.Areas)
                {
                    foreach (var link in source.AreaInfo.Inbounds)
                    {
                        var target = game.Areas.First(a => a.Number == link.Number);
                        if (source.IsOwnedBy(target.Owner))
                            continue;

                        source.Armies = 10;
                        target.Armies = 10;
                        game.SetAttack(source, target, 5);
                        game.RunTurn();
                        return string.Join(",", game.Areas.Select(a =>
                            $"{a.Number}:{(a.Owner == null ? 0 : a.Owner.Number)}:{a.Armies}"));
                    }
                }

                throw new InvalidOperationException("no attackable neighbour found");
            }

            Assert.Equal(ResolveOnce(31337), ResolveOnce(31337));
        }
    }
}

using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using GlobalCombat.Core;
using ProtoBuf.Grpc;

namespace GlobalCombat.GrpcHost
{
    public class GameEngineService : IGameEngine
    {
        // Games created via NewGame stay here for the lifetime of the process, exactly like the
        // real GameServer.cs keeps a Game object alive server-side for as long as it's running -
        // see the comment on ThinkRequest for why Think/ResolveQueuedTurn need this instead of a
        // stateless round trip. Never evicted; this is a harness/spike host, not production.
        static readonly ConcurrentDictionary<int, Game> _games = new();

        // Game.Start()/RunTurn() need MapInfo.Areas rehydrated onto each Area (that link is not
        // serialized - see GlobalCombat.Core.Game.Load doing the same thing after ProtoBuf.Serializer.Deserialize).
        static void Rehydrate(Game game)
        {
            var mapInfo = game.MapInfo;
            foreach (var area in game.Areas)
                area.AreaInfo = mapInfo.GetArea(area.Number);
        }

        static Game GetStoredGame(int gameId)
        {
            if (!_games.TryGetValue(gameId, out var game))
                throw new InvalidOperationException($"No game with Id={gameId} (has NewGame been called for it in this process?)");
            return game;
        }

        public Task<NewGameResponse> NewGame(NewGameRequest request, CallContext context = default)
        {
            var game = new Game
            {
                Id = new Random().Next(1, 1_000_000),
                GameName = "gRPC harness game",
                MapName = request.MapName,
                MaxPlayers = Math.Max(2, request.PlayerNames.Count),
                TurnLength = 1440,
                IsFogged = request.IsFogged,
                IsNonRandom = request.IsNonRandom,
                ReverseAttackOrder = request.ReverseAttackOrder,
                MinimumArmies = request.MinimumArmies
            };
            game.SeedRandom(request.Seed);

            int accountId = 1;
            foreach (var name in request.PlayerNames)
                game.Join(accountId++, name, rating: 1200);

            _games[game.Id] = game;

            return Task.FromResult(new NewGameResponse { Game = game });
        }

        public Task<ResolveTurnResponse> ResolveTurn(ResolveTurnRequest request, CallContext context = default)
        {
            var game = request.Game;
            Rehydrate(game);
            game.SeedRandom(request.Seed);

            foreach (var order in request.Orders)
            {
                var source = game.GetArea(order.SourceAreaNumber);
                var target = game.GetArea(order.TargetAreaNumber);
                if (source == null || target == null)
                    continue;

                switch (order.Command)
                {
                    case Command.Attack:
                        game.SetAttack(source, target, order.Amount);
                        break;
                    case Command.Transfer:
                        game.SetTransfer(source, target, order.Amount);
                        break;
                }
            }

            var summary = new StringBuilder();
            Action<Game, string> onRunTurn = (g, message) => summary.Append(message);
            Game.OnRunTurn += onRunTurn;
            try
            {
                game.RunTurn();
            }
            finally
            {
                Game.OnRunTurn -= onRunTurn;
            }

            return Task.FromResult(new ResolveTurnResponse
            {
                Game = game,
                TurnSummary = summary.ToString()
            });
        }

        public Task<ThinkResponse> Think(ThinkRequest request, CallContext context = default)
        {
            var game = GetStoredGame(request.GameId);
            game.SeedRandom(request.Seed);

            new RandomAiPlayer(game).Think();

            var response = new ThinkResponse();
            foreach (var area in game.Areas)
            {
                if (area.AssignedArmies > 0)
                    response.Assignments.Add(new Assignment { AreaNumber = area.Number, Amount = area.AssignedArmies });

                if (area.Command != Command.None)
                    response.Orders.Add(new Order { SourceAreaNumber = area.Number, TargetAreaNumber = area.Target!.Number, Amount = area.Amount, Command = area.Command });
            }

            return Task.FromResult(response);
        }

        // Resolves whatever commands Think() (or a human player, in production) already queued
        // onto the stored Game's Areas - no Orders parameter needed, unlike the stateless
        // ResolveTurn above, since there's nothing to re-apply that isn't already sitting on the
        // one in-memory Game object both this and Think operated on.
        public Task<ResolveTurnResponse> ResolveQueuedTurn(ResolveQueuedTurnRequest request, CallContext context = default)
        {
            var game = GetStoredGame(request.GameId);
            game.SeedRandom(request.Seed);

            var summary = new StringBuilder();
            Action<Game, string> onRunTurn = (g, message) => summary.Append(message);
            Game.OnRunTurn += onRunTurn;
            try
            {
                game.RunTurn();
            }
            finally
            {
                Game.OnRunTurn -= onRunTurn;
            }

            return Task.FromResult(new ResolveTurnResponse
            {
                Game = game,
                TurnSummary = summary.ToString()
            });
        }

        public Task<TourneyBracketResponse> TourneyBracket(TourneyBracketRequest request, CallContext context = default)
        {
            var bracket = GlobalCombat.Core.TourneyBracket.BuildRounds(request.InitialGames, request.GameSize, request.Winners, request.IsDoubleElimination);
            return Task.FromResult(new TourneyBracketResponse { Bracket = bracket });
        }
    }
}

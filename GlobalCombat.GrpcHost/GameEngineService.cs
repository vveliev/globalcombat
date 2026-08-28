using System;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using GlobalCombat.Core;
using ProtoBuf.Grpc;

namespace GlobalCombat.GrpcHost
{
    public class GameEngineService : IGameEngine
    {
        // Game.Start()/RunTurn() need MapInfo.Areas rehydrated onto each Area (that link is not
        // serialized - see GlobalCombat.Core.Game.Load doing the same thing after ProtoBuf.Serializer.Deserialize).
        static void Rehydrate(Game game)
        {
            var mapInfo = game.MapInfo;
            foreach (var area in game.Areas)
                area.AreaInfo = mapInfo.GetArea(area.Number);
        }

        public Task<NewGameResponse> NewGame(NewGameRequest request, CallContext context = default)
        {
            var game = new Game
            {
                Id = new Random().Next(1, 1_000_000),
                GameName = "gRPC spike game",
                MapName = request.MapName,
                MaxPlayers = Math.Max(2, request.PlayerNames.Count),
                TurnLength = 1440,
                IsFogged = false,
                IsNonRandom = true, // deterministic combat makes the spike's turn output reproducible
                MinimumArmies = 3
            };

            int accountId = 1;
            foreach (var name in request.PlayerNames)
                game.Join(accountId++, name, rating: 1200);

            return Task.FromResult(new NewGameResponse { Game = game });
        }

        public Task<ResolveTurnResponse> ResolveTurn(ResolveTurnRequest request, CallContext context = default)
        {
            var game = request.Game;
            Rehydrate(game);

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
    }
}

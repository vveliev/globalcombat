using System.Collections.Generic;
using System.Threading.Tasks;
using GlobalCombat.Core;
using ProtoBuf;
using ProtoBuf.Grpc;
using ProtoBuf.Grpc.Configuration;

namespace GlobalCombat.GrpcHost
{
    // Spike question: can the existing GlobalCombat.Core [ProtoContract] types (Game, Player, Area, ...)
    // be reused directly as the gRPC contract, or does the real object graph need a hand-written
    // parallel model? Game/Player/Area/Invite are used as-is here - no shadow DTOs.

    [ProtoContract]
    public class Order
    {
        [ProtoMember(1)]
        public int SourceAreaNumber { get; set; }

        [ProtoMember(2)]
        public int TargetAreaNumber { get; set; }

        [ProtoMember(3)]
        public int Amount { get; set; }

        [ProtoMember(4)]
        public Command Command { get; set; }
    }

    [ProtoContract]
    public class ResolveTurnRequest
    {
        [ProtoMember(1)]
        public Game Game { get; set; } = new Game();

        [ProtoMember(2)]
        public List<Order> Orders { get; set; } = new List<Order>();
    }

    [ProtoContract]
    public class ResolveTurnResponse
    {
        [ProtoMember(1)]
        public Game Game { get; set; } = new Game();

        [ProtoMember(2)]
        public string TurnSummary { get; set; } = string.Empty;
    }

    [ProtoContract]
    public class NewGameRequest
    {
        [ProtoMember(1)]
        public MapName MapName { get; set; }

        [ProtoMember(2)]
        public List<string> PlayerNames { get; set; } = new List<string>();
    }

    [ProtoContract]
    public class NewGameResponse
    {
        [ProtoMember(1)]
        public Game Game { get; set; } = new Game();
    }

    [Service]
    public interface IGameEngine
    {
        [Operation]
        Task<NewGameResponse> NewGame(NewGameRequest request, CallContext context = default);

        [Operation]
        Task<ResolveTurnResponse> ResolveTurn(ResolveTurnRequest request, CallContext context = default);
    }
}

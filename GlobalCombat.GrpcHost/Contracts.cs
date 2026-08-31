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

        // The differential harness's seed for this turn's combat RNG (GIF-28). Game.Rng is
        // [ProtoIgnore] (see Game.cs), so it never survives the Game -> wire -> Game round trip;
        // without this the server would resolve every turn's combat with a fresh unseeded
        // Random and the two engines could never be compared draw-for-draw.
        [ProtoMember(3)]
        public int Seed { get; set; }
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

        // Seeds the RNG the server uses for Start()'s area-split/ownership deal, so a harness
        // caller can reproduce the exact starting Game state (see differential-harness skill:
        // that deal draws from Rng regardless of IsNonRandom - it is not gated by the combat-roll
        // toggle below, and has to be seeded like everything else or two calls never agree).
        [ProtoMember(3)]
        public int Seed { get; set; }

        [ProtoMember(4)]
        public bool IsNonRandom { get; set; }

        [ProtoMember(5)]
        public bool IsFogged { get; set; }

        [ProtoMember(6)]
        public bool ReverseAttackOrder { get; set; }

        [ProtoMember(7)]
        public int MinimumArmies { get; set; }
    }

    [ProtoContract]
    public class NewGameResponse
    {
        [ProtoMember(1)]
        public Game Game { get; set; } = new Game();
    }

    // Think/ResolveQueuedTurn identify the game by Id and operate on the *same in-memory Game
    // object* NewGame created and GameEngineService kept server-side (see _games in
    // GameEngineService), rather than round-tripping a serialized Game through the request. This
    // isn't just an optimization: protobuf-net.Grpc's AsReference doesn't actually preserve
    // Player identity sharing *across sibling Areas* on a deserialize (each Area.Owner comes back
    // as its own copy, not the same object two areas of the same player's territory would share
    // in memory) - GIF-38 already found a version of this same fragility. That silently breaks
    // SetAssigned's `area.Owner.UnassignedArmies -= amount`: a debit made through one area's
    // Owner is invisible to a sibling area's Owner, so a player attacked... err, *assigned to*
    // repeatedly across several of their own areas never actually runs out of unassigned armies
    // the way RunTurn requires. Keeping the Game in server memory across Think -> ResolveQueuedTurn
    // (exactly like the real GameServer.cs keeps one Game object alive per running game) sidesteps
    // the bug entirely instead of working around it - the original stateless ResolveTurn/Think(Game)
    // shape is still here unchanged for GIF-38's existing SelfTest/mix task demo, which never
    // exercises multi-area-per-player mutation in a way that would expose this.
    [ProtoContract]
    public class ThinkRequest
    {
        [ProtoMember(1)]
        public int GameId { get; set; }

        [ProtoMember(2)]
        public int Seed { get; set; }
    }

    [ProtoContract]
    public class ResolveQueuedTurnRequest
    {
        [ProtoMember(1)]
        public int GameId { get; set; }

        [ProtoMember(2)]
        public int Seed { get; set; }
    }

    [ProtoContract]
    public class Assignment
    {
        [ProtoMember(1)]
        public int AreaNumber { get; set; }

        [ProtoMember(2)]
        public int Amount { get; set; }
    }

    [ProtoContract]
    public class ThinkResponse
    {
        // Deliberately flat (area-number-keyed), not the mutated Game graph: returning Areas
        // straight off a post-Think() Game - with dozens of areas simultaneously holding a
        // non-null AsReference Target - crashes protobuf-net's serializer measurement pass with
        // a StackOverflowException. RunTurn's own response never hit this because its last step
        // clears every Command/Target before returning; Think() is the first caller to return
        // state with many Target references still live at once. Same family of fragility GIF-38
        // already found in this AsReference machinery, worse this time (a hang, not silently
        // wrong data) - see docs/memory project_gif38_asreference_finding.
        [ProtoMember(1)]
        public List<Assignment> Assignments { get; set; } = new List<Assignment>();

        [ProtoMember(2)]
        public List<Order> Orders { get; set; } = new List<Order>();
    }

    // GIF-109: bracket seeding/advancement is deterministic, DB-free math (Web/Models/Tourney.cs's
    // BuildRounds, extracted to GlobalCombat.Core.TourneyBracket) - unlike NewGame/Think/
    // ResolveQueuedTurn, this RPC is stateless and takes no seed: same request always produces the
    // same bracket, so there's nothing to reproduce beyond passing the same shape twice.
    [ProtoContract]
    public class TourneyBracketRequest
    {
        [ProtoMember(1)]
        public int InitialGames { get; set; }

        [ProtoMember(2)]
        public int GameSize { get; set; }

        [ProtoMember(3)]
        public int Winners { get; set; }

        [ProtoMember(4)]
        public bool IsDoubleElimination { get; set; }
    }

    [ProtoContract]
    public class TourneyBracketResponse
    {
        [ProtoMember(1)]
        public GlobalCombat.Core.TourneyBracket Bracket { get; set; } = new GlobalCombat.Core.TourneyBracket();
    }

    [Service]
    public interface IGameEngine
    {
        [Operation]
        Task<NewGameResponse> NewGame(NewGameRequest request, CallContext context = default);

        [Operation]
        Task<ResolveTurnResponse> ResolveTurn(ResolveTurnRequest request, CallContext context = default);

        [Operation]
        Task<ThinkResponse> Think(ThinkRequest request, CallContext context = default);

        [Operation]
        Task<ResolveTurnResponse> ResolveQueuedTurn(ResolveQueuedTurnRequest request, CallContext context = default);

        [Operation]
        Task<TourneyBracketResponse> TourneyBracket(TourneyBracketRequest request, CallContext context = default);
    }
}

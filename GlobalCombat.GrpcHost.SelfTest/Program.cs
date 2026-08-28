using GlobalCombat.Core;
using GlobalCombat.GrpcHost;
using Grpc.Net.Client;
using ProtoBuf.Grpc.Client;

// Isolate: does protobuf-net's own AsReference machinery preserve object identity on a plain
// in-process Serialize/Deserialize round trip, with no gRPC/network layer involved at all?
{
    var shared = new Player { AccountId = 1, Number = 1, Name = "Shared" };
    var probe = new Game
    {
        Areas = new List<Area>
        {
            new Area { Number = 1, Owner = shared },
            new Area { Number = 2, Owner = shared },
        },
        Players = new List<Player> { shared }
    };
    using var probeStream = new MemoryStream();
    ProtoBuf.Serializer.Serialize(probeStream, probe);
    probeStream.Position = 0;
    var roundTripped = ProtoBuf.Serializer.Deserialize<Game>(probeStream);
    var sameOwnerAcrossAreas = ReferenceEquals(roundTripped.Areas[0].Owner, roundTripped.Areas[1].Owner);
    var ownerIsPlayersListEntry = ReferenceEquals(roundTripped.Areas[0].Owner, roundTripped.Players[0]);
    Console.WriteLine($"[AsReference probe, no gRPC] Areas[0].Owner == Areas[1].Owner: {sameOwnerAcrossAreas}; Areas[0].Owner == Players[0]: {ownerIsPlayersListEntry}");
    Console.WriteLine($"[AsReference probe] values still match: Areas[0].Owner.Name={roundTripped.Areas[0].Owner.Name}, Areas[1].Owner.Name={roundTripped.Areas[1].Owner.Name}, Players[0].Name={roundTripped.Players[0].Name}");

    // Now mutate through one alias and see whether the mutation is visible through the other -
    // this is the behavior game logic (e.g. Game.RunTurn's player.Areas++/UnassignedArmies+=)
    // actually depends on, not just the printed values matching once.
    roundTripped.Areas[0].Owner.Armies = 999;
    Console.WriteLine($"[AsReference probe] mutate Areas[0].Owner.Armies=999 -> Areas[1].Owner.Armies={roundTripped.Areas[1].Owner.Armies}, Players[0].Armies={roundTripped.Players[0].Armies}");
}

GrpcClientFactory.AllowUnencryptedHttp2 = true;
using var channel = GrpcChannel.ForAddress("http://127.0.0.1:5251");
var client = channel.CreateGrpcService<IGameEngine>();

var newGame = await client.NewGame(new NewGameRequest
{
    MapName = MapName.Original,
    PlayerNames = new List<string> { "Alice", "Bob" }
});

var game = newGame.Game;
Console.WriteLine($"NewGame: Id={game.Id} Started={game.Started} Areas={game.Areas.Count} Players={game.Players.Count}");
foreach (var p in game.Players)
    Console.WriteLine($"  Player #{p.Number} {p.Name}: {p.Areas} areas, {p.Armies} armies ({p.UnassignedArmies} unassigned)");

// Sanity check the AsReference graph came back wired correctly, not just parallel lists.
var firstArea = game.Areas[0];
Console.WriteLine($"Area 1 owner is same Player object as game.Players entry: {ReferenceEquals(firstArea.Owner, game.GetPlayerByNumber(firstArea.Owner.Number))}");

// Note: AreaInfo (map geometry/links) is not a [ProtoMember] - it never crosses the wire, only
// Area.Number does. The client picks orders using area numbers it already knows (map "original"
// is a fixed, hardcoded 42-area layout shared by both sides - see GlobalCombat.Core/MapInfo.cs).
// Area 1 (Alaska) links to Area 2 in that layout.
var player1Area = game.Areas.First(a => a.Owner != null && a.Owner.Number == 1);
var enemyNeighbor = game.Areas.First(a => a.Number == 2);
var orders = new List<Order>
{
    new Order { SourceAreaNumber = player1Area.Number, TargetAreaNumber = enemyNeighbor.Number, Amount = Math.Max(1, player1Area.TotalArmies - 1), Command = Command.Attack }
};

var resolved = await client.ResolveTurn(new ResolveTurnRequest { Game = game, Orders = orders });
Console.WriteLine($"ResolveTurn: Turn={resolved.Game.Turn} Summary={resolved.Game.Turn}");
Console.WriteLine($"TurnSummary: {resolved.TurnSummary}");

// Correctness check: Game.RunTurn totals each player's armies by scanning Areas for
// `area.Owner == player` (default reference equality - Player has no Equals override).
// Independently recompute the same total by matching on Number (a value, always correct)
// and compare against what RunTurn actually produced through the wire-crossed Game.
foreach (var p in resolved.Game.Players)
{
    var expectedTotalArmies = resolved.Game.Areas.Where(a => a.Owner != null && a.Owner.Number == p.Number).Sum(a => a.Armies) + p.UnassignedArmies;
    Console.WriteLine($"  Player #{p.Number} {p.Name}: RunTurn computed Armies={p.Armies}, independently-recomputed-by-value Armies={expectedTotalArmies} {(p.Armies == expectedTotalArmies ? "MATCH" : "*** MISMATCH ***")}");
}

// Wire-size measurement: serialize the resolved Game the same way protobuf-net.Grpc does on the wire.
using var ms = new MemoryStream();
ProtoBuf.Serializer.Serialize(ms, resolved.Game);
Console.WriteLine($"Serialized Game size: {ms.Length} bytes for {resolved.Game.Areas.Count} areas / {resolved.Game.Players.Count} players");

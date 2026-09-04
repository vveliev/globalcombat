using GlobalCombat.GrpcHost;
using ProtoBuf.Grpc.Reflection;
using ProtoBuf.Grpc.Server;

// `dotnet run -- emit-proto <path>` writes the generated .proto for IGameEngine and exits,
// without starting Kestrel. This is how the .proto committed to the repo was produced.
if (args.Length >= 2 && args[0] == "emit-proto")
{
    var generator = new SchemaGenerator();
    var schema = generator.GetSchema<IGameEngine>();
    File.WriteAllText(args[1], schema);
    Console.WriteLine($"Wrote {args[1]} ({schema.Length} bytes)");
    return;
}

var builder = WebApplication.CreateBuilder(args);

// Plaintext HTTP/2 (h2c) - no TLS - so a non-.NET client (Elixir/gun) can connect without
// certificate setup. Fine for a spike; production would terminate TLS in front of this.
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(5251, listenOptions =>
    {
        listenOptions.Protocols = Microsoft.AspNetCore.Server.Kestrel.Core.HttpProtocols.Http2;
    });
});

builder.Services.AddCodeFirstGrpc(options => options.Interceptors.Add<LoggingInterceptor>());

var app = builder.Build();

app.MapGrpcService<GameEngineService>();
app.MapGet("/", () => "GlobalCombat gRPC spike host is running.");

app.Run();

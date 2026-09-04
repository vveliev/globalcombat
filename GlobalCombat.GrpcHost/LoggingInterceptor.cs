using System.Diagnostics;
using Grpc.Core;
using Grpc.Core.Interceptors;

namespace GlobalCombat.GrpcHost
{
    /// <summary>
    /// One Information-level line per unary RPC (method, outcome, elapsed ms). The Phoenix side
    /// calls this host for board generation and the differential harness; without this, the only
    /// evidence the engine host ever served a request was the Kestrel startup banner, which makes
    /// the two-process shape (docs/adr/0001) undiagnosable from logs in production.
    /// </summary>
    public sealed class LoggingInterceptor : Interceptor
    {
        readonly ILogger<LoggingInterceptor> _logger;

        public LoggingInterceptor(ILogger<LoggingInterceptor> logger) => _logger = logger;

        public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
            TRequest request,
            ServerCallContext context,
            UnaryServerMethod<TRequest, TResponse> continuation)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                var response = await continuation(request, context);
                _logger.LogInformation("gRPC {Method} ok in {ElapsedMs} ms", context.Method, sw.ElapsedMilliseconds);
                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "gRPC {Method} failed in {ElapsedMs} ms", context.Method, sw.ElapsedMilliseconds);
                throw;
            }
        }
    }
}

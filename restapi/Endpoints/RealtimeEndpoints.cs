using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class RealtimeEndpoints
{
    public static RouteGroupBuilder MapRealtimeEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/realtime", async (
            HttpContext context,
            RealtimeConnectionManager connections,
            AuthService auth,
            CancellationToken ct) =>
        {
            if (!context.WebSockets.IsWebSocketRequest)
            {
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                await context.Response.WriteAsJsonAsync(new
                {
                    data = (object?)null,
                    meta = (object?)null,
                    error = new { code = "websocket_required", message = "此接口需要 WebSocket 连接" },
                    traceId = System.Diagnostics.Activity.Current?.Id
                }, ct);
                return;
            }

            using var socket = await context.WebSockets.AcceptWebSocketAsync();
            await connections.RunAsync(socket, auth, ct);
        });
        return api;
    }
}

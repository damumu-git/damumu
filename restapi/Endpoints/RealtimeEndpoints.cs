using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class RealtimeEndpoints
{
    private static readonly SemaphoreSlim SocketSlots = new(500);
    public static RouteGroupBuilder MapRealtimeEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/realtime", async (
            HttpContext context,
            RealtimeConnectionManager connections,
            SessionSecurity sessions,
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

            var origin = context.Request.Headers.Origin.ToString();
            if (origin.Length > 0 && origin != SessionSecurity.WebOrigin)
                throw new ApiException(403, "invalid_origin", "连接来源无效");
            if (!await SocketSlots.WaitAsync(0, ct))
                throw new ApiException(429, "connection_limit", "实时连接繁忙，请稍后再试");
            try
            {
                using var socket = await context.WebSockets.AcceptWebSocketAsync();
                await connections.RunAsync(socket, sessions, ct);
            }
            finally { SocketSlots.Release(); }
        });
        return api;
    }
}

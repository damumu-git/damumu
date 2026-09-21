using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace Muda.Api.Infrastructure;

public sealed class RealtimeConnectionManager(ILogger<RealtimeConnectionManager> logger)
{
    private const int MaxMessageBytes = 16 * 1024;
    private static readonly TimeSpan AuthenticationTimeout = TimeSpan.FromSeconds(10);
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<Guid, Connection>> _connections = new();

    public async Task RunAsync(WebSocket socket, AuthService auth, CancellationToken requestAborted)
    {
        Guid userId;
        try
        {
            using var authenticationTimeout = CancellationTokenSource.CreateLinkedTokenSource(requestAborted);
            authenticationTimeout.CancelAfter(AuthenticationTimeout);
            var authentication = await ReceiveJsonAsync(socket, authenticationTimeout.Token);
            if (authentication is null
                || !authentication.RootElement.TryGetProperty("type", out var type)
                || type.GetString() != "authenticate"
                || !authentication.RootElement.TryGetProperty("token", out var tokenElement)
                || tokenElement.GetString() is not { } token
                || !auth.TryValidateToken(token, out userId))
            {
                await CloseAsync(socket, WebSocketCloseStatus.PolicyViolation, "authentication_failed");
                return;
            }
        }
        catch (OperationCanceledException)
        {
            await CloseAsync(socket, WebSocketCloseStatus.PolicyViolation, "authentication_timeout");
            return;
        }
        catch (JsonException)
        {
            await CloseAsync(socket, WebSocketCloseStatus.InvalidPayloadData, "invalid_json");
            return;
        }

        var connection = new Connection(Guid.NewGuid(), userId, socket);
        var userConnections = _connections.GetOrAdd(userId, _ => new());
        userConnections[connection.Id] = connection;
        await connection.SendAsync(new { type = "connected", data = new { userId } }, requestAborted);

        try
        {
            while (socket.State == WebSocketState.Open && !requestAborted.IsCancellationRequested)
            {
                using var message = await ReceiveJsonAsync(socket, requestAborted);
                if (message is null) break;
                if (message.RootElement.TryGetProperty("type", out var incomingType)
                    && incomingType.GetString() == "ping")
                    await connection.SendAsync(new { type = "pong", data = new { } }, requestAborted);
            }
        }
        catch (OperationCanceledException) when (requestAborted.IsCancellationRequested)
        {
            // The request or application is stopping.
        }
        catch (WebSocketException exception)
        {
            logger.LogDebug(exception, "Realtime connection {ConnectionId} closed unexpectedly", connection.Id);
        }
        catch (JsonException)
        {
            await CloseAsync(socket, WebSocketCloseStatus.InvalidPayloadData, "invalid_json");
        }
        finally
        {
            userConnections.TryRemove(connection.Id, out _);
            if (userConnections.IsEmpty) _connections.TryRemove(userId, out _);
            connection.Dispose();
            await CloseAsync(socket, WebSocketCloseStatus.NormalClosure, "closed");
        }
    }

    public async Task PublishAsync(
        IEnumerable<Guid> userIds,
        string type,
        object data,
        CancellationToken cancellationToken = default)
    {
        var payload = new { type, data };
        foreach (var userId in userIds.Distinct())
        {
            if (!_connections.TryGetValue(userId, out var userConnections)) continue;
            foreach (var pair in userConnections.ToArray())
            {
                try
                {
                    await pair.Value.SendAsync(payload, cancellationToken);
                }
                catch (Exception exception) when (exception is WebSocketException or OperationCanceledException)
                {
                    userConnections.TryRemove(pair.Key, out var removed);
                    removed?.Dispose();
                }
            }
        }
    }

    private static async Task<JsonDocument?> ReceiveJsonAsync(
        WebSocket socket,
        CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        using var stream = new MemoryStream();
        while (true)
        {
            var result = await socket.ReceiveAsync(buffer, cancellationToken);
            if (result.MessageType == WebSocketMessageType.Close) return null;
            if (result.MessageType != WebSocketMessageType.Text)
                throw new JsonException("Only text messages are supported.");
            if (stream.Length + result.Count > MaxMessageBytes)
                throw new JsonException("Realtime message is too large.");
            stream.Write(buffer, 0, result.Count);
            if (result.EndOfMessage) break;
        }
        return JsonDocument.Parse(stream.ToArray());
    }

    private static async Task CloseAsync(
        WebSocket socket,
        WebSocketCloseStatus status,
        string reason)
    {
        if (socket.State is not (WebSocketState.Open or WebSocketState.CloseReceived)) return;
        try
        {
            await socket.CloseAsync(status, reason, CancellationToken.None);
        }
        catch (WebSocketException)
        {
            socket.Abort();
        }
    }

    private sealed class Connection(Guid id, Guid userId, WebSocket socket) : IDisposable
    {
        private readonly SemaphoreSlim _sendLock = new(1, 1);
        public Guid Id { get; } = id;
        public Guid UserId { get; } = userId;

        public async Task SendAsync(object payload, CancellationToken cancellationToken)
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(payload);
            await _sendLock.WaitAsync(cancellationToken);
            try
            {
                if (socket.State == WebSocketState.Open)
                    await socket.SendAsync(bytes, WebSocketMessageType.Text, true, cancellationToken);
            }
            finally
            {
                _sendLock.Release();
            }
        }

        public void Dispose() => _sendLock.Dispose();
    }
}

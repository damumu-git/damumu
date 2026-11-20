using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Npgsql;

namespace Muda.Api.Infrastructure;

public sealed class RealtimeConnectionManager(
    NpgsqlDataSource dataSource,
    SessionSecurity sessionSecurity,
    ILogger<RealtimeConnectionManager> logger)
{
    private const int MaxMessageBytes = 16 * 1024;
    private static readonly TimeSpan AuthenticationTimeout = TimeSpan.FromSeconds(10);
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<Guid, Connection>> _connections = new();
    private readonly SemaphoreSlim connectionSlots = new(500);
    internal Guid InstanceId { get; } = Guid.NewGuid();

    public async Task RunAsync(WebSocket socket, SessionSecurity sessions, CancellationToken requestAborted)
    {
        Guid userId;
        string credential;
        try
        {
            using var authenticationTimeout = CancellationTokenSource.CreateLinkedTokenSource(requestAborted);
            authenticationTimeout.CancelAfter(AuthenticationTimeout);
            using var authentication = await ReceiveJsonAsync(socket, authenticationTimeout.Token);
            if (authentication is null
                || authentication.RootElement.ValueKind != JsonValueKind.Object
                || !authentication.RootElement.TryGetProperty("type", out var type)
                || type.ValueKind != JsonValueKind.String
                || type.GetString() != "authenticate"
                || !authentication.RootElement.TryGetProperty("token", out var tokenElement)
                || tokenElement.ValueKind != JsonValueKind.String
                || tokenElement.GetString() is not { } token
                || token.Length > 1024)
            {
                await CloseAsync(socket, WebSocketCloseStatus.PolicyViolation, "authentication_failed");
                return;
            }
            credential = token;
            var account = await sessions.ValidateAsync(credential, requestAborted);
            if (!account.HasValue)
            {
                await CloseAsync(socket, WebSocketCloseStatus.PolicyViolation, "authentication_failed");
                return;
            }
            userId = account.Value;
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

        var connection = new Connection(Guid.NewGuid(), userId, socket, credential);
        ConcurrentDictionary<Guid, Connection>? userConnections = null;
        if (!await connectionSlots.WaitAsync(0, requestAborted))
        {
            await CloseAsync(socket, WebSocketCloseStatus.PolicyViolation, "connection_limit");
            return;
        }

        try
        {
            lock (_connections)
            {
                userConnections = _connections.GetOrAdd(userId, _ => new());
                if (userConnections.Count >= 5) return;
                userConnections[connection.Id] = connection;
            }
            await connection.SendAsync(new { type = "connected", data = new { userId } }, requestAborted);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(requestAborted);
            timeout.CancelAfter(TimeSpan.FromSeconds(65));
            var verifiedAt = DateTimeOffset.UtcNow;
            var windowStarted = verifiedAt;
            var received = 0;
            while (socket.State == WebSocketState.Open && !requestAborted.IsCancellationRequested)
            {
                using var message = await ReceiveJsonAsync(socket, timeout.Token);
                if (message is null) break;
                if (message.RootElement.ValueKind != JsonValueKind.Object) break;
                var now = DateTimeOffset.UtcNow;
                if (now - windowStarted >= TimeSpan.FromSeconds(10)) { windowStarted = now; received = 0; }
                if (++received > 20) break;
                timeout.CancelAfter(TimeSpan.FromSeconds(65));
                if (now - verifiedAt > TimeSpan.FromSeconds(15))
                {
                    if (await sessions.ValidateAsync(credential, requestAborted) != userId) break;
                    verifiedAt = now;
                }
                if (message.RootElement.TryGetProperty("type", out var incomingType)
                    && incomingType.ValueKind == JsonValueKind.String
                    && incomingType.GetString() == "ping")
                    await connection.SendAsync(new { type = "pong", data = new { } }, requestAborted);
            }
        }
        catch (OperationCanceledException)
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
            lock (_connections)
            {
                if (userConnections is not null)
                {
                    userConnections.TryRemove(connection.Id, out _);
                    if (userConnections.IsEmpty) _connections.TryRemove(userId, out _);
                }
            }
            connectionSlots.Release();
            await CloseAsync(socket, WebSocketCloseStatus.NormalClosure, "closed");
        }
    }

    public async Task PublishAsync(
        IEnumerable<Guid> userIds,
        string type,
        object data,
        CancellationToken cancellationToken = default)
    {
        var ids = userIds.Distinct().ToArray();
        await PublishLocalAsync(ids, type, data, cancellationToken);
        try
        {
            var element = JsonSerializer.SerializeToElement(data);
            foreach (var recipientChunk in ids.Chunk(100))
            {
                var payload = JsonSerializer.Serialize(
                    new RealtimeRelay(InstanceId, recipientChunk, type, element));
                await using var command = dataSource.CreateCommand(
                    "SELECT pg_notify('muda_realtime', @payload)");
                command.Parameters.AddWithValue("payload", payload);
                await command.ExecuteNonQueryAsync(cancellationToken);
            }
        }
        catch (Exception exception) when (exception is NpgsqlException or InvalidOperationException)
        {
            logger.LogWarning(exception, "Cross-instance realtime relay failed; local delivery and REST synchronization remain available");
        }
    }

    internal async Task PublishLocalAsync(
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
                    if (await sessionSecurity.ValidateAsync(pair.Value.Token, cancellationToken) != userId)
                    {
                        await CloseAsync(pair.Value.Socket, WebSocketCloseStatus.PolicyViolation, "session_expired");
                        continue;
                    }
                    await pair.Value.SendAsync(payload, cancellationToken);
                }
                catch (Exception exception) when (exception is WebSocketException or OperationCanceledException)
                {
                    userConnections.TryRemove(pair.Key, out _);
                }
            }
        }
    }

    internal sealed record RealtimeRelay(Guid Origin, Guid[] UserIds, string Type, JsonElement Data);

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
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            await socket.CloseAsync(status, reason, timeout.Token);
        }
        catch (Exception error) when (error is WebSocketException or OperationCanceledException)
        {
            socket.Abort();
        }
    }

    private sealed class Connection(Guid id, Guid userId, WebSocket socket, string token)
    {
        private readonly SemaphoreSlim _sendLock = new(1, 1);
        public Guid Id { get; } = id;
        public Guid UserId { get; } = userId;
        public string Token { get; } = token;
        public WebSocket Socket { get; } = socket;

        public async Task SendAsync(object payload, CancellationToken cancellationToken)
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(payload);
            if (!await _sendLock.WaitAsync(0, cancellationToken))
            {
                Socket.Abort();
                return;
            }
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeout.CancelAfter(TimeSpan.FromSeconds(5));
                if (Socket.State == WebSocketState.Open)
                    await Socket.SendAsync(bytes, WebSocketMessageType.Text, true, timeout.Token);
            }
            finally
            {
                _sendLock.Release();
            }
        }
    }
}

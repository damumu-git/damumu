using System.Text.Json;
using Npgsql;

namespace Muda.Api.Infrastructure;

public sealed class RealtimeRelayService(
    NpgsqlDataSource dataSource,
    RealtimeConnectionManager connections,
    ILogger<RealtimeRelayService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var connection = await dataSource.OpenConnectionAsync(stoppingToken);
                connection.Notification += async (_, args) =>
                {
                    try
                    {
                        var relay = JsonSerializer.Deserialize<RealtimeConnectionManager.RealtimeRelay>(args.Payload);
                        if (relay is null || relay.Origin == connections.InstanceId) return;
                        await connections.PublishLocalAsync(relay.UserIds, relay.Type, relay.Data, stoppingToken);
                    }
                    catch (Exception exception) when (exception is JsonException or OperationCanceledException)
                    {
                        logger.LogDebug(exception, "Ignored invalid or cancelled realtime relay");
                    }
                };
                await using (var listen = new NpgsqlCommand("LISTEN muda_realtime", connection))
                    await listen.ExecuteNonQueryAsync(stoppingToken);
                while (!stoppingToken.IsCancellationRequested)
                    await connection.WaitAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Realtime relay listener disconnected; retrying");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }
}

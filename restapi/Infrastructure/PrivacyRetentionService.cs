namespace Muda.Api.Infrastructure;

public sealed class PrivacyRetentionService(
    Db db, MediaStorage media, ILogger<PrivacyRetentionService> logger) : BackgroundService
{
    public async Task RunOnceAsync(CancellationToken ct)
    {
        await db.ExecuteAsync("SELECT muda_purge_expired_personal_data()", cancellationToken: ct);
        // A durable queue survives process crashes and filesystem failures.
        var files = await db.QueryAsync(
            "SELECT storage_key,is_directory FROM media_deletion_queue ORDER BY queued_at LIMIT 500", cancellationToken: ct);
        foreach (var file in files)
        {
            var key = (string)file["storage_key"]!;
            try
            {
                if ((bool)file["is_directory"]!) media.DeleteAvatarDirectory(key);
                else media.DeleteFile(key);
                await db.ExecuteAsync("DELETE FROM media_deletion_queue WHERE storage_key=@key", new { key }, ct);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
            {
                logger.LogError(exception, "Expired media could not be deleted; queue entry retained for retry");
                await db.ExecuteAsync("UPDATE media_deletion_queue SET queued_at=now() WHERE storage_key=@key", new { key }, ct);
            }
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(1));
        do
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception exception) { logger.LogError(exception, "Privacy retention cleanup failed"); }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}

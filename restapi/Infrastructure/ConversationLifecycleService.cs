namespace Muda.Api.Infrastructure;

public sealed class ConversationLifecycleService(
    Db db,
    ILogger<ConversationLifecycleService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(1));
        do
        {
            try
            {
                await db.QueryAsync("SELECT * FROM muda_refresh_conversation_lifecycle()",
                    cancellationToken: stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Conversation lifecycle refresh failed");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}

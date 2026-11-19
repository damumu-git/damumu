using Muda.Api.Endpoints;

namespace Muda.Api.Infrastructure;

public sealed class RecurringEventReminderService(Db db, RealtimeConnectionManager realtime, ILogger<RecurringEventReminderService> logger) : BackgroundService
{
    public async Task RunOnceAsync(CancellationToken ct)
    {
        await db.ExecuteAsync("""
            DELETE FROM event_recurrence WHERE first_ends_at < now()-interval '9 months'
            """, cancellationToken: ct);
        var plans = await db.QueryAsync("""
            SELECT p.id,p.organizer_user_id,p.frequency,p.occurrence_count,p.first_starts_at
            FROM event_recurrence p JOIN app_user u ON u.id=p.organizer_user_id
            WHERE NOT p.paused AND u.status='active' AND u.deleted_at IS NULL
              AND p.first_starts_at < now()+interval '14 days'
            """, cancellationToken: ct);
        foreach (var plan in plans)
        {
            for (var index = 1; index < Convert.ToInt32(plan["occurrence_count"]); index++)
            {
                var startsAt = RecurringEventEndpoints.Occurrence((DateTime)plan["first_starts_at"]!,
                    (string)plan["frequency"]!, index);
                if (!startsAt.HasValue || startsAt <= DateTime.UtcNow || startsAt > DateTime.UtcNow.AddDays(14)) continue;
                var inserted = await db.ExecuteAsync("""
                    WITH due AS (
                        INSERT INTO event_recurrence_reminder(recurrence_id,occurrence_index)
                        SELECT @id,@index WHERE NOT EXISTS (
                            SELECT 1 FROM event WHERE recurrence_id=@id AND recurrence_index=@index)
                        ON CONFLICT DO NOTHING RETURNING recurrence_id
                    )
                    INSERT INTO notification(user_id,notification_type,title,body,data)
                    SELECT p.organizer_user_id,'recurrence_due','定期活动可确认发布',
                        '下一场已进入发布窗口，请在定期活动计划中确认。',
                        jsonb_build_object('recurrenceId',p.id)
                    FROM due JOIN event_recurrence p ON p.id=due.recurrence_id
                    WHERE NOT p.paused
                    """, new { id = plan["id"], index }, ct);
                if (inserted > 0)
                    await realtime.PublishAsync([(Guid)plan["organizer_user_id"]!],
                        "notification.created", new { notificationType = "recurrence_due" }, ct);
            }
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(1));
        do
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception error)
            {
                logger.LogWarning("Recurring event reminder failed ({FailureType})", error.GetType().Name);
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}

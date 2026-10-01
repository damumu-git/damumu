namespace Muda.Api.Infrastructure;

public static class EventCancellation
{
    public static string ValidateReason(string? reason)
    {
        var value = reason?.Trim();
        if (string.IsNullOrEmpty(value) || value.Length > 500)
            throw new ApiException(400, "invalid_cancellation_reason", "请填写取消原因（最多 500 字）");
        return value;
    }

    // One statement makes the status, group message and notifications atomic.
    // The guarded UPDATE serializes concurrent cancellations, emitting only once.
    public const string Sql = """
        WITH cancelled AS (
            UPDATE event e
            SET status='cancelled', cancelled_at=now(), cancellation_reason=@reason
            WHERE e.id=@id AND e.organizer_user_id=@userId AND e.deleted_at IS NULL
              AND e.status NOT IN ('cancelled', 'completed')
              AND EXISTS (SELECT 1 FROM conversation c WHERE c.event_id=e.id AND c.conversation_type='event')
            RETURNING e.id, e.status, e.cancelled_at, e.cancellation_reason
        ), notice AS (
            INSERT INTO message (conversation_id, sender_user_id, message_type, body)
            SELECT c.id, NULL, 'event_cancelled', @reason
            FROM cancelled e JOIN conversation c ON c.event_id=e.id AND c.conversation_type='event'
            RETURNING id, conversation_id
        ), bumped AS (
            UPDATE conversation c
            SET updated_at=now(), status='read_only', read_only_at=now()
            FROM notice n WHERE c.id=n.conversation_id
        ), notified AS (
            INSERT INTO notification (user_id, notification_type, title, body, data)
            SELECT cm.user_id, 'event_cancelled', '活动取消', '取消原因：' || @reason,
                   jsonb_build_object('eventId', @id, 'conversationId', n.conversation_id, 'messageId', n.id)
            FROM notice n JOIN conversation_member cm ON cm.conversation_id=n.conversation_id
            WHERE cm.left_at IS NULL AND cm.user_id<>@userId
        )
        SELECT e.*, n.id AS message_id, n.conversation_id
        FROM cancelled e CROSS JOIN notice n
        """;
}

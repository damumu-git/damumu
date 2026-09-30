using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class SocialEndpoints
{
    public static RouteGroupBuilder MapSocialEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/conversations", async (
            HttpContext context, Db db, int? limit, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var take = Math.Clamp(limit ?? 30, 1, 100);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT c.id, c.conversation_type, c.event_id,
                       COALESCE(c.title, e.title, other_member.nickname, '会话') AS display_title,
                       c.status,
                       cm.last_read_at, cm.muted_until,
                       e.title AS event_title,
                       lm.id AS last_message_id, lm.body AS last_message_body,
                       lm.message_type AS last_message_type, lm.created_at AS last_message_at,
                       lm.sender_name AS last_message_sender,
                       (SELECT count(*) FROM conversation_member active_member
                        WHERE active_member.conversation_id=c.id AND active_member.left_at IS NULL) AS member_count,
                       (
                           SELECT count(*) FROM message unread
                           WHERE unread.conversation_id=c.id
                             AND unread.created_at > COALESCE(cm.last_read_at, '-infinity')
                             AND unread.sender_user_id IS DISTINCT FROM @userId
                             AND unread.deleted_at IS NULL
                       ) AS unread_count
                FROM conversation_member cm
                JOIN conversation c ON c.id=cm.conversation_id
                LEFT JOIN event e ON e.id=c.event_id
                LEFT JOIN LATERAL (
                    SELECT up.nickname
                    FROM conversation_member peer
                    JOIN user_profile up ON up.user_id=peer.user_id
                    WHERE peer.conversation_id=c.id AND peer.user_id<>@userId
                    ORDER BY peer.joined_at LIMIT 1
                ) other_member ON true
                LEFT JOIN LATERAL (
                    SELECT m.id, m.body, m.message_type, m.created_at,
                           up.nickname AS sender_name
                    FROM message m
                    LEFT JOIN user_profile up ON up.user_id=m.sender_user_id
                    WHERE m.conversation_id=c.id AND m.deleted_at IS NULL
                    ORDER BY m.created_at DESC LIMIT 1
                ) lm ON true
                WHERE cm.user_id=@userId AND cm.left_at IS NULL AND cm.hidden_at IS NULL
                ORDER BY lm.created_at DESC NULLS LAST, c.updated_at DESC
                LIMIT @limit
                """, new { userId, limit = take }, ct));
        });

        api.MapPost("/conversations/direct", async (
            HttpContext context, DirectConversationRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            if (userId == request.OtherUserId)
                throw new ApiException(400, "invalid_recipient", "不能与自己创建私信");

            var ids = new[] { userId, request.OtherUserId }.Order().ToArray();
            var directKey = $"{ids[0]:N}:{ids[1]:N}";
            var conversation = await db.QueryOneAsync(
                """
                INSERT INTO conversation (conversation_type, direct_key)
                VALUES ('direct', @directKey)
                ON CONFLICT (direct_key) WHERE conversation_type='direct'
                DO UPDATE SET updated_at=now()
                RETURNING id, conversation_type, status, created_at
                """, new { directKey }, ct)
                ?? throw new ApiException(500, "conversation_failed", "创建会话失败");
            var conversationId = (Guid)conversation["id"]!;

            foreach (var memberId in ids)
                await db.ExecuteAsync(
                    """
                    INSERT INTO conversation_member (conversation_id, user_id)
                    VALUES (@conversationId, @memberId)
                    ON CONFLICT (conversation_id, user_id)
                    DO UPDATE SET left_at=NULL, hidden_at=NULL
                    """, new { conversationId, memberId }, ct);
            return ApiSupport.Created($"/api/v1/conversations/{conversationId}", conversation);
        });

        api.MapGet("/conversations/{id:guid}/messages", async (
            Guid id, HttpContext context, Db db, DateTime? before, int? limit, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var member = await db.ScalarAsync<long>(
                """
                SELECT count(*) FROM conversation_member
                WHERE conversation_id=@id AND user_id=@userId AND left_at IS NULL
                """, new { id, userId }, ct);
            if (member == 0) throw new ApiException(403, "forbidden", "无权访问该会话");
            var take = Math.Clamp(limit ?? 50, 1, 100);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT m.id, m.sender_user_id, m.message_type, m.body, m.media_asset_id,
                       m.reply_to_message_id, m.edited_at, m.recalled_at, m.created_at,
                       up.nickname AS sender_name, up.avatar_url AS sender_avatar
                FROM message m
                LEFT JOIN user_profile up ON up.user_id=m.sender_user_id
                WHERE m.conversation_id=@id AND m.deleted_at IS NULL
                  AND (CAST(@before AS timestamptz) IS NULL OR m.created_at < @before)
                ORDER BY m.created_at DESC, m.id DESC
                LIMIT @limit
                """, new { id, before, limit = take }, ct));
        });

        api.MapPost("/conversations/{id:guid}/messages", async (
            Guid id, HttpContext context, SendMessageRequest request, Db db,
            RealtimeConnectionManager realtime, PushNotificationService push,
            CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var allowed = await db.ScalarAsync<long>(
                """
                SELECT count(*)
                FROM conversation_member cm
                JOIN conversation c ON c.id=cm.conversation_id
                WHERE cm.conversation_id=@id AND cm.user_id=@userId
                  AND cm.left_at IS NULL AND c.status='active'
                """, new { id, userId }, ct);
            if (allowed == 0) throw new ApiException(403, "forbidden", "无权在该会话发言");
            if (request.MessageType == "event_cancelled")
                throw new ApiException(400, "reserved_message_type", "不能发送系统活动通知");
            if (string.IsNullOrWhiteSpace(request.Body) && request.MediaAssetId is null)
                throw new ApiException(400, "empty_message", "消息不能为空");

            var message = await db.QueryOneAsync(
                """
                INSERT INTO message (
                    conversation_id, sender_user_id, message_type, body,
                    media_asset_id, reply_to_message_id, client_message_id
                )
                VALUES (
                    @id, @userId, @messageType, @body,
                    @mediaAssetId, @replyToMessageId, @clientMessageId
                )
                RETURNING id, conversation_id, sender_user_id, message_type, body,
                          media_asset_id, reply_to_message_id, created_at
                """, new
                {
                    id,
                    userId,
                    messageType = request.MessageType ?? "text",
                    request.Body,
                    request.MediaAssetId,
                    request.ReplyToMessageId,
                    request.ClientMessageId
                }, ct);
            await db.ExecuteAsync(
                "UPDATE conversation SET updated_at=now() WHERE id=@id", new { id }, ct);
            await db.ExecuteAsync(
                """
                UPDATE conversation_member cm
                SET hidden_at=NULL
                FROM conversation c
                WHERE cm.conversation_id=@id AND c.id=cm.conversation_id
                  AND c.conversation_type='direct' AND cm.left_at IS NULL
                """, new { id }, ct);
            await db.ExecuteAsync(
                """
                INSERT INTO notification (user_id, notification_type, title, body, data)
                SELECT cm.user_id, 'new_message',
                       CASE WHEN c.conversation_type='event' THEN '活动群有新消息' ELSE '收到新消息' END,
                       COALESCE(NULLIF(@body, ''), '收到一条新消息'),
                       jsonb_build_object('conversationId', c.id, 'messageId', @messageId)
                FROM conversation_member cm
                JOIN conversation c ON c.id=cm.conversation_id
                WHERE cm.conversation_id=@id AND cm.left_at IS NULL AND cm.user_id<>@userId
                """, new
                {
                    id,
                    userId,
                    body = request.Body?.Trim(),
                    messageId = (Guid)message!["id"]!
                }, ct);
            var recipients = await db.QueryAsync(
                """
                SELECT user_id FROM conversation_member
                WHERE conversation_id=@id AND left_at IS NULL
                """, new { id }, ct);
            var recipientIds = recipients
                .Select(row => (Guid)row["user_id"]!)
                .ToArray();
            await realtime.PublishAsync(recipientIds, "message.created", new
            {
                conversationId = id,
                messageId = (Guid)message!["id"]!
            }, ct);
            var pushRecipients = recipientIds.Where(recipientId => recipientId != userId).ToArray();
            var pushBody = string.IsNullOrWhiteSpace(request.Body) ? "收到一条新消息" : request.Body.Trim();
            await push.SendToUsersAsync(db, pushRecipients, "收到新消息", pushBody, new Dictionary<string, string>
            {
                ["type"] = "message.created",
                ["conversationId"] = id.ToString(),
                ["messageId"] = ((Guid)message!["id"]!).ToString()
            }, ct);
            return ApiSupport.Created($"/api/v1/conversations/{id}/messages/{message!["id"]}", message);
        });

        api.MapPost("/conversations/{id:guid}/read-latest", async (
            Guid id, HttpContext context, Db db,
            RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var updated = await db.ExecuteAsync(
                """
                UPDATE conversation_member cm
                SET last_read_at=now(),
                    last_read_message_id=(
                        SELECT m.id FROM message m
                        WHERE m.conversation_id=cm.conversation_id AND m.deleted_at IS NULL
                        ORDER BY m.created_at DESC, m.id DESC LIMIT 1
                    )
                WHERE cm.conversation_id=@id AND cm.user_id=@userId AND cm.left_at IS NULL
                """, new { id, userId }, ct);
            if (updated == 0)
                throw new ApiException(404, "conversation_not_found", "会话不存在");
            await db.ExecuteAsync(
                """
                UPDATE notification SET read_at=COALESCE(read_at, now())
                WHERE user_id=@userId AND deleted_at IS NULL
                  AND notification_type='new_message'
                  AND data->>'conversationId'=@conversationId
                """, new { userId, conversationId = id.ToString() }, ct);
            await realtime.PublishAsync([userId], "unread.changed", new { conversationId = id }, ct);
            return ApiSupport.Ok(new { conversationId = id, readAt = DateTime.UtcNow });
        });

        api.MapDelete("/conversations/{id:guid}", async (
            Guid id, HttpContext context, Db db,
            RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var conversationType = await db.ScalarAsync<string>(
                """
                SELECT c.conversation_type
                FROM conversation c
                JOIN conversation_member cm ON cm.conversation_id=c.id
                WHERE c.id=@id AND cm.user_id=@userId AND cm.left_at IS NULL
                """, new { id, userId }, ct);
            if (conversationType is null)
                throw new ApiException(404, "conversation_not_found", "会话不存在");
            if (conversationType == "event")
            {
                await db.ExecuteAsync(
                    """
                    UPDATE conversation_member
                    SET left_at=now(), left_voluntarily_at=now(), hidden_at=NULL
                    WHERE conversation_id=@id AND user_id=@userId
                    """, new { id, userId }, ct);
            }
            else
            {
                await db.ExecuteAsync(
                    """
                    UPDATE conversation_member
                    SET hidden_at=now(), last_read_at=now()
                    WHERE conversation_id=@id AND user_id=@userId AND left_at IS NULL
                    """, new { id, userId }, ct);
            }
            await realtime.PublishAsync([userId], "conversation.removed", new
            {
                conversationId = id,
                conversationType
            }, ct);
            return Results.NoContent();
        });

        api.MapGet("/unread-summary", async (
            HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var summary = await db.QueryOneAsync(
                """
                SELECT
                  (SELECT count(*) FROM notification n
                   WHERE n.user_id=@userId AND n.read_at IS NULL AND n.deleted_at IS NULL) AS notification_count,
                  (SELECT count(*) FROM message m
                   JOIN conversation_member cm ON cm.conversation_id=m.conversation_id
                   WHERE cm.user_id=@userId AND cm.left_at IS NULL AND cm.hidden_at IS NULL
                     AND m.created_at > COALESCE(cm.last_read_at, '-infinity')
                     AND m.sender_user_id IS DISTINCT FROM @userId
                     AND m.deleted_at IS NULL) AS message_count
                """, new { userId }, ct);
            return ApiSupport.Ok(summary);
        });

        api.MapPost("/conversations/read-all", async (
            HttpContext context, Db db,
            RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var count = await db.ExecuteAsync(
                """
                UPDATE conversation_member cm
                SET last_read_at=now(),
                    last_read_message_id=(
                        SELECT m.id FROM message m
                        WHERE m.conversation_id=cm.conversation_id AND m.deleted_at IS NULL
                        ORDER BY m.created_at DESC, m.id DESC LIMIT 1
                    )
                WHERE cm.user_id=@userId AND cm.left_at IS NULL AND cm.hidden_at IS NULL
                """, new { userId }, ct);
            await realtime.PublishAsync([userId], "unread.changed", new { }, ct);
            return ApiSupport.Ok(new { updated = count, readAt = DateTime.UtcNow });
        });

        api.MapPost("/conversations/{id:guid}/read", async (
            Guid id, HttpContext context, ReadConversationRequest request, Db db,
            RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var count = await db.ExecuteAsync(
                """
                UPDATE conversation_member cm
                SET last_read_message_id=@messageId, last_read_at=now()
                WHERE cm.conversation_id=@id AND cm.user_id=@userId AND cm.left_at IS NULL
                  AND EXISTS (SELECT 1 FROM message m WHERE m.id=@messageId AND m.conversation_id=@id)
                """, new { id, userId, messageId = request.MessageId }, ct);
            if (count == 0) throw new ApiException(404, "conversation_not_found", "会话不存在");
            await db.ExecuteAsync(
                """
                UPDATE notification
                SET read_at=COALESCE(read_at, now())
                WHERE user_id=@userId AND notification_type='new_message'
                  AND data->>'conversationId'=@conversationId
                """, new { userId, conversationId = id.ToString() }, ct);
            await realtime.PublishAsync([userId], "unread.changed", new
            {
                conversationId = id
            }, ct);
            return ApiSupport.Ok(new { conversationId = id, readAt = DateTime.UtcNow });
        });

        api.MapPost("/reviews", async (
            HttpContext context, CreateReviewRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            if (request.Rating is < 1 or > 5)
                throw new ApiException(400, "invalid_rating", "评分必须为 1–5");
            var eligible = await db.ScalarAsync<long>(
                """
                SELECT count(*)
                FROM event_member mine
                JOIN event_member target ON target.event_id=mine.event_id
                WHERE mine.event_id=@eventId
                  AND mine.user_id=@userId AND mine.status='attended'
                  AND target.user_id=@toUserId AND target.status='attended'
                """, new { request.EventId, userId, request.ToUserId }, ct);
            if (eligible == 0) throw new ApiException(403, "review_not_allowed", "只有同场已签到成员可以互评");

            var review = await db.QueryOneAsync(
                """
                INSERT INTO review (
                    event_id, from_user_id, to_user_id, rating, tags, comment, visibility
                )
                VALUES (@eventId, @userId, @toUserId, @rating, @tags, @comment, 'aggregate')
                RETURNING id, event_id, from_user_id, to_user_id, rating, tags, created_at
                """, new
                {
                    request.EventId,
                    userId,
                    request.ToUserId,
                    request.Rating,
                    tags = request.Tags ?? [],
                    request.Comment
                }, ct);
            return ApiSupport.Created($"/api/v1/reviews/{review!["id"]}", review);
        });

        return api;
    }
}

public sealed record DirectConversationRequest(Guid OtherUserId);
public sealed record SendMessageRequest(
    string? MessageType,
    string? Body,
    Guid? MediaAssetId,
    Guid? ReplyToMessageId,
    Guid? ClientMessageId);
public sealed record ReadConversationRequest(Guid MessageId);
public sealed record CreateReviewRequest(
    Guid EventId,
    Guid ToUserId,
    short Rating,
    string[]? Tags,
    string? Comment);

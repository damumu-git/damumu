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
                SELECT c.id, c.conversation_type, c.event_id, c.title, c.status,
                       cm.last_read_at, cm.muted_until,
                       e.title AS event_title,
                       lm.id AS last_message_id, lm.body AS last_message_body,
                       lm.message_type AS last_message_type, lm.created_at AS last_message_at,
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
                    SELECT id, body, message_type, created_at
                    FROM message
                    WHERE conversation_id=c.id AND deleted_at IS NULL
                    ORDER BY created_at DESC LIMIT 1
                ) lm ON true
                WHERE cm.user_id=@userId AND cm.left_at IS NULL
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
                    DO UPDATE SET left_at=NULL
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
                  AND (@before IS NULL OR m.created_at < @before)
                ORDER BY m.created_at DESC, m.id DESC
                LIMIT @limit
                """, new { id, before, limit = take }, ct));
        });

        api.MapPost("/conversations/{id:guid}/messages", async (
            Guid id, HttpContext context, SendMessageRequest request, Db db, CancellationToken ct) =>
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
            return ApiSupport.Created($"/api/v1/conversations/{id}/messages/{message!["id"]}", message);
        });

        api.MapPost("/conversations/{id:guid}/read", async (
            Guid id, HttpContext context, ReadConversationRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var count = await db.ExecuteAsync(
                """
                UPDATE conversation_member
                SET last_read_message_id=@messageId, last_read_at=now()
                WHERE conversation_id=@id AND user_id=@userId AND left_at IS NULL
                """, new { id, userId, messageId = request.MessageId }, ct);
            if (count == 0) throw new ApiException(404, "conversation_not_found", "会话不存在");
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

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
                             AND (cm.last_read_message_id IS NULL OR
                                  (unread.created_at, unread.id) > (
                                    COALESCE((SELECT marker.created_at FROM message marker
                                              WHERE marker.id=cm.last_read_message_id), cm.last_read_at, '-infinity'),
                                    cm.last_read_message_id))
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
                  AND c.status<>'archived'
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
            Guid id, HttpContext context, Db db, string? cursor, DateTime? before,
            int? limit, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var member = await db.ScalarAsync<long>(
                """
                SELECT count(*) FROM conversation_member
                WHERE conversation_id=@id AND user_id=@userId AND left_at IS NULL
                """, new { id, userId }, ct);
            if (member == 0) throw new ApiException(403, "forbidden", "无权访问该会话");
            var take = Math.Clamp(limit ?? 50, 1, 100);
            var position = MessageCursor.Decode(cursor);
            var rows = await db.QueryAsync(
                """
                SELECT m.id, m.sender_user_id, m.message_type, m.body, m.media_asset_id,
                       m.reply_to_message_id, m.client_message_id,
                       m.edited_at, m.recalled_at, m.created_at,
                       up.nickname AS sender_name, up.avatar_url AS sender_avatar,
                       reply.body AS reply_to_body, reply.recalled_at AS reply_to_recalled_at,
                       CASE WHEN ma.id IS NULL THEN NULL ELSE '/uploads/' || ma.storage_key END AS media_url,
                       ma.mime_type AS media_mime_type
                FROM message m
                LEFT JOIN user_profile up ON up.user_id=m.sender_user_id
                LEFT JOIN message reply ON reply.id=m.reply_to_message_id
                LEFT JOIN media_asset ma ON ma.id=m.media_asset_id AND ma.deleted_at IS NULL
                WHERE m.conversation_id=@id AND m.deleted_at IS NULL
                  AND (CAST(@before AS timestamptz) IS NULL OR m.created_at < @before)
                  AND (@hasCursor=false OR (m.created_at, m.id) < (@cursorCreatedAt, @cursorMessageId))
                ORDER BY m.created_at DESC, m.id DESC
                LIMIT @limit
                """, new
                {
                    id,
                    before,
                    hasCursor = position is not null,
                    cursorCreatedAt = position?.CreatedAt ?? DateTime.UnixEpoch,
                    cursorMessageId = position?.MessageId ?? Guid.Empty,
                    limit = take + 1
                }, ct);
            var hasMore = rows.Count > take;
            if (hasMore) rows.RemoveAt(rows.Count - 1);
            string? nextCursor = null;
            if (hasMore && rows.Count > 0)
            {
                var last = rows[^1];
                nextCursor = MessageCursor.Encode((DateTime)last["created_at"]!, (Guid)last["id"]!);
            }
            return ApiSupport.Ok(new { items = rows, nextCursor, hasMore });
        });

        api.MapPost("/conversations/{id:guid}/media", async (
            Guid id, HttpContext context, IFormFile image, Db db,
            IWebHostEnvironment environment, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var allowed = await db.ScalarAsync<long>(
                """
                SELECT count(*) FROM conversation_member cm
                JOIN conversation c ON c.id=cm.conversation_id
                WHERE cm.conversation_id=@id AND cm.user_id=@userId
                  AND cm.left_at IS NULL AND c.status='active'
                """, new { id, userId }, ct);
            if (allowed == 0) throw new ApiException(403, "forbidden", "无权在该会话上传附件");
            if (image.Length is <= 0 or > 5 * 1024 * 1024)
                throw new ApiException(400, "invalid_chat_image", "聊天图片需要小于 5 MB");
            var mimeType = image.ContentType.ToLowerInvariant();
            var extension = mimeType switch
            {
                "image/jpeg" => ".jpg",
                "image/png" => ".png",
                "image/webp" => ".webp",
                _ => throw new ApiException(400, "invalid_chat_image", "仅支持 JPEG、PNG 或 WebP 图片")
            };
            var header = new byte[12];
            await using (var input = image.OpenReadStream())
            {
                if (await input.ReadAsync(header, ct) < 12)
                    throw new ApiException(400, "invalid_chat_image", "图片文件无效");
            }
            var signatureMatches = mimeType switch
            {
                "image/jpeg" => header[0] == 0xff && header[1] == 0xd8 && header[2] == 0xff,
                "image/png" => header.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }),
                "image/webp" => header.AsSpan(0, 4).SequenceEqual("RIFF"u8) && header.AsSpan(8, 4).SequenceEqual("WEBP"u8),
                _ => false
            };
            if (!signatureMatches)
                throw new ApiException(400, "invalid_chat_image", "图片内容与文件类型不匹配");
            var mediaId = Guid.NewGuid();
            var storageKey = $"messages/{userId:N}/{mediaId:N}{extension}";
            var path = Path.Combine(environment.ContentRootPath, "uploads", "messages",
                userId.ToString("N"), $"{mediaId:N}{extension}");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            try
            {
                await using (var output = File.Create(path)) await image.CopyToAsync(output, ct);
                await db.ExecuteAsync(
                    """
                    INSERT INTO media_asset (id, owner_user_id, storage_key, mime_type, byte_size, status)
                    VALUES (@mediaId, @userId, @storageKey, @mimeType, @byteSize, 'ready')
                    """, new { mediaId, userId, storageKey, mimeType, byteSize = image.Length }, ct);
            }
            catch
            {
                if (File.Exists(path)) File.Delete(path);
                throw;
            }
            return ApiSupport.Ok(new { mediaAssetId = mediaId, mediaUrl = $"/uploads/{storageKey}" });
        }).DisableAntiforgery();

        api.MapDelete("/conversations/{id:guid}/media/{mediaId:guid}", async (
            Guid id, Guid mediaId, HttpContext context, Db db,
            IWebHostEnvironment environment, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var asset = await db.QueryOneAsync(
                """
                UPDATE media_asset SET deleted_at=now()
                WHERE id=@mediaId AND owner_user_id=@userId AND deleted_at IS NULL
                  AND NOT EXISTS (SELECT 1 FROM message WHERE media_asset_id=@mediaId AND deleted_at IS NULL)
                RETURNING storage_key
                """, new { mediaId, userId }, ct);
            if (asset is null) return Results.NoContent();
            var relative = ((string)asset["storage_key"]!).Replace('/', Path.DirectorySeparatorChar);
            var path = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "uploads", relative));
            var uploads = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "uploads"));
            if (path.StartsWith(uploads, StringComparison.OrdinalIgnoreCase) && File.Exists(path)) File.Delete(path);
            return Results.NoContent();
        });

        api.MapPost("/conversations/{id:guid}/messages", async (
            Guid id, HttpContext context, SendMessageRequest request, Db db,
            RealtimeConnectionManager realtime, PushNotificationService push,
            CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var messageType = request.MessageType ?? "text";
            if (messageType is not ("text" or "image" or "file"))
                throw new ApiException(400, "reserved_message_type", "不能发送系统活动通知");
            var body = request.Body?.Trim();
            if (string.IsNullOrWhiteSpace(body) && request.MediaAssetId is null)
                throw new ApiException(400, "empty_message", "消息不能为空");
            if (body?.Length > 4000)
                throw new ApiException(400, "message_too_long", "消息最多 4000 字");

            var result = await db.SendMessageAsync(id, userId, messageType, body,
                request.MediaAssetId, request.ReplyToMessageId,
                request.ClientMessageId ?? Guid.NewGuid(), ct);
            var messageId = (Guid)result.Message["id"]!;
            if (result.Created)
            {
                await realtime.PublishAsync(result.RecipientIds, "message.created",
                    new { conversationId = id, messageId }, ct);
                var pushRecipients = result.RecipientIds.Where(recipientId => recipientId != userId);
                await push.SendToUsersAsync(db, pushRecipients, "收到新消息",
                    string.IsNullOrWhiteSpace(body) ? "收到一条新消息" : body,
                    new Dictionary<string, string>
                    {
                        ["type"] = "message.created",
                        ["conversationId"] = id.ToString(),
                        ["messageId"] = messageId.ToString()
                    }, ct);
            }
            return result.Created
                ? ApiSupport.Created($"/api/v1/conversations/{id}/messages/{messageId}", result.Message)
                : ApiSupport.Ok(result.Message);
        });

        api.MapPost("/conversations/{id:guid}/messages/{messageId:guid}/recall", async (
            Guid id, Guid messageId, HttpContext context, Db db,
            RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var message = await db.QueryOneAsync(
                """
                UPDATE message m SET recalled_at=now(), body=NULL, media_asset_id=NULL, updated_at=now()
                WHERE m.id=@messageId AND m.conversation_id=@id AND m.sender_user_id=@userId
                  AND m.deleted_at IS NULL AND m.recalled_at IS NULL
                  AND m.created_at >= now() - interval '5 minutes'
                  AND EXISTS (SELECT 1 FROM conversation_member cm
                              WHERE cm.conversation_id=@id AND cm.user_id=@userId AND cm.left_at IS NULL)
                RETURNING id, conversation_id, sender_user_id, message_type, body,
                          reply_to_message_id, client_message_id, recalled_at, created_at
                """, new { id, messageId, userId }, ct);
            if (message is null)
                throw new ApiException(409, "cannot_recall", "消息不存在、已撤回或超过 5 分钟");
            var recipients = await db.QueryAsync(
                "SELECT user_id FROM conversation_member WHERE conversation_id=@id AND left_at IS NULL",
                new { id }, ct);
            await realtime.PublishAsync(recipients.Select(row => (Guid)row["user_id"]!),
                "message.updated", new { conversationId = id, messageId }, ct);
            return ApiSupport.Ok(message);
        });

        api.MapPatch("/conversations/{id:guid}/messages/{messageId:guid}", async (
            Guid id, Guid messageId, HttpContext context, EditMessageRequest request,
            Db db, RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var body = request.Body?.Trim();
            if (string.IsNullOrEmpty(body) || body.Length > 4000)
                throw new ApiException(400, "invalid_message", "消息内容需要为 1–4000 字");
            var message = await db.QueryOneAsync(
                """
                UPDATE message m SET body=@body, edited_at=now(), updated_at=now()
                WHERE m.id=@messageId AND m.conversation_id=@id AND m.sender_user_id=@userId
                  AND m.message_type='text' AND m.deleted_at IS NULL AND m.recalled_at IS NULL
                  AND m.created_at >= now() - interval '15 minutes'
                  AND EXISTS (SELECT 1 FROM conversation_member cm
                              WHERE cm.conversation_id=@id AND cm.user_id=@userId AND cm.left_at IS NULL)
                RETURNING id, conversation_id, sender_user_id, message_type, body,
                          reply_to_message_id, client_message_id, edited_at, recalled_at, created_at
                """, new { id, messageId, userId, body }, ct);
            if (message is null)
                throw new ApiException(409, "cannot_edit", "消息不存在、已撤回或超过 15 分钟");
            var recipients = await db.QueryAsync(
                "SELECT user_id FROM conversation_member WHERE conversation_id=@id AND left_at IS NULL",
                new { id }, ct);
            await realtime.PublishAsync(recipients.Select(row => (Guid)row["user_id"]!),
                "message.updated", new { conversationId = id, messageId }, ct);
            return ApiSupport.Ok(message);
        });

        api.MapPost("/conversations/{id:guid}/messages/{messageId:guid}/report", async (
            Guid id, Guid messageId, HttpContext context, ReportMessageRequest request,
            Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var allowedCategories = new[] { "harassment", "inappropriate_content", "spam", "fraud", "privacy_violation", "unsafe_behavior" };
            if (!allowedCategories.Contains(request.CategoryCode))
                throw new ApiException(400, "invalid_report_category", "请选择有效的举报原因");
            var description = request.Description?.Trim();
            if (description?.Length > 1000)
                throw new ApiException(400, "report_description_too_long", "举报说明最多 1000 字");
            return ApiSupport.Created($"/api/v1/reports", await db.ReportMessageAsync(
                id, messageId, userId, request.CategoryCode, description, ct));
        });

        api.MapPost("/conversations/{id:guid}/read-latest", async (
            Guid id, HttpContext context, Db db,
            RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var updated = await db.ExecuteAsync(
                """
                UPDATE conversation_member cm
                SET (last_read_at, last_read_message_id)=(
                        SELECT m.created_at, m.id FROM message m
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
                     AND (cm.last_read_message_id IS NULL OR
                          (m.created_at, m.id) > (
                            COALESCE((SELECT marker.created_at FROM message marker
                                      WHERE marker.id=cm.last_read_message_id), cm.last_read_at, '-infinity'),
                            cm.last_read_message_id))
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
                SET (last_read_at, last_read_message_id)=(
                        SELECT m.created_at, m.id FROM message m
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
                SET last_read_message_id=target.id, last_read_at=target.created_at
                FROM message target
                WHERE cm.conversation_id=@id AND cm.user_id=@userId AND cm.left_at IS NULL
                  AND target.id=@messageId AND target.conversation_id=@id
                  AND (cm.last_read_message_id IS NULL OR
                       (target.created_at, target.id) >= (
                         COALESCE((SELECT marker.created_at FROM message marker
                                   WHERE marker.id=cm.last_read_message_id), cm.last_read_at, '-infinity'),
                         cm.last_read_message_id))
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
public sealed record EditMessageRequest(string? Body);
public sealed record ReportMessageRequest(string CategoryCode, string? Description);
public sealed record CreateReviewRequest(
    Guid EventId,
    Guid ToUserId,
    short Rating,
    string[]? Tags,
    string? Comment);

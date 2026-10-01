using System.Data;
using Npgsql;
using NpgsqlTypes;

namespace Muda.Api.Infrastructure;

public sealed class Db(NpgsqlDataSource dataSource)
{
    public async Task<List<Dictionary<string, object?>>> QueryAsync(
        string sql,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        await using var command = dataSource.CreateCommand(sql);
        AddParameters(command, parameters);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<Dictionary<string, object?>>();
        while (await reader.ReadAsync(cancellationToken))
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (var index = 0; index < reader.FieldCount; index++)
            {
                row[reader.GetName(index)] = await reader.IsDBNullAsync(index, cancellationToken)
                    ? null
                    : reader.GetValue(index);
            }
            rows.Add(row);
        }
        return rows;
    }

    public async Task<Dictionary<string, object?>?> QueryOneAsync(
        string sql,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        var rows = await QueryAsync(sql, parameters, cancellationToken);
        return rows.FirstOrDefault();
    }

    public async Task<int> ExecuteAsync(
        string sql,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        await using var command = dataSource.CreateCommand(sql);
        AddParameters(command, parameters);
        return await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<T?> ScalarAsync<T>(
        string sql,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        await using var command = dataSource.CreateCommand(sql);
        AddParameters(command, parameters);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        if (result is null or DBNull) return default;
        if (result is T typed) return typed;
        return (T)Convert.ChangeType(result, typeof(T));
    }

    public async Task<MessageSendResult> SendMessageAsync(
        Guid conversationId, Guid userId, string messageType, string? body,
        Guid? mediaAssetId, Guid? replyToMessageId, Guid clientMessageId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        Dictionary<string, object?>? existingMessage = null;
        await using (var existing = new NpgsqlCommand(
            """
            SELECT id, conversation_id, sender_user_id, message_type, body,
                   media_asset_id, reply_to_message_id, client_message_id,
                   edited_at, recalled_at, created_at
            FROM message WHERE sender_user_id=@userId AND client_message_id=@clientMessageId
            """, connection, transaction))
        {
            existing.Parameters.AddWithValue("userId", userId);
            existing.Parameters.AddWithValue("clientMessageId", clientMessageId);
            await using var reader = await existing.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                var row = ReadRow(reader);
                if ((Guid)row["conversation_id"]! != conversationId)
                    throw new ApiException(409, "client_message_conflict", "消息标识已被其它会话使用");
                existingMessage = row;
            }
        }
        if (existingMessage is not null)
        {
            await transaction.CommitAsync(cancellationToken);
            return new(existingMessage, [], false, "");
        }

        string conversationType;
        await using (var access = new NpgsqlCommand(
            """
            SELECT c.conversation_type, c.status
            FROM conversation_member cm JOIN conversation c ON c.id=cm.conversation_id
            WHERE cm.conversation_id=@conversationId AND cm.user_id=@userId AND cm.left_at IS NULL
            FOR UPDATE OF c
            """, connection, transaction))
        {
            access.Parameters.AddWithValue("conversationId", conversationId);
            access.Parameters.AddWithValue("userId", userId);
            await using var reader = await access.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
                throw new ApiException(403, "forbidden", "无权在该会话发言");
            conversationType = reader.GetString(0);
            if (reader.GetString(1) != "active")
                throw new ApiException(409, "conversation_read_only", "该活动群已结束，只能查看历史消息");
        }

        if (replyToMessageId is not null)
        {
            await using var reply = new NpgsqlCommand(
                "SELECT count(*) FROM message WHERE id=@replyId AND conversation_id=@conversationId AND deleted_at IS NULL",
                connection, transaction);
            reply.Parameters.AddWithValue("replyId", replyToMessageId.Value);
            reply.Parameters.AddWithValue("conversationId", conversationId);
            if (Convert.ToInt64(await reply.ExecuteScalarAsync(cancellationToken)) == 0)
                throw new ApiException(400, "invalid_reply", "回复的消息不存在");
        }
        if (mediaAssetId is not null)
        {
            await using var media = new NpgsqlCommand(
                "SELECT count(*) FROM media_asset WHERE id=@mediaAssetId AND owner_user_id=@userId AND status='ready' AND deleted_at IS NULL",
                connection, transaction);
            media.Parameters.AddWithValue("mediaAssetId", mediaAssetId.Value);
            media.Parameters.AddWithValue("userId", userId);
            if (Convert.ToInt64(await media.ExecuteScalarAsync(cancellationToken)) == 0)
                throw new ApiException(400, "invalid_media", "消息附件不存在或不可用");
        }

        Dictionary<string, object?> message;
        await using (var insert = new NpgsqlCommand(
            """
            INSERT INTO message (conversation_id, sender_user_id, message_type, body,
                                 media_asset_id, reply_to_message_id, client_message_id)
            VALUES (@conversationId, @userId, @messageType, @body,
                    @mediaAssetId, @replyToMessageId, @clientMessageId)
            RETURNING id, conversation_id, sender_user_id, message_type, body,
                      media_asset_id, reply_to_message_id, client_message_id,
                      edited_at, recalled_at, created_at
            """, connection, transaction))
        {
            insert.Parameters.AddWithValue("conversationId", conversationId);
            insert.Parameters.AddWithValue("userId", userId);
            insert.Parameters.AddWithValue("messageType", messageType);
            insert.Parameters.AddWithValue("body", (object?)body ?? DBNull.Value);
            insert.Parameters.AddWithValue("mediaAssetId", (object?)mediaAssetId ?? DBNull.Value);
            insert.Parameters.AddWithValue("replyToMessageId", (object?)replyToMessageId ?? DBNull.Value);
            insert.Parameters.AddWithValue("clientMessageId", clientMessageId);
            await using var reader = await insert.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            message = ReadRow(reader);
        }

        await using (var update = new NpgsqlCommand(
            "UPDATE conversation SET updated_at=now() WHERE id=@conversationId", connection, transaction))
        {
            update.Parameters.AddWithValue("conversationId", conversationId);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }
        if (conversationType == "direct")
        {
            await using var reveal = new NpgsqlCommand(
                "UPDATE conversation_member SET hidden_at=NULL WHERE conversation_id=@conversationId AND left_at IS NULL",
                connection, transaction);
            reveal.Parameters.AddWithValue("conversationId", conversationId);
            await reveal.ExecuteNonQueryAsync(cancellationToken);
        }

        var recipients = new List<Guid>();
        await using (var notify = new NpgsqlCommand(
            """
            WITH recipients AS (
                SELECT user_id FROM conversation_member
                WHERE conversation_id=@conversationId AND left_at IS NULL
            ), inserted AS (
                INSERT INTO notification (user_id, notification_type, title, body, data)
                SELECT user_id, 'new_message',
                       CASE WHEN @conversationType='event' THEN '活动群有新消息' ELSE '收到新消息' END,
                       COALESCE(NULLIF(@body, ''), '收到一条新消息'),
                       jsonb_build_object('conversationId', @conversationId, 'messageId', @messageId)
                FROM recipients WHERE user_id<>@userId
            ) SELECT user_id FROM recipients
            """, connection, transaction))
        {
            notify.Parameters.AddWithValue("conversationId", conversationId);
            notify.Parameters.AddWithValue("conversationType", conversationType);
            notify.Parameters.AddWithValue("body", (object?)body ?? DBNull.Value);
            notify.Parameters.AddWithValue("messageId", (Guid)message["id"]!);
            notify.Parameters.AddWithValue("userId", userId);
            await using var reader = await notify.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken)) recipients.Add(reader.GetGuid(0));
        }

        await transaction.CommitAsync(cancellationToken);
        return new(message, recipients.ToArray(), true, conversationType);
    }

    public async Task<Dictionary<string, object?>> ReportMessageAsync(
        Guid conversationId, Guid messageId, Guid reporterUserId,
        string categoryCode, string? description, CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);
        Guid reportedUserId;
        await using (var target = new NpgsqlCommand(
            """
            SELECT m.sender_user_id FROM message m
            JOIN conversation_member cm ON cm.conversation_id=m.conversation_id
            WHERE m.id=@messageId AND m.conversation_id=@conversationId
              AND cm.user_id=@reporterUserId AND cm.left_at IS NULL AND m.deleted_at IS NULL
            """, connection, transaction))
        {
            target.Parameters.AddWithValue("messageId", messageId);
            target.Parameters.AddWithValue("conversationId", conversationId);
            target.Parameters.AddWithValue("reporterUserId", reporterUserId);
            var sender = await target.ExecuteScalarAsync(cancellationToken);
            if (sender is not Guid senderId)
                throw new ApiException(404, "message_not_found", "消息不存在或无权举报");
            if (senderId == reporterUserId)
                throw new ApiException(400, "cannot_report_self", "不能举报自己的消息");
            reportedUserId = senderId;
        }

        Dictionary<string, object?> report;
        await using (var insert = new NpgsqlCommand(
            """
            INSERT INTO report (reporter_user_id, target_type, target_id, reported_user_id,
                                category_code, description, priority)
            VALUES (@reporterUserId, 'message', @messageId, @reportedUserId,
                    @categoryCode, @description, 2)
            RETURNING id, target_type, target_id, category_code, priority, status, created_at
            """, connection, transaction))
        {
            insert.Parameters.AddWithValue("reporterUserId", reporterUserId);
            insert.Parameters.AddWithValue("messageId", messageId);
            insert.Parameters.AddWithValue("reportedUserId", reportedUserId);
            insert.Parameters.AddWithValue("categoryCode", categoryCode);
            insert.Parameters.AddWithValue("description", (object?)description ?? DBNull.Value);
            await using var reader = await insert.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            report = ReadRow(reader);
        }

        await using (var evidence = new NpgsqlCommand(
            """
            INSERT INTO report_evidence (report_id, evidence_type, snapshot)
            SELECT @reportId, 'message_context', jsonb_build_object(
                'conversationId', @conversationId, 'reportedMessageId', @messageId,
                'capturedAt', now(), 'messages', COALESCE(jsonb_agg(jsonb_build_object(
                    'id', context.id, 'senderUserId', context.sender_user_id,
                    'messageType', context.message_type, 'body', context.body,
                    'createdAt', context.created_at, 'recalledAt', context.recalled_at)
                    ORDER BY context.created_at, context.id), '[]'::jsonb))
            FROM (
                SELECT m.* FROM message m
                WHERE m.conversation_id=@conversationId AND m.deleted_at IS NULL
                ORDER BY abs(extract(epoch FROM (m.created_at -
                    (SELECT created_at FROM message WHERE id=@messageId)))), m.created_at, m.id
                LIMIT 11
            ) context
            """, connection, transaction))
        {
            evidence.Parameters.AddWithValue("reportId", (Guid)report["id"]!);
            evidence.Parameters.AddWithValue("conversationId", conversationId);
            evidence.Parameters.AddWithValue("messageId", messageId);
            await evidence.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        return report;
    }

    public async Task<Dictionary<string, object?>> JoinEventAsync(
        Guid eventId,
        Guid userId,
        short partySize,
        string? note,
        bool shareContact,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);

        await using var eventCommand = new NpgsqlCommand(
            """
            SELECT id, organizer_user_id, status, approval_mode, capacity, approved_count, waitlist_count, title
            FROM event
            WHERE id = @eventId AND deleted_at IS NULL
            FOR UPDATE
            """, connection, transaction);
        eventCommand.Parameters.AddWithValue("eventId", eventId);

        await using var reader = await eventCommand.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
            throw new ApiException(404, "event_not_found", "活动不存在");

        var organizerId = reader.GetGuid(1);
        var eventStatus = reader.GetString(2);
        var approvalMode = reader.GetString(3);
        var capacity = reader.GetInt16(4);
        var approvedCount = reader.GetInt16(5);
        var waitlistCount = reader.GetInt16(6);
        var eventTitle = reader.GetString(7);
        await reader.CloseAsync();

        if (organizerId == userId)
            throw new ApiException(409, "organizer_cannot_join", "组织者已是活动成员");
        await using (var existingCommand = new NpgsqlCommand(
            "SELECT status FROM event_member WHERE event_id=@eventId AND user_id=@userId FOR UPDATE",
            connection, transaction))
        {
            existingCommand.Parameters.AddWithValue("eventId", eventId);
            existingCommand.Parameters.AddWithValue("userId", userId);
            var existingStatus = await existingCommand.ExecuteScalarAsync(cancellationToken);
            if (existingStatus is not null)
                throw new ApiException(409, "already_applied", "你已经申请过该活动，不能重复申请");
        }
        if (eventStatus is not ("published" or "full"))
            throw new ApiException(409, "event_not_joinable", "当前活动不可报名");

        if (approvedCount + partySize > capacity && approvalMode != "manual")
            throw new ApiException(409, "event_full", "剩余名额不足");
        var status = approvalMode == "manual"
            ? "applied"
            : approvedCount + partySize <= capacity ? "approved" : "waitlisted";
        int? waitlistPosition = null;
        if (status == "waitlisted") waitlistPosition = waitlistCount + 1;

        await using var memberCommand = new NpgsqlCommand(
            """
            INSERT INTO event_member (
                event_id, user_id, status, waitlist_position, party_size,
                application_note, share_contact, joined_at
            )
            VALUES (
                @eventId, @userId, @status, @waitlistPosition, @partySize,
                @note, @shareContact,
                CASE WHEN @status = 'approved' THEN now() ELSE NULL END
            )
            RETURNING id, event_id, user_id, status, waitlist_position,
                      party_size, share_contact, application_note, created_at
            """, connection, transaction);
        memberCommand.Parameters.AddWithValue("eventId", eventId);
        memberCommand.Parameters.AddWithValue("userId", userId);
        memberCommand.Parameters.AddWithValue("status", status);
        memberCommand.Parameters.AddWithValue("waitlistPosition", (object?)waitlistPosition ?? DBNull.Value);
        memberCommand.Parameters.AddWithValue("partySize", partySize);
        memberCommand.Parameters.AddWithValue("note", (object?)note ?? DBNull.Value);
        memberCommand.Parameters.AddWithValue("shareContact", shareContact);

        Dictionary<string, object?> member;
        await using (var memberReader = await memberCommand.ExecuteReaderAsync(cancellationToken))
        {
            await memberReader.ReadAsync(cancellationToken);
            member = ReadRow(memberReader);
        }

        var approvedDelta = status == "approved" ? partySize : 0;
        var waitlistDelta = status == "waitlisted" ? 1 : 0;
        await using var updateCommand = new NpgsqlCommand(
            """
            UPDATE event
            SET approved_count = approved_count + @approvedDelta,
                waitlist_count = waitlist_count + @waitlistDelta,
                status = CASE
                    WHEN approved_count + @approvedDelta >= capacity THEN 'full'
                    ELSE status
                END
            WHERE id = @eventId
            """, connection, transaction);
        updateCommand.Parameters.AddWithValue("eventId", eventId);
        updateCommand.Parameters.AddWithValue("approvedDelta", approvedDelta);
        updateCommand.Parameters.AddWithValue("waitlistDelta", waitlistDelta);
        await updateCommand.ExecuteNonQueryAsync(cancellationToken);

        await using var organizerNotification = new NpgsqlCommand(
            """
            INSERT INTO notification (user_id, notification_type, title, body, data)
            VALUES (@organizerId, 'event_application_received', '活动收到新报名',
                    @body, jsonb_build_object('eventId', @eventId, 'applicantUserId', @userId, 'status', @status))
            """, connection, transaction);
        organizerNotification.Parameters.AddWithValue("organizerId", organizerId);
        organizerNotification.Parameters.AddWithValue("eventId", eventId);
        organizerNotification.Parameters.AddWithValue("userId", userId);
        organizerNotification.Parameters.AddWithValue("status", status);
        organizerNotification.Parameters.AddWithValue("body", $"有人报名了「{eventTitle}」，请查看报名信息");
        await organizerNotification.ExecuteNonQueryAsync(cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return member;
    }

    public Task<Dictionary<string, object?>> ReviewMemberAsync(
        Guid eventId,
        Guid memberUserId,
        Guid reviewerUserId,
        bool approve,
        string? rejectionReason,
        CancellationToken cancellationToken) =>
        ReviewMemberCoreAsync(
            eventId, memberUserId, reviewerUserId, approve, rejectionReason,
            allowAdministrativeReview: false, cancellationToken: cancellationToken);

    public Task<Dictionary<string, object?>> ReviewMemberAsAdminAsync(
        Guid eventId,
        Guid memberUserId,
        Guid? actorUserId,
        CancellationToken cancellationToken) =>
        ReviewMemberCoreAsync(
            eventId, memberUserId, actorUserId, approve: true, rejectionReason: null,
            allowAdministrativeReview: true, cancellationToken: cancellationToken);

    private async Task<Dictionary<string, object?>> ReviewMemberCoreAsync(
        Guid eventId,
        Guid memberUserId,
        Guid? reviewerUserId,
        bool approve,
        string? rejectionReason,
        bool allowAdministrativeReview,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);

        await using var eventCommand = new NpgsqlCommand(
            "SELECT organizer_user_id, capacity, approved_count, title, status FROM event WHERE id=@eventId FOR UPDATE",
            connection, transaction);
        eventCommand.Parameters.AddWithValue("eventId", eventId);
        await using var eventReader = await eventCommand.ExecuteReaderAsync(cancellationToken);
        if (!await eventReader.ReadAsync(cancellationToken))
            throw new ApiException(404, "event_not_found", "活动不存在");
        if (!allowAdministrativeReview && eventReader.GetGuid(0) != reviewerUserId)
            throw new ApiException(403, "forbidden", "只有组织者可以审核成员");
        if (eventReader.GetString(4) is "cancelled" or "completed")
            throw new ApiException(409, "event_closed", "活动已结束或取消，无法审核成员");
        var capacity = eventReader.GetInt16(1);
        var approvedCount = eventReader.GetInt16(2);
        var eventTitle = eventReader.GetString(3);
        await eventReader.CloseAsync();

        await using var sizeCommand = new NpgsqlCommand(
            "SELECT party_size FROM event_member WHERE event_id=@eventId AND user_id=@memberUserId AND status='applied' FOR UPDATE",
            connection, transaction);
        sizeCommand.Parameters.AddWithValue("eventId", eventId);
        sizeCommand.Parameters.AddWithValue("memberUserId", memberUserId);
        var partySizeResult = await sizeCommand.ExecuteScalarAsync(cancellationToken);
        if (partySizeResult is null)
            throw new ApiException(404, "application_not_found", "待审核申请不存在");
        var partySize = Convert.ToInt16(partySizeResult);
        if (approve && approvedCount + partySize > capacity)
            throw new ApiException(409, "event_full", "活动名额已满");

        await using var command = new NpgsqlCommand(
            """
            UPDATE event_member
            SET status=@status,
                reviewed_by_user_id=@reviewerUserId,
                reviewed_at=now(),
                rejection_reason=CASE WHEN @status='rejected' THEN @rejectionReason ELSE NULL END,
                joined_at=CASE WHEN @status='approved' THEN now() ELSE joined_at END
            WHERE event_id=@eventId AND user_id=@memberUserId AND status='applied'
            RETURNING id, event_id, user_id, status, party_size,
                      rejection_reason, reviewed_at
            """, connection, transaction);
        command.Parameters.AddWithValue("status", approve ? "approved" : "rejected");
        command.Parameters.AddWithValue("reviewerUserId", (object?)reviewerUserId ?? DBNull.Value);
        command.Parameters.AddWithValue("eventId", eventId);
        command.Parameters.AddWithValue("memberUserId", memberUserId);
        command.Parameters.AddWithValue("rejectionReason", (object?)rejectionReason ?? DBNull.Value);

        Dictionary<string, object?> member;
        await using (var memberReader = await command.ExecuteReaderAsync(cancellationToken))
        {
            if (!await memberReader.ReadAsync(cancellationToken))
                throw new ApiException(404, "application_not_found", "待审核申请不存在");
            member = ReadRow(memberReader);
        }

        if (approve)
        {
            await using var update = new NpgsqlCommand(
                """
                UPDATE event
                SET approved_count=approved_count+@partySize,
                    status=CASE WHEN approved_count+@partySize >= capacity THEN 'full' ELSE status END
                WHERE id=@eventId
                """, connection, transaction);
            update.Parameters.AddWithValue("eventId", eventId);
            update.Parameters.AddWithValue("partySize", partySize);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }

        await using var notification = new NpgsqlCommand(
            """
            INSERT INTO notification (user_id, notification_type, title, body, data)
            VALUES (@memberUserId, @type, @title, @body,
                    jsonb_build_object('eventId', @eventId, 'status', @status))
            """, connection, transaction);
        notification.Parameters.AddWithValue("memberUserId", memberUserId);
        notification.Parameters.AddWithValue("type", approve
            ? "event_application_approved" : "event_application_rejected");
        notification.Parameters.AddWithValue("title", approve ? "活动申请已通过" : "活动申请未通过");
        notification.Parameters.AddWithValue("body", approve
            ? $"你申请的「{eventTitle}」已通过"
            : $"你申请的「{eventTitle}」未通过：{rejectionReason}");
        notification.Parameters.AddWithValue("eventId", eventId);
        notification.Parameters.AddWithValue("status", approve ? "approved" : "rejected");
        await notification.ExecuteNonQueryAsync(cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return member;
    }

    private static Dictionary<string, object?> ReadRow(NpgsqlDataReader reader)
    {
        var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        for (var index = 0; index < reader.FieldCount; index++)
            row[reader.GetName(index)] = reader.IsDBNull(index) ? null : reader.GetValue(index);
        return row;
    }

    private static void AddParameters(NpgsqlCommand command, object? parameters)
    {
        if (parameters is null) return;
        foreach (var property in parameters.GetType().GetProperties())
        {
            var value = property.GetValue(parameters);
            var parameter = new NpgsqlParameter(property.Name, value ?? DBNull.Value);
            if (value is null)
            {
                var type = Nullable.GetUnderlyingType(property.PropertyType) ?? property.PropertyType;
                parameter.NpgsqlDbType = type switch
                {
                    _ when type == typeof(string) => NpgsqlDbType.Text,
                    _ when type == typeof(Guid) => NpgsqlDbType.Uuid,
                    _ when type == typeof(DateTime) => NpgsqlDbType.TimestampTz,
                    _ when type == typeof(DateTimeOffset) => NpgsqlDbType.TimestampTz,
                    _ when type == typeof(short) => NpgsqlDbType.Smallint,
                    _ when type == typeof(int) => NpgsqlDbType.Integer,
                    _ when type == typeof(long) => NpgsqlDbType.Bigint,
                    _ when type == typeof(bool) => NpgsqlDbType.Boolean,
                    _ when type == typeof(decimal) => NpgsqlDbType.Numeric,
                    _ when type == typeof(double) => NpgsqlDbType.Double,
                    _ when type == typeof(Guid[]) => NpgsqlDbType.Array | NpgsqlDbType.Uuid,
                    _ when type == typeof(string[]) => NpgsqlDbType.Array | NpgsqlDbType.Text,
                    _ => NpgsqlDbType.Unknown
                };
            }
            command.Parameters.Add(parameter);
        }
    }
}

public sealed record MessageSendResult(
    Dictionary<string, object?> Message,
    Guid[] RecipientIds,
    bool Created,
    string ConversationType);

public sealed class ApiException(int statusCode, string code, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
    public string Code { get; } = code;
}

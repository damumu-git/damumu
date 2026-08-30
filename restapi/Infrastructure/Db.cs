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
            SELECT id, organizer_user_id, status, approval_mode, capacity, approved_count, waitlist_count
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
        await reader.CloseAsync();

        if (organizerId == userId)
            throw new ApiException(409, "organizer_cannot_join", "组织者已是活动成员");
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
            ON CONFLICT (event_id, user_id) DO UPDATE SET
                status = EXCLUDED.status,
                waitlist_position = EXCLUDED.waitlist_position,
                party_size = EXCLUDED.party_size,
                application_note = EXCLUDED.application_note,
                share_contact = EXCLUDED.share_contact,
                rejection_reason = NULL,
                left_at = NULL,
                updated_at = now()
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

        await transaction.CommitAsync(cancellationToken);
        return member;
    }

    public async Task<Dictionary<string, object?>> ReviewMemberAsync(
        Guid eventId,
        Guid memberUserId,
        Guid reviewerUserId,
        bool approve,
        string? rejectionReason,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);

        await using var eventCommand = new NpgsqlCommand(
            "SELECT organizer_user_id, capacity, approved_count, title FROM event WHERE id=@eventId FOR UPDATE",
            connection, transaction);
        eventCommand.Parameters.AddWithValue("eventId", eventId);
        await using var eventReader = await eventCommand.ExecuteReaderAsync(cancellationToken);
        if (!await eventReader.ReadAsync(cancellationToken))
            throw new ApiException(404, "event_not_found", "活动不存在");
        if (eventReader.GetGuid(0) != reviewerUserId)
            throw new ApiException(403, "forbidden", "只有组织者可以审核成员");
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
        command.Parameters.AddWithValue("reviewerUserId", reviewerUserId);
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

public sealed class ApiException(int statusCode, string code, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
    public string Code { get; } = code;
}

using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class SafetyEndpoints
{
    public static RouteGroupBuilder MapSafetyEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/emergency-contacts", async (
            HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, is_primary, verified_at, created_at
                FROM emergency_contact
                WHERE user_id=@userId AND deleted_at IS NULL
                ORDER BY is_primary DESC, created_at
                """, new { userId }, ct));
        });

        api.MapPost("/emergency-contacts", async (
            HttpContext context, CreateEmergencyContactRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var contact = await db.QueryOneAsync(
                """
                INSERT INTO emergency_contact (
                    user_id, name_ciphertext, phone_ciphertext, phone_hash,
                    relationship_ciphertext, is_primary
                )
                VALUES (
                    @userId, convert_to(@name, 'UTF8'), convert_to(@phone, 'UTF8'),
                    digest(@phone, 'sha256'), convert_to(@relationship, 'UTF8'), @isPrimary
                )
                RETURNING id, is_primary, created_at
                """, new
                {
                    userId,
                    request.Name,
                    request.Phone,
                    relationship = request.Relationship ?? "",
                    request.IsPrimary
                }, ct);
            return ApiSupport.Created($"/api/v1/emergency-contacts/{contact!["id"]}", contact);
        });

        api.MapPost("/safety-sessions/start", async (
            HttpContext context, StartSafetySessionRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var minutes = Math.Clamp(request.CheckInIntervalMinutes, (short)15, (short)240);
            var session = await db.QueryOneAsync(
                """
                INSERT INTO safety_session (
                    user_id, event_id, emergency_contact_id, check_in_interval_minutes,
                    next_due_at, ends_at, location_consent_at
                )
                VALUES (
                    @userId, @eventId, @emergencyContactId, @minutes,
                    now() + make_interval(mins => @minutes), @endsAt,
                    CASE WHEN @shareLocation THEN now() ELSE NULL END
                )
                RETURNING id, user_id, event_id, status, check_in_interval_minutes,
                          started_at, next_due_at, ends_at
                """, new
                {
                    userId,
                    request.EventId,
                    request.EmergencyContactId,
                    minutes,
                    request.EndsAt,
                    request.ShareLocation
                }, ct);
            return ApiSupport.Created($"/api/v1/safety-sessions/{session!["id"]}", session);
        });

        api.MapGet("/safety-sessions/active", async (
            HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryOneAsync(
                """
                SELECT ss.*, e.title AS event_title
                FROM safety_session ss
                LEFT JOIN event e ON e.id=ss.event_id
                WHERE ss.user_id=@userId AND ss.status IN ('active', 'overdue', 'alerted')
                ORDER BY ss.created_at DESC LIMIT 1
                """, new { userId }, ct));
        });

        api.MapPost("/safety-sessions/{id:guid}/check-in", async (
            Guid id, HttpContext context, SafetyCheckInRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var owns = await db.ScalarAsync<long>(
                "SELECT count(*) FROM safety_session WHERE id=@id AND user_id=@userId AND status IN ('active','overdue','alerted')",
                new { id, userId }, ct);
            if (owns == 0) throw new ApiException(404, "safety_session_not_found", "安全会面不存在");

            await db.ExecuteAsync(
                """
                INSERT INTO safety_checkin (safety_session_id, status, note_ciphertext)
                VALUES (@id, @status, CASE WHEN @note IS NULL THEN NULL ELSE convert_to(@note, 'UTF8') END)
                """, new { id, request.Status, request.Note }, ct);
            var session = await db.QueryOneAsync(
                """
                UPDATE safety_session
                SET status=CASE WHEN @status='safe' THEN 'active' ELSE 'alerted' END,
                    next_due_at=now() + make_interval(mins => check_in_interval_minutes)
                WHERE id=@id
                RETURNING id, status, next_due_at, row_version
                """, new { id, request.Status }, ct);
            return ApiSupport.Ok(session);
        });

        api.MapPost("/safety-sessions/{id:guid}/alert", async (
            Guid id, HttpContext context, SafetyAlertRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var owns = await db.ScalarAsync<long>(
                "SELECT count(*) FROM safety_session WHERE id=@id AND user_id=@userId",
                new { id, userId }, ct);
            if (owns == 0) throw new ApiException(404, "safety_session_not_found", "安全会面不存在");
            var alert = await db.QueryOneAsync(
                """
                WITH changed AS (
                    UPDATE safety_session SET status='alerted' WHERE id=@id RETURNING id
                )
                INSERT INTO safety_alert (safety_session_id, alert_type)
                SELECT id, @alertType FROM changed
                RETURNING id, safety_session_id, alert_type, status, created_at
                """, new { id, alertType = request.AlertType ?? "manual_sos" }, ct);
            return ApiSupport.Created($"/api/v1/safety-alerts/{alert!["id"]}", alert);
        });

        api.MapPost("/safety-sessions/{id:guid}/end", async (
            Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var session = await db.QueryOneAsync(
                """
                UPDATE safety_session
                SET status='ended', ended_at=now(),
                    latest_location_ciphertext=NULL, location_expires_at=now()
                WHERE id=@id AND user_id=@userId AND status <> 'ended'
                RETURNING id, status, ended_at
                """, new { id, userId }, ct);
            if (session is null) throw new ApiException(404, "safety_session_not_found", "安全会面不存在");
            return ApiSupport.Ok(session);
        });

        return api;
    }
}

public sealed record CreateEmergencyContactRequest(
    string Name,
    string Phone,
    string? Relationship,
    bool IsPrimary);
public sealed record StartSafetySessionRequest(
    Guid? EventId,
    Guid? EmergencyContactId,
    short CheckInIntervalMinutes,
    DateTime? EndsAt,
    bool ShareLocation);
public sealed record SafetyCheckInRequest(string Status, string? Note);
public sealed record SafetyAlertRequest(string? AlertType);

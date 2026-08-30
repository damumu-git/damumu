using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class GovernanceEndpoints
{
    public static RouteGroupBuilder MapGovernanceEndpoints(this RouteGroupBuilder api)
    {
        api.MapPost("/reports", async (
            HttpContext context, CreateReportRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var report = await db.QueryOneAsync(
                """
                INSERT INTO report (
                    reporter_user_id, target_type, target_id, reported_user_id,
                    category_code, description, priority
                )
                VALUES (
                    @userId, @targetType, @targetId, @reportedUserId,
                    @categoryCode, @description, @priority
                )
                RETURNING id, target_type, target_id, category_code, priority, status, created_at
                """, new
                {
                    userId,
                    request.TargetType,
                    request.TargetId,
                    request.ReportedUserId,
                    request.CategoryCode,
                    request.Description,
                    priority = Math.Clamp(request.Priority ?? 3, (short)1, (short)5)
                }, ct);
            return ApiSupport.Created($"/api/v1/reports/{report!["id"]}", report);
        });

        api.MapGet("/me/reports", async (
            HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, target_type, target_id, category_code, priority, status,
                       resolution_code, resolved_at, created_at
                FROM report
                WHERE reporter_user_id=@userId
                ORDER BY created_at DESC
                """, new { userId }, ct));
        });

        return api;
    }
}

public sealed record CreateReportRequest(
    string TargetType,
    Guid TargetId,
    Guid? ReportedUserId,
    string CategoryCode,
    string? Description,
    short? Priority);

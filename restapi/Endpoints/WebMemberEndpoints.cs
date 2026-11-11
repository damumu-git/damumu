using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class WebMemberEndpoints
{
    public static RouteGroupBuilder MapWebMemberEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/me/saved", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync("""
                SELECT b.kind,b.target,b.created_at, COALESCE(g.title,e.title) AS title,
                       COALESCE(g.summary,e.description) AS summary, e.status,
                       (SELECT min(starts_at) FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled') AS starts_at,
                       (SELECT max(ends_at) FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled') AS ends_at
                FROM web_bookmark b
                LEFT JOIN web_guide g ON b.kind='guide' AND g.slug=b.target AND g.published
                LEFT JOIN event e ON e.id::text=b.target AND b.kind='activity'
                    AND e.deleted_at IS NULL AND e.visibility='public'
                    AND e.status IN ('published','full','completed','cancelled')
                WHERE b.user_id=@userId AND (g.slug IS NOT NULL OR e.id IS NOT NULL)
                ORDER BY b.created_at DESC,b.kind,b.target LIMIT 100
                """, new { userId }, ct));
        });
        api.MapGet("/me/saved/{kind}/{target}", async (string kind, string target, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var saved = await db.ScalarAsync<bool>("""
                SELECT EXISTS(SELECT 1 FROM web_bookmark WHERE user_id=@userId AND kind=@kind AND target=@target)
                """, new { userId, kind, target }, ct);
            return ApiSupport.Ok(new { saved });
        });
        api.MapPut("/me/saved/{kind}/{target}", async (string kind, string target, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var exists = kind switch
            {
                "activity" when Guid.TryParse(target, out var id) => await db.ScalarAsync<bool>("""
                    SELECT EXISTS(SELECT 1 FROM event WHERE id=@id AND visibility='public'
                      AND deleted_at IS NULL AND status IN ('published','full','completed','cancelled'))
                    """, new { id }, ct),
                "guide" when target.Length <= 80 => await db.ScalarAsync<bool>(
                    "SELECT EXISTS(SELECT 1 FROM web_guide WHERE slug=@target AND published)", new { target }, ct),
                _ => false
            };
            if (!exists) throw new ApiException(404, "bookmark_target_not_found", "内容不存在或无法收藏");
            if (kind == "activity") target = Guid.Parse(target).ToString();
            await db.ExecuteAsync("""
                INSERT INTO web_bookmark(user_id,kind,target) VALUES (@userId,@kind,@target)
                ON CONFLICT DO NOTHING
                """, new { userId, kind, target }, ct);
            return ApiSupport.Ok(new { saved = true });
        });
        api.MapDelete("/me/saved/{kind}/{target}", async (string kind, string target, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("DELETE FROM web_bookmark WHERE user_id=@userId AND kind=@kind AND target=@target",
                new { userId, kind, target }, ct);
            return ApiSupport.Ok(new { saved = false });
        });
        api.MapGet("/me/blocks", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync("""
                SELECT b.blocked_user_id AS id,COALESCE(p.nickname,'搭慕用户') AS nickname
                FROM user_block b JOIN app_user u ON u.id=b.blocked_user_id AND u.deleted_at IS NULL
                LEFT JOIN user_profile p ON p.user_id=u.id
                WHERE b.blocker_user_id=@userId ORDER BY nickname,u.id LIMIT 100
                """, new { userId }, ct));
        });
        api.MapPost("/events/{id:guid}/members/{memberUserId:guid}/check-in", async (
            Guid id, Guid memberUserId, HttpContext context, Db db, CancellationToken ct) =>
        {
            var organizer = ApiSupport.RequireUserId(context);
            var changed = await db.ExecuteAsync("""
                UPDATE event_member m SET status='attended',checked_in_at=now()
                FROM event e WHERE e.id=m.event_id AND e.id=@id AND e.organizer_user_id=@organizer
                  AND e.deleted_at IS NULL AND e.status IN ('published','full','completed')
                  AND m.user_id=@memberUserId AND m.status='approved' AND m.left_at IS NULL
                  AND EXISTS (SELECT 1 FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled'
                    AND now() >= COALESCE(s.check_in_opens_at,s.starts_at-interval '1 hour')
                    AND now() <= COALESCE(s.check_in_closes_at,s.ends_at+interval '24 hours'))
                """, new { id, memberUserId, organizer }, ct);
            if (changed == 0) throw new ApiException(409, "check_in_unavailable", "没有可签到的记录或签到时间未开放");
            return ApiSupport.Ok(new { status = "attended" });
        });
        return api;
    }
}

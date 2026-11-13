using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class WebCommunityEndpoints
{
    private const string PublicEvent = """
        e.visibility='public' AND e.deleted_at IS NULL AND e.status IN ('published','full','completed')
        """;

    public static RouteGroupBuilder MapWebCommunityEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/web/intents", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync($"""
                SELECT i.id,i.title,i.description,r.name_zh_cn AS region_name,e.id AS event_id
                FROM web_intent i JOIN administrative_region r ON r.code=i.region_code
                JOIN app_user owner ON owner.id=i.owner_id AND owner.status='active' AND owner.deleted_at IS NULL
                LEFT JOIN event e ON e.id=i.event_id AND {PublicEvent}
                ORDER BY i.created_at DESC,i.id LIMIT 100
                """, cancellationToken: ct)));

        api.MapPost("/web/intents", async (IntentInput input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var ownerId = ApiSupport.RequireUserId(context);
            var (title, description) = Validate(input.Title, input.Description);
            var id = Guid.NewGuid();
            var changed = await db.ExecuteAsync("""
                INSERT INTO web_intent(id,owner_id,title,description,region_code)
                SELECT @id,@ownerId,@title,@description,code FROM administrative_region
                WHERE code=@regionCode AND is_active
                """, new { id, ownerId, title, description, input.RegionCode }, ct);
            if (changed == 0) throw new ApiException(400, "region_invalid", "请选择地区");
            return ApiSupport.Ok(new { id });
        });

        api.MapGet("/web/intents/{id:guid}", async (Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.GetOptionalUserId(context);
            var item = await db.QueryOneAsync($"""
                SELECT i.id,i.owner_id,i.title,i.description,r.name_zh_cn AS region_name,e.id AS event_id,
                       i.event_id IS NOT NULL AS converted,
                       (SELECT slot FROM web_intent_vote WHERE intent_id=i.id AND user_id=@viewer) AS viewer_slot
                FROM web_intent i JOIN administrative_region r ON r.code=i.region_code
                JOIN app_user owner ON owner.id=i.owner_id AND owner.status='active' AND owner.deleted_at IS NULL
                LEFT JOIN event e ON e.id=i.event_id AND {PublicEvent}
                WHERE i.id=@id
                """, new { id, viewer }, ct) ?? throw Missing();
            var votes = await db.QueryAsync("""
                SELECT slot,count(*) AS count FROM web_intent_vote WHERE intent_id=@id GROUP BY slot
                """, new { id }, ct);
            return ApiSupport.Ok(new { item, votes });
        });

        api.MapPut("/web/intents/{id:guid}/vote", async (Guid id, IntentVote input,
            HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            if (input.Slot is not ("saturday" or "sunday" or "either"))
                throw new ApiException(400, "slot_invalid", "请选择时段");
            var changed = await db.ExecuteAsync("""
                INSERT INTO web_intent_vote(intent_id,user_id,slot)
                SELECT i.id,@userId,@slot FROM web_intent i
                JOIN app_user owner ON owner.id=i.owner_id AND owner.status='active' AND owner.deleted_at IS NULL
                WHERE i.id=@id AND i.event_id IS NULL FOR UPDATE OF i
                ON CONFLICT (intent_id,user_id) DO UPDATE SET slot=EXCLUDED.slot
                """, new { id, userId, input.Slot }, ct);
            if (changed == 0) throw new ApiException(409, "intent_closed", "征集已结束或不存在");
            return ApiSupport.Ok(new { saved = true });
        });

        api.MapDelete("/web/intents/{id:guid}/vote", async (Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("""
                DELETE FROM web_intent_vote v USING web_intent i
                WHERE i.id=v.intent_id AND i.id=@id AND v.user_id=@userId AND i.event_id IS NULL
                """, new { id, userId }, ct);
            return ApiSupport.Ok(new { saved = false });
        });

        api.MapPut("/web/intents/{id:guid}/event", async (Guid id, EventReference input,
            HttpContext context, Db db, CancellationToken ct) =>
        {
            var ownerId = ApiSupport.RequireUserId(context);
            var changed = await db.ExecuteAsync($"""
                UPDATE web_intent i SET event_id=e.id FROM event e
                WHERE i.id=@id AND i.owner_id=@ownerId AND i.event_id IS NULL
                    AND e.id=@eventId AND e.organizer_user_id=@ownerId
                    AND {PublicEvent} AND e.status IN ('published','full')
                """, new { id, ownerId, input.EventId }, ct);
            if (changed == 0) throw new ApiException(409, "intent_event_invalid", "只能关联自己发起的公开活动");
            return ApiSupport.Ok(new { id });
        });

        api.MapGet("/web/groups", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync("""
                SELECT g.id,g.title,g.description,(SELECT count(*) FROM web_group_member WHERE group_id=g.id) AS member_count
                FROM web_group g JOIN app_user owner ON owner.id=g.owner_id AND owner.status='active' AND owner.deleted_at IS NULL
                ORDER BY g.created_at DESC,g.id LIMIT 100
                """, cancellationToken: ct)));

        api.MapPost("/web/groups", async (GroupInput input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var ownerId = ApiSupport.RequireUserId(context);
            var (title, description) = Validate(input.Title, input.Description);
            var id = Guid.NewGuid();
            await db.ExecuteAsync("""
                WITH created AS (INSERT INTO web_group(id,owner_id,title,description)
                    VALUES (@id,@ownerId,@title,@description) RETURNING id)
                INSERT INTO web_group_member(group_id,user_id) SELECT id,@ownerId FROM created
                """, new { id, ownerId, title, description }, ct);
            return ApiSupport.Ok(new { id });
        });

        api.MapGet("/web/groups/{id:guid}", async (Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.GetOptionalUserId(context);
            var item = await db.QueryOneAsync("""
                SELECT g.id,g.owner_id,g.title,g.description,
                    EXISTS(SELECT 1 FROM web_group_member WHERE group_id=g.id AND user_id=@viewer) AS joined,
                    (SELECT count(*) FROM web_group_member WHERE group_id=g.id) AS member_count
                FROM web_group g JOIN app_user owner ON owner.id=g.owner_id AND owner.status='active' AND owner.deleted_at IS NULL
                WHERE g.id=@id
                """, new { id, viewer }, ct) ?? throw Missing();
            var events = await db.QueryAsync($"""
                SELECT e.id,e.title,e.price_amount,e.status,e.approved_count,e.capacity,c.name_zh_cn AS category_name,
                    COALESCE(p.code,c.code) AS cover_category_code,c.code AS cover_subcategory_code,
                    (SELECT min(starts_at) FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled') AS starts_at
                FROM web_group_event ge JOIN event e ON e.id=ge.event_id JOIN category c ON c.id=e.category_id
                LEFT JOIN category p ON p.id=c.parent_id
                WHERE ge.group_id=@id AND {PublicEvent} ORDER BY starts_at DESC NULLS LAST,e.id LIMIT 100
                """, new { id }, ct);
            var members = await db.QueryAsync("""
                SELECT m.user_id AS id,COALESCE(p.nickname,'搭慕用户') AS nickname
                FROM web_group_member m JOIN app_user u ON u.id=m.user_id AND u.status='active' AND u.deleted_at IS NULL
                LEFT JOIN user_profile p ON p.user_id=u.id WHERE m.group_id=@id ORDER BY nickname,u.id LIMIT 50
                """, new { id }, ct);
            return ApiSupport.Ok(new { item, events, members });
        });

        api.MapPut("/web/groups/{id:guid}/membership", async (Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            if (!await db.ScalarAsync<bool>("""
                SELECT EXISTS (SELECT 1 FROM web_group g JOIN app_user u ON u.id=g.owner_id
                    WHERE g.id=@id AND u.status='active' AND u.deleted_at IS NULL)
                """, new { id }, ct)) throw Missing();
            await db.ExecuteAsync("""
                INSERT INTO web_group_member(group_id,user_id) VALUES (@id,@userId) ON CONFLICT DO NOTHING
                """, new { id, userId }, ct);
            return ApiSupport.Ok(new { joined = true });
        });

        api.MapDelete("/web/groups/{id:guid}/membership", async (Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("""
                DELETE FROM web_group_member m USING web_group g WHERE m.group_id=g.id
                    AND g.id=@id AND m.user_id=@userId AND g.owner_id<>@userId
                """, new { id, userId }, ct);
            return ApiSupport.Ok(new { left = true });
        });

        api.MapPut("/web/groups/{id:guid}/events", async (Guid id, EventReference input,
            HttpContext context, Db db, CancellationToken ct) =>
        {
            var ownerId = ApiSupport.RequireUserId(context);
            if (!await db.ScalarAsync<bool>($"""
                SELECT EXISTS(SELECT 1 FROM web_group g,event e WHERE g.id=@id AND e.id=@eventId
                    AND g.owner_id=@ownerId AND e.organizer_user_id=@ownerId AND {PublicEvent})
                """, new { id, ownerId, input.EventId }, ct))
                throw new ApiException(403, "group_event_forbidden", "只能添加自己发起的公开活动");
            await db.ExecuteAsync("""
                INSERT INTO web_group_event(group_id,event_id) VALUES (@id,@eventId) ON CONFLICT DO NOTHING
                """, new { id, input.EventId }, ct);
            return ApiSupport.Ok(new { id });
        });

        api.MapGet("/web/follows/{targetId:guid}", async (Guid targetId, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var following = await db.ScalarAsync<bool>(
                "SELECT EXISTS(SELECT 1 FROM web_follow WHERE user_id=@userId AND target_id=@targetId)",
                new { userId, targetId }, ct);
            return ApiSupport.Ok(new { following });
        });

        api.MapPut("/web/follows/{targetId:guid}", async (Guid targetId, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            if (userId == targetId) throw new ApiException(400, "cannot_follow_self", "无法关注自己");
            if (!await db.ScalarAsync<bool>("SELECT direct_contact_visible(@userId,@targetId)",
                new { userId, targetId }, ct)) throw Missing();
            await db.ExecuteAsync("INSERT INTO web_follow(user_id,target_id) VALUES (@userId,@targetId) ON CONFLICT DO NOTHING",
                new { userId, targetId }, ct);
            return ApiSupport.Ok(new { following = true });
        });

        api.MapDelete("/web/follows/{targetId:guid}", async (Guid targetId, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("DELETE FROM web_follow WHERE user_id=@userId AND target_id=@targetId",
                new { userId, targetId }, ct);
            return ApiSupport.Ok(new { following = false });
        });

        api.MapGet("/web/following", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync($"""
                SELECT e.id,e.title,e.price_amount,p.nickname AS organizer_name,c.name_zh_cn AS category_name,
                    COALESCE(parent.code,c.code) AS cover_category_code,c.code AS cover_subcategory_code,
                    (SELECT min(starts_at) FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled') AS starts_at
                FROM event e JOIN category c ON c.id=e.category_id LEFT JOIN category parent ON parent.id=c.parent_id
                JOIN app_user organizer ON organizer.id=e.organizer_user_id AND organizer.status='active' AND organizer.deleted_at IS NULL
                LEFT JOIN user_profile p ON p.user_id=e.organizer_user_id
                WHERE {PublicEvent} AND e.status IN ('published','full')
                    AND NOT EXISTS (SELECT 1 FROM user_block b
                      WHERE (b.blocker_user_id=@userId AND b.blocked_user_id=e.organizer_user_id)
                         OR (b.blocked_user_id=@userId AND b.blocker_user_id=e.organizer_user_id))
                    AND (EXISTS(SELECT 1 FROM web_follow f WHERE f.user_id=@userId AND f.target_id=e.organizer_user_id)
                      OR EXISTS(SELECT 1 FROM web_group_event ge JOIN web_group_member m ON m.group_id=ge.group_id
                          JOIN web_group g ON g.id=ge.group_id JOIN app_user owner ON owner.id=g.owner_id
                          WHERE ge.event_id=e.id AND m.user_id=@userId AND owner.status='active' AND owner.deleted_at IS NULL))
                ORDER BY e.created_at DESC,e.id LIMIT 60
                """, new { userId }, ct));
        });

        api.MapGet("/web/map/{code}", async (string code, Db db, CancellationToken ct) =>
        {
            var item = await db.QueryOneAsync("""
                SELECT name_zh_cn AS name,
                  ST_XMin(boundary::geometry) AS west, ST_YMin(boundary::geometry) AS south,
                  ST_XMax(boundary::geometry) AS east, ST_YMax(boundary::geometry) AS north
                FROM administrative_region WHERE code=@code AND is_active AND boundary IS NOT NULL
                """, new { code }, ct) ?? throw Missing();
            return ApiSupport.Ok(item);
        });
        return api;
    }

    private static (string Title, string Description) Validate(string? title, string? description)
    {
        title = title?.Trim();
        description = description?.Trim();
        if (title is null or { Length: < 2 or > 100 } || description is null or { Length: < 2 or > 1000 })
            throw new ApiException(400, "web_content_invalid", "请填写标题和介绍");
        return (title, description);
    }

    private static ApiException Missing() => new(404, "web_content_not_found", "内容不存在或不可用");

    public sealed record IntentInput(string? Title, string? Description, string? RegionCode);
    public sealed record IntentVote(string? Slot);
    public sealed record GroupInput(string? Title, string? Description);
    public sealed record EventReference(Guid EventId);
}

using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class WebMemberEndpoints
{
    public sealed record MemberProfileUpdate(string? Bio, string? HomeRegionCode, bool ShowHomeRegion);

    public static RouteGroupBuilder MapWebMemberEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/me/member-profile", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            context.Response.Headers.CacheControl = "private, no-store";
            var userId = ApiSupport.RequireUserId(context);
            var profile = await db.QueryOneAsync("""
                SELECT p.web_public_bio AS bio, home.code AS home_region_code,
                       p.show_home_region AND home.code IS NOT NULL AS show_home_region,
                       home.name_zh_cn AS home_region_name, parent.name_zh_cn AS home_parent_name
                FROM user_profile p
                LEFT JOIN administrative_region home ON home.code=p.home_region_code AND home.is_active
                LEFT JOIN administrative_region parent ON parent.code=home.parent_code AND parent.is_active
                WHERE p.user_id=@userId
                """, new { userId }, ct);
            return ApiSupport.Ok(profile);
        });

        api.MapPut("/me/member-profile", async (MemberProfileUpdate input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var bio = input.Bio?.Trim();
            var regionCode = string.IsNullOrWhiteSpace(input.HomeRegionCode) ? null : input.HomeRegionCode.Trim();
            if (bio?.Length > 300) throw new ApiException(400, "bio_too_long", "公开简介最多 300 字");
            if (regionCode?.Length > 32) throw new ApiException(400, "invalid_home_region", "请选择有效的常驻区域");
            var changed = await db.ExecuteAsync("""
                UPDATE user_profile SET web_public_bio=NULLIF(@bio,''), home_region_code=@regionCode,
                    show_home_region=(@regionCode IS NOT NULL AND @showHomeRegion), updated_at=now()
                WHERE user_id=@userId AND (@regionCode::varchar IS NULL OR EXISTS (
                    SELECT 1 FROM administrative_region r
                    LEFT JOIN administrative_region p ON p.code=r.parent_code AND p.level=1 AND p.is_active
                    WHERE r.code=@regionCode AND r.is_active AND (r.level=1 OR (r.level=2 AND p.code IS NOT NULL))))
                """, new { userId, bio, regionCode, input.ShowHomeRegion }, ct);
            if (changed == 0) throw new ApiException(400, "invalid_home_region", "请选择有效的常驻区域");
            return ApiSupport.Ok(new { bio, home_region_code = regionCode, show_home_region = regionCode is not null && input.ShowHomeRegion });
        });

        api.MapGet("/me/following", async (HttpContext context, Db db, int? offset, CancellationToken ct) =>
        {
            context.Response.Headers.CacheControl = "private, no-store";
            var userId = ApiSupport.RequireUserId(context);
            var skip = Math.Max(offset ?? 0, 0);
            var items = await db.QueryAsync("""
                SELECT f.target_id AS id, p.nickname, COALESCE(avatar.image_url,p.avatar_url) AS avatar_url,
                       p.web_public_bio AS bio,
                       EXISTS (SELECT 1 FROM web_follow reverse_follow
                         WHERE reverse_follow.user_id=f.target_id AND reverse_follow.target_id=@userId) AS mutual
                FROM web_follow f JOIN user_profile p ON p.user_id=f.target_id
                LEFT JOIN system_avatar avatar ON p.avatar_url='system:'||avatar.id::text
                WHERE f.user_id=@userId AND direct_contact_visible(@userId,f.target_id)
                ORDER BY f.created_at DESC,f.target_id OFFSET @skip LIMIT 41
                """, new { userId, skip }, ct);
            var hasMore = items.Count > 40;
            if (hasMore) items.RemoveAt(40);
            return ApiSupport.Ok(new { items, hasMore });
        });

        api.MapGet("/me/saved", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync($"""
                SELECT b.kind,b.target,b.created_at, COALESCE(g.title,e.title) AS title,
                       COALESCE(g.summary,e.description) AS summary, e.status,
                       g.cover_category AS guide_cover_category,
                       {ActivityQueries.CoverThumbnail},
                       {ActivityQueries.CoverCategoryCodes},
                       COALESCE(e.custom_subcategory, c.name_zh_cn) AS category_name,
                       city.name_zh_cn AS city_name, district.name_zh_cn AS district_name,
                       municipality.name_zh_cn AS municipality_name,
                       (SELECT min(starts_at) FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled') AS starts_at,
                       (SELECT max(ends_at) FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled') AS ends_at
                FROM web_bookmark b
                LEFT JOIN web_guide g ON b.kind='guide' AND g.slug=b.target AND g.published
                LEFT JOIN event e ON e.id::text=b.target AND b.kind='activity'
                    AND e.deleted_at IS NULL AND e.visibility='public'
                    AND e.status IN ('published','full','completed','cancelled')
                LEFT JOIN category c ON c.id=e.category_id
                {ActivityQueries.CoverCategoryJoins}
                {ActivityQueries.CoverMediaJoin}
                LEFT JOIN administrative_region city ON city.code=e.city_code
                LEFT JOIN administrative_region district ON district.code=e.district_code
                LEFT JOIN administrative_region municipality ON district.level=3 AND municipality.code=district.parent_code
                WHERE b.user_id=@userId AND (g.slug IS NOT NULL OR e.id IS NOT NULL)
                ORDER BY b.created_at DESC,b.kind,b.target LIMIT 100
                """, new { userId }, ct));
        });
        api.MapGet("/me/saved/{kind}/{target}", async (string kind, string target, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            if (kind == "activity" && Guid.TryParse(target, out var id)) target = id.ToString();
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
            if (kind == "activity" && Guid.TryParse(target, out var id)) target = id.ToString();
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

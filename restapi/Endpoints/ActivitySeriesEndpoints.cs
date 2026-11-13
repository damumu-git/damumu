using System.Net;
using System.Text.Json;
using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class ActivitySeriesEndpoints
{
    private const string PublicEvent = """
        e.deleted_at IS NULL AND e.visibility='public'
        AND e.status IN ('published','full','completed')
        AND host.status='active' AND host.deleted_at IS NULL
        """;
    private const string Ended = """
        EXISTS (SELECT 1 FROM event_schedule WHERE event_id=e.id AND status='scheduled')
        AND NOT EXISTS (SELECT 1 FROM event_schedule WHERE event_id=e.id AND status='scheduled' AND ends_at>now())
        """;
    private const string VisibleSeries = "(s.owner_id IS NULL OR (owner.status='active' AND owner.deleted_at IS NULL))";

    public static void MapActivitySeriesEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/series", async (string? region, Guid? ownerId, bool? managed, HttpContext context, Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync($"""
                SELECT s.id,s.slug,s.title,s.description,s.owner_id,s.region_code,r.name_zh_cn AS region_name
                FROM activity_series s LEFT JOIN app_user owner ON owner.id=s.owner_id
                LEFT JOIN administrative_region r ON r.code=s.region_code
                LEFT JOIN administrative_region parent ON parent.code=r.parent_code
                WHERE {VisibleSeries} AND (@ownerId IS NULL OR s.owner_id=@ownerId)
                  AND (NOT @managed OR s.owner_id=@viewer OR s.editor_id=@viewer)
                  AND (@region IS NULL OR r.code=@region OR r.parent_code=@region OR parent.parent_code=@region)
                ORDER BY (s.owner_id IS NULL) DESC,s.created_at DESC LIMIT 100
                """, new { region, ownerId, managed = managed ?? false,
                    viewer = managed == true ? ApiSupport.RequireUserId(context) : (Guid?)null }, ct)));

        api.MapGet("/series/{key}", async (string key, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.GetOptionalUserId(context);
            var item = await db.QueryOneAsync($"""
                SELECT s.id,s.slug,s.title,s.description,s.owner_id,s.region_code,r.name_zh_cn AS region_name,
                       g.slug AS guide_slug,g.title AS guide_title,
                       COALESCE(m.subscribed,false) AS subscribed,m.interest_slot,
                       COALESCE(@viewer IN (s.owner_id,s.editor_id),false) AS can_manage,
                       (SELECT count(*) FROM activity_series_member i
                        WHERE i.series_id=s.id AND i.interest_slot IS NOT NULL) AS interest_count,
                       (SELECT count(*) FROM activity_series_member i WHERE i.series_id=s.id AND i.interest_slot='saturday') AS saturday_count,
                       (SELECT count(*) FROM activity_series_member i WHERE i.series_id=s.id AND i.interest_slot='sunday') AS sunday_count,
                       (SELECT count(*) FROM activity_series_member i WHERE i.series_id=s.id AND i.interest_slot='either') AS either_count
                FROM activity_series s LEFT JOIN app_user owner ON owner.id=s.owner_id
                LEFT JOIN administrative_region r ON r.code=s.region_code
                LEFT JOIN web_guide g ON g.slug=s.guide_slug AND g.published
                LEFT JOIN activity_series_member m ON m.series_id=s.id AND m.user_id=@viewer
                WHERE (s.slug=@key OR s.id::text=@key) AND {VisibleSeries}
                """, new { key, viewer }, ct) ?? throw new ApiException(404, "series_not_found", "活动系列不存在");
            var events = await db.QueryAsync($"""
                SELECT e.id,e.title,e.price_amount,e.status,e.approved_count,e.capacity,
                       schedule.starts_at,schedule.ends_at,
                       host_profile.nickname AS organizer_name,COALESCE(e.custom_subcategory,c.name_zh_cn) AS category_name,
                       city.name_zh_cn AS city_name,district.name_zh_cn AS district_name,
                       {ActivityQueries.CoverThumbnail},{ActivityQueries.CoverCategoryCodes},
                       recap.event_id IS NOT NULL AS has_recap, ({Ended}) AS ended
                FROM activity_series_event se JOIN event e ON e.id=se.event_id
                JOIN app_user host ON host.id=e.organizer_user_id JOIN category c ON c.id=e.category_id
                LEFT JOIN user_profile host_profile ON host_profile.user_id=host.id
                {ActivityQueries.CoverCategoryJoins}
                {ActivityQueries.CoverMediaJoin}
                LEFT JOIN administrative_region city ON city.code=e.city_code
                LEFT JOIN administrative_region district ON district.code=e.district_code
                LEFT JOIN activity_recap recap ON recap.event_id=e.id
                JOIN LATERAL (SELECT min(starts_at) AS starts_at,max(ends_at) AS ends_at
                    FROM event_schedule WHERE event_id=e.id AND status='scheduled') schedule ON schedule.starts_at IS NOT NULL
                WHERE se.series_id=@id AND {PublicEvent}
                ORDER BY (schedule.ends_at>now()) DESC,
                         CASE WHEN schedule.ends_at>now() THEN schedule.starts_at END,
                         schedule.starts_at DESC LIMIT 100
                """, new { id = item["id"] }, ct);
            return ApiSupport.Ok(new { item, events });
        });

        api.MapPost("/series", async (SeriesInput input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var title = input.Title?.Trim();
            var description = input.Description?.Trim();
            if (title is null or { Length: < 2 or > 100 } || description is null or { Length: < 2 or > 1000 })
                throw new ApiException(400, "invalid_series", "请填写 2 至 100 字的名称和 2 至 1000 字的介绍");
            var series = await db.QueryOneAsync("""
                INSERT INTO activity_series (owner_id,title,description,region_code)
                SELECT @viewer,@title,@description,r.code FROM administrative_region r
                WHERE r.code=@regionCode AND r.is_active
                RETURNING id,title,description,region_code
                """, new { viewer, title, description, input.RegionCode }, ct)
                ?? throw new ApiException(400, "invalid_region", "请选择有效地区");
            return ApiSupport.Ok(series);
        });

        api.MapPut("/series/{id:guid}/membership", async (
            Guid id, SeriesMembership input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            if (input.InterestSlot is not (null or "saturday" or "sunday" or "either"))
                throw new ApiException(400, "invalid_slot", "请选择有效时段");
            var count = await db.ExecuteAsync($"""
                INSERT INTO activity_series_member (series_id,user_id,subscribed,interest_slot)
                SELECT s.id,@viewer,@subscribed,@interestSlot FROM activity_series s
                LEFT JOIN app_user owner ON owner.id=s.owner_id WHERE s.id=@id AND {VisibleSeries}
                ON CONFLICT (series_id,user_id) DO UPDATE SET subscribed=EXCLUDED.subscribed,interest_slot=EXCLUDED.interest_slot
                """, new { id, viewer, input.Subscribed, input.InterestSlot }, ct);
            if (count == 0) throw new ApiException(404, "series_not_found", "活动系列不存在");
            return ApiSupport.Ok(input);
        });

        api.MapPut("/series/{id:guid}/events/{eventId:guid}", async (
            Guid id, Guid eventId, HttpContext context, Db db, RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var result = await db.QueryAsync("""
                WITH linked AS (
                    INSERT INTO activity_series_event(series_id,event_id)
                    SELECT s.id,e.id FROM activity_series s CROSS JOIN event e
                    WHERE s.id=@id AND @viewer IN (s.owner_id,s.editor_id) AND e.id=@eventId AND e.organizer_user_id=@viewer
                      AND e.deleted_at IS NULL AND e.visibility='public'
                      AND e.status IN ('published','full','completed')
                    ON CONFLICT (event_id) DO UPDATE SET series_id=EXCLUDED.series_id
                    WHERE activity_series_event.series_id=EXCLUDED.series_id
                    RETURNING event_id
                ), sent AS (
                    INSERT INTO activity_series_notice (event_id)
                    SELECT event_id FROM linked
                    WHERE EXISTS (SELECT 1 FROM event_schedule WHERE event_id=@eventId AND status='scheduled' AND ends_at>now())
                      AND EXISTS (SELECT 1 FROM event WHERE id=@eventId AND status IN ('published','full'))
                    ON CONFLICT DO NOTHING RETURNING event_id
                ), alerts AS (
                    INSERT INTO notification(user_id,notification_type,title,body,data)
                    SELECT m.user_id,'series_event','订阅的系列有新活动',e.title,jsonb_build_object('eventId',e.id)
                    FROM sent JOIN event e ON e.id=sent.event_id
                    JOIN activity_series_member m ON m.series_id=@id AND m.subscribed
                    WHERE m.user_id<>@viewer AND direct_contact_visible(@viewer,m.user_id)
                    RETURNING user_id
                )
                SELECT NULL::uuid AS user_id FROM linked UNION ALL SELECT user_id FROM alerts
                """, new { id, eventId, viewer }, ct);
            if (result.Count == 0) throw new ApiException(409, "series_link_unavailable", "请选择自己发布的公开活动，且活动只能加入一个系列");
            var recipients = result.Select(row => row["user_id"]).OfType<Guid>().ToArray();
            if (recipients.Length > 0)
                await realtime.PublishAsync(recipients, "notification.created", new { notificationType = "series_event" }, ct);
            return ApiSupport.Ok(new { id, eventId });
        });

        api.MapPost("/series/proposals", async (SeriesProposal input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var body = input.Body?.Trim();
            if (input.Kind is not ("organizer" or "venue") || body is null or { Length: < 2 or > 1000 })
                throw new ApiException(400, "invalid_series_proposal", "请选择合作类型并填写 2 至 1000 字");
            var row = await db.QueryOneAsync("""
                INSERT INTO activity_series_proposal (user_id,kind,region_code,body)
                SELECT @viewer,@kind,r.code,@body FROM administrative_region r WHERE r.code=@regionCode AND r.is_active
                RETURNING id
                """, new { viewer, input.Kind, input.RegionCode, body }, ct);
            if (row is null) throw new ApiException(400, "invalid_region", "请选择有效地区");
            return ApiSupport.Ok(row);
        });

        var admin = api.MapGroup("/admin/activity-series").RequireAdmin();
        admin.MapGet("/official-editor", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryOneAsync("""
                SELECT editor_id,region_code FROM activity_series WHERE slug='damu-weekend'
                """, cancellationToken: ct)));
        admin.MapGet("/proposals", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync("""
                SELECT p.id,p.user_id,p.kind,r.name_zh_cn AS region_name,p.body,p.created_at
                FROM activity_series_proposal p JOIN administrative_region r ON r.code=p.region_code
                ORDER BY p.created_at DESC LIMIT 100
                """, cancellationToken: ct)));
        admin.MapPut("/official-editor", async (OfficialEditor input, Db db, CancellationToken ct) =>
        {
            var count = await db.ExecuteAsync("""
                UPDATE activity_series SET editor_id=@userId,region_code=@regionCode
                WHERE slug='damu-weekend'
                  AND (@userId IS NULL OR EXISTS (SELECT 1 FROM app_user WHERE id=@userId AND status='active' AND deleted_at IS NULL))
                  AND (@regionCode IS NULL OR EXISTS (SELECT 1 FROM administrative_region WHERE code=@regionCode AND is_active))
                """, new { input.UserId, input.RegionCode }, ct);
            if (count == 0) throw new ApiException(400, "invalid_series_editor", "请检查运营账号或地区");
            return ApiSupport.Ok(input);
        });

        api.MapGet("/events/{id:guid}/story", async (Guid id, Db db, CancellationToken ct) =>
            ApiSupport.Ok(await ReadStory(db, id, ct)));

        api.MapPut("/events/{id:guid}/recap", async (
            Guid id, RecapInput input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var body = input.Body?.Trim();
            var photos = input.PhotoIds ?? [];
            if (body is null or { Length: < 2 or > 2000 })
                throw new ApiException(400, "invalid_recap", "请填写 2 至 2000 字的活动回顾");
            if (photos.Length > 3 || photos.Distinct().Count() != photos.Length ||
                (photos.Length > 0 && !input.PhotosApproved))
                throw new ApiException(400, "invalid_recap_photos", "最多上传三张照片，并确认已获得公开使用许可");
            var changed = await db.ExecuteAsync($"""
                INSERT INTO activity_recap (event_id,body,show_cover,photo_ids)
                SELECT e.id,@body,@showCover,@photos FROM event e JOIN app_user host ON host.id=e.organizer_user_id
                WHERE e.id=@id AND e.organizer_user_id=@viewer AND {PublicEvent} AND ({Ended})
                  AND (SELECT count(*) FROM media_asset ma WHERE ma.id=ANY(@photos)
                    AND ma.owner_user_id=@viewer AND ma.status='ready' AND ma.deleted_at IS NULL
                    AND ma.storage_key LIKE 'events/%' AND ma.mime_type='image/jpeg'
                    AND NOT EXISTS (SELECT 1 FROM event covered WHERE covered.cover_media_id=ma.id))=cardinality(@photos)
                ON CONFLICT (event_id) DO UPDATE SET body=EXCLUDED.body,show_cover=EXCLUDED.show_cover,
                    photo_ids=EXCLUDED.photo_ids,updated_at=now()
                """, new { id, viewer, body, input.ShowCover, photos }, ct);
            if (changed == 0) throw new ApiException(403, "recap_unavailable", "仅组织者可以回顾已结束的公开活动");
            return ApiSupport.Ok(new { id });
        });

        api.MapGet("/events/{id:guid}/share-card", async (Guid id, Db db, CancellationToken ct) =>
        {
            var story = await ReadStory(db, id, ct);
            var title = WebUtility.HtmlEncode((string)story["title"]!);
            var region = string.Join(" · ", new[] { story["city_name"], story["district_name"] }.OfType<string>());
            var time = story["starts_at"] is DateTime starts
                ? starts.AddHours(9).ToString("yyyy-MM-dd HH:mm", System.Globalization.CultureInfo.InvariantCulture) + " KST"
                : "";
            var cover = story["cover_url"] as string ?? story["category_cover_url"] as string;
            var category = story["cover_category_code"] as string;
            var fallback = category is "culture" or "food" or "outdoors" or "social" or "sports" or "study" ? category : "other";
            var image = cover is not null ? "https://api.damumu.com" + cover : $"https://app.damumu.com/assets/covers/{fallback}.webp";
            var url = $"https://app.damumu.com/activities/{id}";
            var summary = WebUtility.HtmlEncode(string.Join(" · ", new[] { region, time }.Where(value => !string.IsNullOrWhiteSpace(value))));
            return Results.Content($"""
                <!doctype html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>{title} · 搭慕</title><link rel="canonical" href="{url}"><meta property="og:type" content="website">
                <meta property="og:title" content="{title}"><meta property="og:description" content="{summary}">
                <meta property="og:image" content="{WebUtility.HtmlEncode(image)}"><meta property="og:url" content="{url}/share">
                <meta http-equiv="refresh" content="0;url={url}"></head>
                <body><main><h1>{title}</h1><p>{summary}</p><a href="{url}">查看搭慕活动</a></main></body></html>
                """, "text/html; charset=utf-8");
        });
    }

    private static async Task<Dictionary<string, object?>> ReadStory(Db db, Guid id, CancellationToken ct)
    {
        var story = await db.QueryOneAsync($"""
            SELECT e.id,e.title,e.organizer_user_id,city.name_zh_cn AS city_name,district.name_zh_cn AS district_name,
                   (SELECT min(starts_at) FROM event_schedule WHERE event_id=e.id AND status='scheduled') AS starts_at,
                   s.id AS series_id,s.slug AS series_slug,s.title AS series_title,
                   recap.body AS recap,COALESCE(recap.show_cover,false) AS recap_show_cover,
                   (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',ma.id,'image_url',
                        '/uploads/' || COALESCE(ma.thumbnail_storage_key,ma.storage_key)) ORDER BY photo.ord),'[]')
                    FROM unnest(recap.photo_ids) WITH ORDINALITY photo(id,ord)
                    JOIN media_asset ma ON ma.id=photo.id AND ma.status='ready' AND ma.deleted_at IS NULL) AS recap_photos,
                   ({Ended}) AS ended,{ActivityQueries.CoverThumbnail},{ActivityQueries.CoverCategoryCodes},
                   (SELECT upcoming.id FROM activity_series_event se2 JOIN event upcoming ON upcoming.id=se2.event_id
                    JOIN app_user upcoming_host ON upcoming_host.id=upcoming.organizer_user_id
                    JOIN event_schedule es ON es.event_id=upcoming.id AND es.status='scheduled' AND es.starts_at>now()
                    WHERE se2.series_id=s.id AND upcoming.id<>e.id AND upcoming.deleted_at IS NULL
                      AND upcoming.visibility='public' AND upcoming.status IN ('published','full')
                      AND upcoming_host.status='active' AND upcoming_host.deleted_at IS NULL
                    ORDER BY es.starts_at,upcoming.id LIMIT 1) AS next_event_id
            FROM event e JOIN app_user host ON host.id=e.organizer_user_id JOIN category c ON c.id=e.category_id
            {ActivityQueries.CoverCategoryJoins}
            {ActivityQueries.CoverMediaJoin}
            LEFT JOIN administrative_region city ON city.code=e.city_code
            LEFT JOIN administrative_region district ON district.code=e.district_code
            LEFT JOIN activity_series_event se ON se.event_id=e.id
            LEFT JOIN activity_series s ON s.id=se.series_id
            LEFT JOIN activity_recap recap ON recap.event_id=e.id AND ({Ended})
            WHERE e.id=@id AND {PublicEvent}
            """, new { id }, ct) ?? throw new ApiException(404, "event_not_found", "公开活动不存在");
        story["recap_photos"] = JsonSerializer.Deserialize<List<Dictionary<string, string>>>(
            (string)story["recap_photos"]!) ?? [];
        return story;
    }

    public sealed record SeriesInput(string? Title, string? Description, string? RegionCode);
    public sealed record SeriesMembership(bool Subscribed, string? InterestSlot);
    public sealed record RecapInput(string? Body, bool ShowCover, Guid[]? PhotoIds = null, bool PhotosApproved = false);
    public sealed record SeriesProposal(string? Kind, string? RegionCode, string? Body);
    public sealed record OfficialEditor(Guid? UserId, string? RegionCode);
}

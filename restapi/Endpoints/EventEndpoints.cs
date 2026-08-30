using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class EventEndpoints
{
    public static RouteGroupBuilder MapEventEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/events", async (
            Db db,
            string? city,
            string? district,
            Guid? categoryId,
            string? q,
            DateTime? from,
            DateTime? to,
            double? latitude,
            double? longitude,
            int? radiusMeters,
            int? limit,
            int? offset,
            CancellationToken ct) =>
        {
            var take = Math.Clamp(limit ?? 20, 1, 100);
            var skip = Math.Max(offset ?? 0, 0);
            var hasGeo = latitude.HasValue && longitude.HasValue;
            var radius = Math.Clamp(radiusMeters ?? 20000, 500, 100000);
            var rows = await db.QueryAsync(
                """
                SELECT e.id, e.title, e.description, e.status, e.visibility, e.approval_mode,
                       e.min_participants, e.capacity, e.approved_count, e.waitlist_count,
                       e.price_min, e.price_max, e.price_amount,
                       e.price_currency, e.city_code, e.district_code, e.language_codes,
                       e.cover_media_id, e.published_at,
                       c.id AS category_id, c.name_zh_cn AS category_name, c.icon AS category_icon,
                       city_region.name_zh_cn AS city_name,
                       district_region.name_zh_cn AS district_name,
                       NULL::text AS place_name, NULL::text AS address_public,
                       s.starts_at, s.ends_at,
                       u.id AS organizer_user_id, up.nickname AS organizer_name,
                       COALESCE(ts.score, 0) AS organizer_score,
                       CASE WHEN @hasGeo AND p.public_geo IS NOT NULL
                            THEN ST_Distance(p.public_geo, ST_Point(@longitude, @latitude, 4326)::geography)
                            ELSE NULL END AS distance_meters
                FROM event e
                JOIN category c ON c.id=e.category_id
                JOIN app_user u ON u.id=e.organizer_user_id
                LEFT JOIN user_profile up ON up.user_id=u.id
                LEFT JOIN trust_snapshot ts ON ts.user_id=u.id
                LEFT JOIN place p ON p.id=e.place_id
                LEFT JOIN administrative_region city_region ON city_region.code=e.city_code
                LEFT JOIN administrative_region district_region ON district_region.code=e.district_code
                LEFT JOIN LATERAL (
                    SELECT starts_at, ends_at
                    FROM event_schedule
                    WHERE event_id=e.id AND status='scheduled'
                    ORDER BY starts_at LIMIT 1
                ) s ON true
                WHERE e.deleted_at IS NULL
                  AND e.visibility='public'
                  AND e.status IN ('published', 'full')
                  AND (@city IS NULL OR e.city_code=@city)
                  AND (@district IS NULL OR e.district_code=@district)
                  AND (@categoryId IS NULL OR e.category_id=@categoryId)
                  AND (@q IS NULL OR e.title ILIKE '%' || @q || '%' OR e.description ILIKE '%' || @q || '%')
                  AND (@from IS NULL OR s.starts_at >= @from)
                  AND (@to IS NULL OR s.starts_at <= @to)
                  AND (NOT @hasGeo OR p.public_geo IS NULL OR ST_DWithin(
                        p.public_geo, ST_Point(@longitude, @latitude, 4326)::geography, @radius))
                ORDER BY
                    CASE WHEN @hasGeo AND p.public_geo IS NOT NULL
                         THEN ST_Distance(p.public_geo, ST_Point(@longitude, @latitude, 4326)::geography)
                         ELSE NULL END NULLS LAST,
                    s.starts_at NULLS LAST
                LIMIT @limit OFFSET @offset
                """,
                new
                {
                    city,
                    district,
                    categoryId,
                    q,
                    from,
                    to,
                    hasGeo,
                    latitude = latitude ?? 0,
                    longitude = longitude ?? 0,
                    radius,
                    limit = take,
                    offset = skip
                }, ct);
            return ApiSupport.Ok(rows, new { limit = take, offset = skip, count = rows.Count });
        });

        api.MapGet("/events/{id:guid}", async (
            Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewerId = ApiSupport.GetOptionalUserId(context);
            var item = await db.QueryOneAsync(
                """
                SELECT e.*, c.name_zh_cn AS category_name, c.icon AS category_icon,
                       CASE WHEN e.organizer_user_id=@viewerId OR EXISTS (
                           SELECT 1 FROM event_member viewer_member
                           WHERE viewer_member.event_id=e.id AND viewer_member.user_id=@viewerId
                             AND viewer_member.status IN ('approved','attended')
                       ) THEN p.name END AS place_name,
                       CASE WHEN e.organizer_user_id=@viewerId OR EXISTS (
                           SELECT 1 FROM event_member viewer_member
                           WHERE viewer_member.event_id=e.id AND viewer_member.user_id=@viewerId
                             AND viewer_member.status IN ('approved','attended')
                       ) THEN p.address_public END AS address_public,
                       CASE WHEN e.organizer_user_id=@viewerId OR EXISTS (
                           SELECT 1 FROM event_member viewer_member
                           WHERE viewer_member.event_id=e.id AND viewer_member.user_id=@viewerId
                             AND viewer_member.status IN ('approved','attended')
                       ) THEN ST_Y(p.public_geo::geometry) END AS public_latitude,
                       CASE WHEN e.organizer_user_id=@viewerId OR EXISTS (
                           SELECT 1 FROM event_member viewer_member
                           WHERE viewer_member.event_id=e.id AND viewer_member.user_id=@viewerId
                             AND viewer_member.status IN ('approved','attended')
                       ) THEN ST_X(p.public_geo::geometry) END AS public_longitude,
                       up.nickname AS organizer_name, up.avatar_url AS organizer_avatar,
                       COALESCE(ts.score, 0) AS organizer_score,
                       COALESCE(ts.review_count, 0) AS organizer_review_count
                FROM event e
                JOIN category c ON c.id=e.category_id
                LEFT JOIN place p ON p.id=e.place_id
                LEFT JOIN user_profile up ON up.user_id=e.organizer_user_id
                LEFT JOIN trust_snapshot ts ON ts.user_id=e.organizer_user_id
                WHERE e.id=@id AND e.deleted_at IS NULL
                """, new { id, viewerId }, ct);
            if (item is null) throw new ApiException(404, "event_not_found", "活动不存在");

            var schedules = await db.QueryAsync(
                """
                SELECT id, starts_at, ends_at, check_in_opens_at, check_in_closes_at, timezone, status
                FROM event_schedule WHERE event_id=@id ORDER BY starts_at
                """, new { id }, ct);
            var tags = await db.QueryAsync(
                """
                SELECT i.id, i.code, i.name_zh_cn, i.icon
                FROM event_tag et JOIN interest i ON i.id=et.interest_id
                WHERE et.event_id=@id ORDER BY i.sort_order
                """, new { id }, ct);
            var members = await db.QueryAsync(
                """
                SELECT em.user_id, em.member_role, em.status, up.nickname, up.avatar_url
                FROM event_member em
                LEFT JOIN user_profile up ON up.user_id=em.user_id
                WHERE em.event_id=@id AND em.status IN ('approved', 'attended')
                ORDER BY em.joined_at
                LIMIT 12
                """, new { id }, ct);
            return ApiSupport.Ok(new { item, schedules, tags, members });
        });

        api.MapPost("/events", async (
            HttpContext context, CreateEventRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            if (request.EndsAt <= request.StartsAt)
                throw new ApiException(400, "invalid_schedule", "结束时间必须晚于开始时间");
            if (request.MinParticipants < 2 || request.Capacity < request.MinParticipants)
                throw new ApiException(400, "capacity_invalid", "人数范围无效");
            if (request.PriceMin < 0 || request.PriceMax < request.PriceMin)
                throw new ApiException(400, "price_range_invalid", "人均费用范围无效");
            var categorySelectable = await db.ScalarAsync<int>(
                "SELECT count(*) FROM category WHERE id=@categoryId AND level=2 AND is_active",
                new { request.CategoryId }, ct);
            if (categorySelectable == 0)
                throw new ApiException(400, "category_not_selectable", "请选择有效的细分类");
            var regionValid = await db.ScalarAsync<int>(
                """
                SELECT count(*) FROM administrative_region district
                JOIN administrative_region city ON city.code=district.parent_code
                WHERE city.code=@cityCode AND city.level=1 AND city.is_active
                  AND district.code=@districtCode AND district.level=2 AND district.is_active
                """, new { request.CityCode, request.DistrictCode }, ct);
            if (regionValid == 0)
                throw new ApiException(400, "region_invalid", "请选择有效的城市和地区");

            var eventId = Guid.NewGuid();
            Guid? placeId = null;
            if (request.Place is not null)
            {
                placeId = Guid.NewGuid();
                await db.ExecuteAsync(
                    """
                    INSERT INTO place (
                        id, provider, provider_place_id, name, city_code, district_code,
                        address_public, public_geo,
                        created_by_user_id
                    )
                    VALUES (
                        @placeId, 'manual', @placeId::text, @name, @cityCode, @districtCode, @addressPublic,
                        CASE WHEN @longitude IS NULL OR @latitude IS NULL THEN NULL
                             ELSE ST_Point(@longitude, @latitude, 4326)::geography END, @userId
                    )
                    """, new
                    {
                        placeId,
                        request.Place.Name,
                        request.CityCode,
                        request.DistrictCode,
                        request.Place.AddressPublic,
                        request.Place.Longitude,
                        request.Place.Latitude,
                        userId
                    }, ct);
            }

            await db.ExecuteAsync(
                """
                WITH inserted_event AS (
                    INSERT INTO event (
                        id, organizer_user_id, category_id, place_id, title, description,
                        city_code, district_code, status, published_at, visibility, approval_mode,
                        min_participants, capacity, min_age, max_age,
                        price_min, price_max, price_amount, price_currency, language_codes,
                        announcement, organizer_note, review_status
                    )
                    VALUES (
                        @eventId, @userId, @categoryId, @placeId, @title, @description,
                        @cityCode, @districtCode, 'published', now(), @visibility, @approvalMode,
                        @minParticipants, @capacity, @minAge, @maxAge,
                        @priceMin, @priceMax, @priceMin, @priceCurrency, @languageCodes,
                        @announcement, @organizerNote, 'not_required'
                    )
                    RETURNING id
                ), inserted_schedule AS (
                    INSERT INTO event_schedule (event_id, starts_at, ends_at)
                    SELECT id, @startsAt, @endsAt FROM inserted_event
                )
                INSERT INTO event_member (event_id, user_id, member_role, status, joined_at)
                VALUES (@eventId, @userId, 'organizer', 'approved', now())
                """, new
                {
                    eventId,
                    userId,
                    request.CategoryId,
                    placeId,
                    title = request.Title.Trim(),
                    description = request.Description.Trim(),
                    request.CityCode,
                    request.DistrictCode,
                    visibility = request.Visibility ?? "public",
                    approvalMode = request.ApprovalMode ?? "manual",
                    request.MinParticipants,
                    request.Capacity,
                    minAge = request.MinAge ?? 18,
                    request.MaxAge,
                    request.PriceMin,
                    request.PriceMax,
                    priceCurrency = request.PriceCurrency ?? "KRW",
                    languageCodes = request.LanguageCodes ?? ["zh-CN"],
                    request.StartsAt,
                    request.EndsAt,
                    request.Announcement,
                    request.OrganizerNote
                }, ct);

            foreach (var interestId in request.InterestIds?.Distinct().Take(10) ?? [])
                await db.ExecuteAsync(
                    "INSERT INTO event_tag (event_id, interest_id) VALUES (@eventId, @interestId) ON CONFLICT DO NOTHING",
                    new { eventId, interestId }, ct);

            return ApiSupport.Created($"/api/v1/events/{eventId}", new
            {
                id = eventId,
                status = "published",
                reviewStatus = "not_required"
            });
        });

        api.MapPatch("/events/{id:guid}", async (
            Guid id, HttpContext context, UpdateEventRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var item = await db.QueryOneAsync(
                """
                UPDATE event
                SET title=COALESCE(@title, title),
                    description=COALESCE(@description, description),
                    category_id=COALESCE(@categoryId, category_id),
                    capacity=COALESCE(@capacity, capacity),
                    approval_mode=COALESCE(@approvalMode, approval_mode),
                    visibility=COALESCE(@visibility, visibility),
                    row_version=row_version
                WHERE id=@id AND organizer_user_id=@userId AND deleted_at IS NULL
                  AND row_version=@rowVersion
                RETURNING id, title, description, status, capacity, approval_mode,
                          visibility, row_version, updated_at
                """, new
                {
                    id,
                    userId,
                    request.Title,
                    request.Description,
                    request.CategoryId,
                    request.Capacity,
                    request.ApprovalMode,
                    request.Visibility,
                    request.RowVersion
                }, ct);
            if (item is null)
                throw new ApiException(409, "version_conflict", "活动不存在、无权限或已被其他人更新");
            return ApiSupport.Ok(item);
        });

        api.MapPost("/events/{id:guid}/publish", async (
            Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var item = await db.QueryOneAsync(
                """
                UPDATE event SET status='published', published_at=COALESCE(published_at, now())
                WHERE id=@id AND organizer_user_id=@userId AND status IN ('draft', 'pending_review')
                RETURNING id, status, published_at, row_version
                """, new { id, userId }, ct);
            if (item is null) throw new ApiException(409, "cannot_publish", "活动状态不允许发布");
            return ApiSupport.Ok(item);
        });

        api.MapPost("/events/{id:guid}/cancel", async (
            Guid id, HttpContext context, CancelEventRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var item = await db.QueryOneAsync(
                """
                UPDATE event
                SET status='cancelled', cancelled_at=now(), cancellation_reason=@reason
                WHERE id=@id AND organizer_user_id=@userId AND status NOT IN ('cancelled', 'completed')
                RETURNING id, status, cancelled_at
                """, new { id, userId, reason = request.Reason }, ct);
            if (item is null) throw new ApiException(409, "cannot_cancel", "活动不可取消");
            return ApiSupport.Ok(item);
        });

        api.MapPost("/events/{id:guid}/join", async (
            Guid id, HttpContext context, JoinEventRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            if (request.PartySize is < 1 or > 20)
                throw new ApiException(400, "party_size_invalid", "报名人数需要为 1–20 人");
            return ApiSupport.Ok(await db.JoinEventAsync(
                id, userId, request.PartySize, request.Note, request.ShareContact, ct));
        });

        api.MapPost("/events/{id:guid}/leave", async (
            Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var member = await db.QueryOneAsync(
                """
                UPDATE event_member
                SET status='withdrawn', left_at=now(), waitlist_position=NULL
                WHERE event_id=@id AND user_id=@userId
                  AND member_role='participant'
                  AND status IN ('applied', 'approved', 'waitlisted')
                RETURNING id, event_id, user_id, status, left_at
                """, new { id, userId }, ct);
            if (member is null) throw new ApiException(409, "cannot_leave", "当前没有可退出的报名");
            return ApiSupport.Ok(member);
        });

        api.MapGet("/events/{id:guid}/members", async (
            Guid id, HttpContext context, Db db, string? status, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var allowed = await db.ScalarAsync<long>(
                "SELECT count(*) FROM event WHERE id=@id AND organizer_user_id=@userId",
                new { id, userId }, ct);
            if (allowed == 0) throw new ApiException(403, "forbidden", "只有组织者可以查看成员管理");
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT em.id, em.user_id, em.member_role, em.status, em.waitlist_position,
                       em.party_size, em.application_note, em.share_contact,
                       em.rejection_reason, em.reviewed_at, em.joined_at, em.checked_in_at,
                       up.nickname, up.avatar_url, COALESCE(ts.score, 0) AS trust_score
                FROM event_member em
                LEFT JOIN user_profile up ON up.user_id=em.user_id
                LEFT JOIN trust_snapshot ts ON ts.user_id=em.user_id
                WHERE em.event_id=@id AND (@status IS NULL OR em.status=@status)
                ORDER BY em.created_at
                """, new { id, status }, ct));
        });

        api.MapPost("/events/{id:guid}/members/{memberUserId:guid}/approve", async (
            Guid id, Guid memberUserId, HttpContext context, Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.ReviewMemberAsync(
                id, memberUserId, ApiSupport.RequireUserId(context), true, null, ct)));

        api.MapPost("/events/{id:guid}/members/{memberUserId:guid}/reject", async (
            Guid id, Guid memberUserId, HttpContext context, RejectApplicationRequest request,
            Db db, CancellationToken ct) =>
        {
            var reason = request.Reason?.Trim();
            if (reason is null || reason.Length is < 2 or > 300)
                throw new ApiException(400, "rejection_reason_required", "拒绝理由需要为 2–300 字");
            return ApiSupport.Ok(await db.ReviewMemberAsync(
                id, memberUserId, ApiSupport.RequireUserId(context), false, reason, ct));
        });

        api.MapPost("/events/{id:guid}/check-in", async (
            Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var member = await db.QueryOneAsync(
                """
                UPDATE event_member
                SET status='attended', checked_in_at=now(), check_in_method='code'
                WHERE event_id=@id AND user_id=@userId AND status='approved'
                RETURNING id, event_id, user_id, status, checked_in_at
                """, new { id, userId }, ct);
            if (member is null) throw new ApiException(409, "cannot_check_in", "未获准参加或已签到");
            return ApiSupport.Ok(member);
        });

        return api;
    }
}

public sealed record PlaceRequest(
    string Name, string? AddressPublic, double? Latitude, double? Longitude);
public sealed record CreateEventRequest(
    Guid CategoryId,
    string Title,
    string Description,
    string CityCode,
    string? DistrictCode,
    DateTime StartsAt,
    DateTime EndsAt,
    short MinParticipants,
    short Capacity,
    string? ApprovalMode,
    string? Visibility,
    short? MinAge,
    short? MaxAge,
    decimal PriceMin,
    decimal PriceMax,
    string? PriceCurrency,
    string? Announcement,
    string? OrganizerNote,
    string[]? LanguageCodes,
    Guid[]? InterestIds,
    PlaceRequest? Place);
public sealed record UpdateEventRequest(
    string? Title,
    string? Description,
    Guid? CategoryId,
    short? Capacity,
    string? ApprovalMode,
    string? Visibility,
    long RowVersion);
public sealed record CancelEventRequest(string Reason);
public sealed record JoinEventRequest(short PartySize, string? Note, bool ShareContact);
public sealed record RejectApplicationRequest(string? Reason);

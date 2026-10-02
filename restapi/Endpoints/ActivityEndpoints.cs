using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class ActivityEndpoints
{
    public static RouteGroupBuilder MapActivityEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/activities", async (
            HttpContext context, Db db, string? city, string? district, string? region,
            Guid? categoryId, string? q, DateTime? from, DateTime? to,
            double? latitude, double? longitude, int? radiusMeters,
            int? limit, string? cursor, CancellationToken ct) =>
        {
            var take = Math.Clamp(limit ?? 20, 1, 100);
            var position = ActivityCursor.Decode(cursor);
            var hasGeo = latitude.HasValue && longitude.HasValue;
            if (hasGeo && (latitude is < -90 or > 90 || longitude is < -180 or > 180))
                throw new ApiException(400, "invalid_location", "定位坐标无效");
            var viewerUserId = ApiSupport.GetOptionalUserId(context);
            var fallbackRegion = region;
            if (position is null && fallbackRegion is null && viewerUserId.HasValue)
            {
                fallbackRegion = await db.ScalarAsync<string?>(
                    "SELECT COALESCE(district_code,city_code) FROM user_profile WHERE user_id=@viewerUserId",
                    new { viewerUserId }, ct);
            }
            var anchorAt = position?.AnchorAt ?? DateTime.UtcNow;
            var rows = await db.QueryAsync(ActivityQueries.List, new
            {
                city, district, categoryId, q, from, to, viewerUserId,
                hasGeo, latitude=latitude ?? 0, longitude=longitude ?? 0,
                requestedRegion=fallbackRegion, cursorOrigin=position?.OriginRegionCode,
                radius=Math.Clamp(radiusMeters ?? 1000000, 500, 1000000),
                anchorAt, limit=take+1, hasCursor=position is not null,
                cursorScore=position?.ScoreKey ?? 0,
                cursorRing=position?.RegionRing ?? 0,
                cursorStartsAt=position?.SortStartsAt ?? DateTime.UnixEpoch,
                cursorCreatedAt=position?.CreatedAt ?? DateTime.UnixEpoch,
                cursorActivityId=position?.ActivityId ?? Guid.Empty
            }, ct);
            var hasMore=rows.Count>take;
            if(hasMore) rows.RemoveAt(rows.Count-1);
            string? nextCursor=null;
            if(hasMore && rows.Count>0)
            {
                var last=rows[^1];
                nextCursor=ActivityCursor.Encode(new ActivityCursor(
                    anchorAt,
                    last["origin_region_code"]?.ToString(),
                    Convert.ToInt32(last["score_key"]),
                    Convert.ToInt32(last["region_ring"]),
                    ((DateTime)last["sort_starts_at"]!).ToUniversalTime(),
                    ((DateTime)last["created_at"]!).ToUniversalTime(),
                    (Guid)last["id"]!));
            }
            return ApiSupport.Ok(new ActivityPage(rows,nextCursor,hasMore));
        });
        return api;
    }
}

public sealed record ActivityPage(IReadOnlyList<Dictionary<string,object?>> Items,string? NextCursor,bool HasMore);

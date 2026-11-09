using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class ActivityEndpoints
{
    public static RouteGroupBuilder MapActivityEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/activities", async (
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
            string? cursor,
            CancellationToken ct) =>
        {
            var take = Math.Clamp(limit ?? 20, 1, 100);
            var position = ActivityCursor.Decode(cursor);
            var hasGeo = latitude.HasValue && longitude.HasValue;
            var radius = Math.Clamp(radiusMeters ?? 20000, 500, 100000);
            var rows = await db.QueryAsync(
                ActivityQueries.List,
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
                    beginnerFriendlyThreshold = FeedbackPolicy.BeginnerFriendlyVerificationThreshold,
                    limit = take + 1,
                    hasCursor = position is not null,
                    cursorCreatedAt = position?.CreatedAt ?? DateTime.UnixEpoch,
                    cursorActivityId = position?.ActivityId ?? Guid.Empty
                }, ct);
            var totalCount = rows.Count == 0 ? 0L : (long)rows[0]["total_count"]!;
            foreach (var row in rows) row.Remove("total_count");
            var hasMore = rows.Count > take;
            if (hasMore) rows.RemoveAt(rows.Count - 1);
            await ActivityLocalization.AttachAsync(db, rows, ct);
            var nextCursor = hasMore
                ? ActivityCursor.Encode((DateTime)rows[^1]["created_at"]!, (Guid)rows[^1]["id"]!)
                : null;
            return ApiSupport.Ok(new ActivityPage(rows, nextCursor, hasMore, totalCount));
        });

        return api;
    }
}

public sealed record ActivityPage(
    IReadOnlyList<Dictionary<string, object?>> Items, string? NextCursor, bool HasMore, long TotalCount);

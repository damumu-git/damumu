using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class CatalogEndpoints
{
    public static RouteGroupBuilder MapCatalogEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/categories", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, code, parent_id, level, name_zh_cn, name_en_us,
                       name_ko_kr, description_zh_cn, icon, icon_key, (SELECT ea.image_url FROM emoji_asset ea WHERE ea.is_active AND (ea.key=category.icon_key OR ea.emoji=replace(replace(category.icon,'️',''),'︎','')) ORDER BY (ea.key=category.icon_key) DESC NULLS LAST LIMIT 1) AS icon_url,
                       is_featured, requires_custom_label, color, sort_order, cover_image_url
                FROM category
                WHERE is_active
                ORDER BY level, parent_id NULLS FIRST, sort_order, name_zh_cn
                """, cancellationToken: ct)));

        api.MapGet("/interests", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, code, name_zh_cn, name_ko_kr, icon, (SELECT ea.image_url FROM emoji_asset ea WHERE ea.is_active AND ea.emoji=replace(replace(interest.icon,'️',''),'︎','')) AS icon_url, sort_order
                FROM interest
                WHERE is_active
                ORDER BY sort_order, name_zh_cn
                """, cancellationToken: ct)));

        api.MapGet("/regions", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT code, parent_code, level, name_zh_cn, name_ko_kr,
                       name_en_us, sort_order
                FROM administrative_region
                WHERE is_active
                ORDER BY level, parent_code NULLS FIRST, sort_order, code
                """, cancellationToken: ct)));

        api.MapPost("/regions/resolve", async (ResolveRegionRequest location, Db db, CancellationToken ct) =>
        {
            if (location.Latitude is not double latitude || location.Longitude is not double longitude ||
                !double.IsFinite(latitude) || !double.IsFinite(longitude) ||
                latitude is < -90 or > 90 || longitude is < -180 or > 180)
                throw new ApiException(400, "invalid_location", "定位坐标无效");

            // Only return the administrative names. Do not store or echo the point.
            return ApiSupport.Ok(await db.QueryAsync(
                """
                WITH RECURSIVE covering AS (
                    SELECT code, parent_code, level, name_zh_cn, name_ko_kr, name_en_us
                    FROM administrative_region
                    WHERE is_active AND ST_Covers(
                        boundary, ST_Point(@longitude, @latitude, 4326)::geography)
                ), hierarchy AS (
                    SELECT code, parent_code, level, name_zh_cn, name_ko_kr, name_en_us
                    FROM (
                        SELECT * FROM covering ORDER BY level DESC, code LIMIT 1
                    ) deepest
                    UNION ALL
                    SELECT parent.code, parent.parent_code, parent.level,
                           parent.name_zh_cn, parent.name_ko_kr, parent.name_en_us
                    FROM hierarchy child
                    JOIN administrative_region parent ON parent.code=child.parent_code
                    WHERE parent.is_active AND parent.level=child.level-1
                )
                SELECT code, parent_code, level, name_zh_cn, name_ko_kr, name_en_us
                FROM hierarchy ORDER BY level
                """, new { latitude, longitude }, ct));
        });

        api.MapGet("/config/public", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                "SELECT key, value, version FROM app_config WHERE is_public ORDER BY key",
                cancellationToken: ct)));

        return api;
    }
}

public sealed record ResolveRegionRequest(double? Latitude, double? Longitude);

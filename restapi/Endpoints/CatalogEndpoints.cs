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
                       name_ko_kr, description_zh_cn, icon, icon_key,
                       is_featured, requires_custom_label, color, sort_order
                FROM category
                WHERE is_active
                ORDER BY level, parent_id NULLS FIRST, sort_order, name_zh_cn
                """, cancellationToken: ct)));

        api.MapGet("/interests", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, code, name_zh_cn, name_ko_kr, icon, sort_order
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

        api.MapGet("/regions/resolve", async (
            Db db, double latitude, double longitude, CancellationToken ct) =>
        {
            if (latitude is < -90 or > 90 || longitude is < -180 or > 180)
                throw new ApiException(400, "invalid_location", "定位坐标无效");
            var region = await db.QueryOneAsync(
                """
                WITH point AS (SELECT ST_SetSRID(ST_Point(@longitude,@latitude),4326) geometry)
                SELECT r.code,r.parent_code,r.level,r.name_zh_cn,r.name_ko_kr,r.name_en_us,
                       parent.code AS city_code,parent.name_zh_cn AS city_name_zh_cn,
                       parent.name_ko_kr AS city_name_ko_kr,parent.name_en_us AS city_name_en_us
                FROM administrative_region r
                LEFT JOIN administrative_region parent ON parent.code=CASE WHEN r.level=3 THEN r.parent_code ELSE substring(r.code FROM 1 FOR 5) END
                CROSS JOIN point p
                WHERE r.is_active AND r.level>=2 AND r.boundary IS NOT NULL
                  AND (ST_Covers(r.boundary::geometry,p.geometry)
                       OR ST_DWithin(r.boundary,p.geometry::geography,30000))
                ORDER BY ST_Covers(r.boundary::geometry,p.geometry) DESC,
                         CASE WHEN ST_Covers(r.boundary::geometry,p.geometry) THEN 0 ELSE ST_Distance(r.boundary,p.geometry::geography) END,
                         r.level DESC
                LIMIT 1
                """, new { latitude, longitude }, ct);
            if (region is null) throw new ApiException(404, "region_not_found", "当前位置不在支持的韩国行政区范围内");
            return ApiSupport.Ok(region);
        });
        api.MapGet("/config/public", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                "SELECT key, value, version FROM app_config WHERE is_public ORDER BY key",
                cancellationToken: ct)));

        return api;
    }
}

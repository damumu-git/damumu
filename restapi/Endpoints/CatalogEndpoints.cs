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
                       is_featured, requires_custom_label, color, sort_order
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

        api.MapGet("/config/public", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                "SELECT key, value, version FROM app_config WHERE is_public ORDER BY key",
                cancellationToken: ct)));

        return api;
    }
}

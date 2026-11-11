using Muda.Api.Infrastructure;
using System.Text.RegularExpressions;

namespace Muda.Api.Endpoints;

public static partial class WebGuideEndpoints
{
    public static RouteGroupBuilder MapWebGuideEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/guides", async (Db db, bool? featured, string? region, Guid? categoryId, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync("""
                SELECT g.slug,g.title,g.summary,g.cover_category,g.updated_at
                FROM web_guide g
                LEFT JOIN administrative_region r ON r.code=g.region_code
                LEFT JOIN administrative_region parent ON parent.code=r.parent_code
                LEFT JOIN category c ON c.id=g.category_id
                WHERE g.published AND (NOT @featured OR g.featured)
                  AND (@region IS NULL OR r.code=@region OR r.parent_code=@region OR parent.parent_code=@region)
                  AND (@categoryId IS NULL OR c.id=@categoryId OR c.parent_id=@categoryId)
                ORDER BY g.featured DESC,g.updated_at DESC,g.slug LIMIT 100
                """, new { featured = featured ?? false, region, categoryId }, ct)));

        api.MapGet("/guides/{slug}", async (string slug, Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryOneAsync("""
                SELECT slug,title,summary,body,cover_category,source_url,updated_at
                FROM web_guide WHERE published AND slug=@slug
                """, new { slug }, ct) ?? throw new ApiException(404, "guide_not_found", "指南不存在或已撤下")));

        api.MapPut("/me/web-bio", async (BioUpdate update, HttpContext context, Db db, CancellationToken ct) =>
        {
            var id = ApiSupport.RequireUserId(context);
            var bio = update.Bio?.Trim() ?? "";
            if (bio.Length > 300) throw new ApiException(400, "bio_too_long", "公开简介最多 300 字");
            await db.ExecuteAsync("UPDATE user_profile SET web_public_bio=NULLIF(@bio,'') WHERE user_id=@id",
                new { id, bio }, ct);
            return ApiSupport.Ok(new { bio });
        });

        var admin = api.MapGroup("/admin/guides").RequireAdmin();
        admin.MapGet("", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync("""
                SELECT slug,title,summary,body,cover_category,source_url,region_code,category_id,published,featured,updated_at
                FROM web_guide ORDER BY updated_at DESC, slug
                """, cancellationToken: ct)));

        admin.MapPut("/{slug}", async (string slug, GuideUpdate update, Db db, CancellationToken ct) =>
        {
            var title = update.Title?.Trim();
            var summary = update.Summary?.Trim();
            var body = update.Body?.Trim();
            var source = string.IsNullOrWhiteSpace(update.SourceUrl) ? null : update.SourceUrl.Trim();
            if (slug.Length > 80 || !SlugPattern().IsMatch(slug) ||
                title is null or { Length: < 2 or > 120 } ||
                summary is null or { Length: < 2 or > 300 } ||
                body is null or { Length: < 2 or > 20000 } ||
                update.CoverCategory is not ("culture" or "food" or "other" or "outdoors" or "social" or "sports" or "study") ||
                (source is not null && (source.Length > 2048 ||
                    !Uri.TryCreate(source, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                    string.IsNullOrWhiteSpace(uri.Host) || uri.UserInfo.Length != 0)))
                throw new ApiException(400, "guide_invalid", "请检查指南标题、内容、分类和来源链接");

            if (update.RegionCode is not null && !await db.ScalarAsync<bool>(
                    "SELECT EXISTS(SELECT 1 FROM administrative_region WHERE code=@regionCode AND is_active)", new { update.RegionCode }, ct))
                throw new ApiException(400, "guide_region_invalid", "地区不存在");
            if (update.CategoryId is not null && !await db.ScalarAsync<bool>(
                    "SELECT EXISTS(SELECT 1 FROM category WHERE id=@categoryId AND is_active)", new { update.CategoryId }, ct))
                throw new ApiException(400, "guide_category_invalid", "分类不存在");
            await db.ExecuteAsync("""
                INSERT INTO web_guide (slug,title,summary,body,cover_category,source_url,region_code,category_id,published,featured)
                VALUES (@slug,@title,@summary,@body,@coverCategory,@source,@regionCode,@categoryId,@published,@featured)
                ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title,summary=EXCLUDED.summary,
                    body=EXCLUDED.body,cover_category=EXCLUDED.cover_category,source_url=EXCLUDED.source_url,
                    region_code=EXCLUDED.region_code,category_id=EXCLUDED.category_id,
                    published=EXCLUDED.published,featured=EXCLUDED.featured,updated_at=now()
                """, new { slug, title, summary, body, update.CoverCategory, source, update.RegionCode, update.CategoryId, update.Published, update.Featured }, ct);
            return ApiSupport.Ok(new { slug });
        });
        return api;
    }

    [GeneratedRegex("\\A[a-z0-9]+(?:-[a-z0-9]+)*\\z")]
    private static partial Regex SlugPattern();

    public sealed record BioUpdate(string? Bio);

    public sealed record GuideUpdate(string? Title, string? Summary, string? Body, string? CoverCategory,
        string? SourceUrl, bool Published, bool Featured, string? RegionCode = null, Guid? CategoryId = null);
}

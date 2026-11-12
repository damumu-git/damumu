using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class ContentFilterEndpoints
{
    public static void MapContentFilterEndpoints(this RouteGroupBuilder api)
    {
        var admin = api.MapGroup("/admin/content-filter").RequireAdmin();
        admin.MapGet("", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                "SELECT term, is_enabled FROM content_filter_term ORDER BY is_enabled DESC, term",
                cancellationToken: ct)));

        admin.MapPut("", async (ContentFilterTerm input, Db db, ContentFilter filter, CancellationToken ct) =>
        {
            var term = ContentFilter.Normalize(input.Term ?? "");
            if (term.Length is < 2 or > 40 || term.Any(char.IsControl))
                throw new ApiException(400, "invalid_filter_term", "词条需为 2 至 40 个字");
            var row = await db.QueryOneAsync("""
                INSERT INTO content_filter_term (term, is_enabled) VALUES (@term, @enabled)
                ON CONFLICT (term) DO UPDATE SET is_enabled=EXCLUDED.is_enabled, updated_at=now()
                RETURNING term, is_enabled
                """, new { term, enabled = input.IsEnabled }, ct);
            filter.Invalidate();
            return ApiSupport.Ok(row);
        });
    }

    public sealed record ContentFilterTerm(string? Term, bool IsEnabled);
}

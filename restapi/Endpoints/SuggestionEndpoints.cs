using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class SuggestionEndpoints
{
    public static void MapSuggestionEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/me/suggestions", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, body, created_at, reply, replied_at FROM user_suggestion
                WHERE user_id=@userId ORDER BY created_at DESC, id DESC LIMIT 100
                """, new { userId }, ct));
        });

        api.MapPost("/me/suggestions", async (
            HttpContext context, SuggestionText request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var body = ValidateText(request.Text);
            var item = await db.QueryOneAsync(
                """
                INSERT INTO user_suggestion(user_id,body)
                SELECT id,@body FROM app_user WHERE id=@userId AND status='active' AND deleted_at IS NULL
                RETURNING id,body,created_at,reply,replied_at
                """, new { userId, body }, ct);
            if (item is null) throw new ApiException(404, "account_unavailable", "账号不可用");
            return ApiSupport.Created($"/api/v1/me/suggestions", item);
        });

        var admin = api.MapGroup("/admin/suggestions").RequireAdmin();
        admin.MapGet("", async (bool? unanswered, int? limit, int? offset, Db db, CancellationToken ct) =>
        {
            var take = Math.Clamp(limit ?? 25, 1, 100);
            var skip = Math.Max(offset ?? 0, 0);
            var pending = unanswered == true;
            var rows = await db.QueryAsync(
                """
                SELECT s.id,s.user_id,p.nickname,s.body,s.created_at,s.reply,s.replied_at
                FROM user_suggestion s LEFT JOIN user_profile p ON p.user_id=s.user_id
                WHERE NOT @pending OR s.reply IS NULL
                ORDER BY s.created_at DESC, s.id DESC LIMIT @take OFFSET @skip
                """, new { pending, take, skip }, ct);
            var total = await db.ScalarAsync<long>(
                "SELECT count(*) FROM user_suggestion WHERE NOT @pending OR reply IS NULL", new { pending }, ct);
            return ApiSupport.Ok(rows, new { total, limit = take, offset = skip });
        });
        admin.MapPost("/{id:guid}/reply", async (
            Guid id, SuggestionText request, Db db, RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var reply = ValidateText(request.Text);
            var notification = await db.QueryOneAsync(
                """
                WITH answered AS (
                    UPDATE user_suggestion SET reply=@reply,replied_at=now()
                    WHERE id=@id AND reply IS NULL
                    RETURNING id,user_id
                ), audited AS (
                    INSERT INTO audit_log(actor_role,action,target_type,target_id)
                    SELECT 'admin','admin.suggestion.replied','suggestion',id FROM answered
                )
                INSERT INTO notification(user_id,notification_type,title,body,data)
                SELECT a.user_id,'suggestion_replied',
                       CASE split_part(u.locale,'-',1) WHEN 'ko' THEN '제안에 답변이 도착했어요'
                            WHEN 'en' THEN 'Your suggestion has a reply' ELSE '你的建议收到回复' END,
                       CASE split_part(u.locale,'-',1) WHEN 'ko' THEN '내 제안에서 답변을 확인하세요.'
                            WHEN 'en' THEN 'Open your suggestions to read the reply.' ELSE '请在「我的建议」查看回复。' END,
                       jsonb_build_object('suggestionId',a.id)
                FROM answered a JOIN app_user u ON u.id=a.user_id
                RETURNING id,user_id
                """, new { id, reply }, ct);
            if (notification is null)
                throw new ApiException(409, "suggestion_already_replied", "建议已回复或已不可用");
            await realtime.PublishAsync([(Guid)notification["user_id"]!], "notification.created",
                new { notificationId = notification["id"] }, ct);
            return ApiSupport.Ok(new { id });
        });
    }

    private static string ValidateText(string? input)
    {
        var text = input?.Trim();
        if (string.IsNullOrEmpty(text) || text.EnumerateRunes().Count() > 1000)
            throw new ApiException(400, "invalid_suggestion_text", "请输入 1–1000 字的内容");
        return text;
    }
}

public sealed record SuggestionText(string? Text);

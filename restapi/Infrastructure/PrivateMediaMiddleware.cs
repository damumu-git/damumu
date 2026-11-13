namespace Muda.Api.Infrastructure;

public sealed class PrivateMediaMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, Db db)
    {
        if (context.Request.Path.StartsWithSegments("/uploads/events", StringComparison.OrdinalIgnoreCase))
        {
            context.Response.Headers.CacheControl = "private,no-store";
            var storageKey = context.Request.Path.Value!["/uploads/".Length..];
            var allowed = await db.ScalarAsync<bool>(
                $"""
                SELECT EXISTS (
                    SELECT 1 FROM media_asset ma JOIN event e ON e.cover_media_id=ma.id
                    WHERE (ma.storage_key=@storageKey OR ma.thumbnail_storage_key=@storageKey)
                      AND ma.status='ready' AND ma.deleted_at IS NULL AND {ActivityQueries.PublicCoverEvent}
                    UNION ALL
                    SELECT 1 FROM media_asset ma JOIN activity_recap r ON ARRAY[ma.id] <@ r.photo_ids
                    JOIN event e ON e.id=r.event_id JOIN app_user host ON host.id=e.organizer_user_id
                    WHERE (ma.storage_key=@storageKey OR ma.thumbnail_storage_key=@storageKey)
                      AND ma.status='ready' AND ma.deleted_at IS NULL
                      AND e.deleted_at IS NULL AND e.visibility='public' AND e.status IN ('published','full','completed')
                      AND host.status='active' AND host.deleted_at IS NULL
                      AND EXISTS (SELECT 1 FROM event_schedule WHERE event_id=e.id AND status='scheduled')
                      AND NOT EXISTS (SELECT 1 FROM event_schedule WHERE event_id=e.id AND status='scheduled' AND ends_at>now())
                )
                """, new { storageKey }, context.RequestAborted);
            if (!allowed)
                throw new ApiException(404, "media_not_found", "图片不存在或无权访问");
        }
        else if (context.Request.Path.StartsWithSegments("/uploads/messages", StringComparison.OrdinalIgnoreCase))
        {
            // Never treat an unguessable filename as authorization.
            var userId = ApiSupport.RequireUserId(context);
            var storageKey = context.Request.Path.Value!["/uploads/".Length..];
            var allowed = await db.ScalarAsync<int>(
                """
                SELECT count(*) FROM media_asset ma
                WHERE (ma.storage_key=@storageKey OR ma.thumbnail_storage_key=@storageKey)
                  AND ma.status='ready' AND ma.deleted_at IS NULL
                  AND (
                    (ma.owner_user_id=@userId AND ma.created_at > now()-interval '1 day'
                     AND NOT EXISTS (SELECT 1 FROM message sent WHERE sent.media_asset_id=ma.id))
                    OR EXISTS (
                      SELECT 1 FROM message m
                      JOIN conversation_member cm ON cm.conversation_id=m.conversation_id
                      WHERE m.media_asset_id=ma.id AND m.deleted_at IS NULL AND m.recalled_at IS NULL
                        AND m.created_at > now()-interval '3 months'
                        AND cm.user_id=@userId AND cm.left_at IS NULL
                    )
                  )
                """, new { storageKey, userId }, context.RequestAborted);
            if (allowed == 0)
                throw new ApiException(404, "media_not_found", "图片不存在或无权访问");
            context.Response.Headers.CacheControl = "private,no-store";
        }
        await next(context);
    }
}

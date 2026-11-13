using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class FriendEndpoints
{
    public static void MapFriendEndpoints(this RouteGroupBuilder api)
    {
        var friends = api.MapGroup("/me/friends");
        friends.MapGet("", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            context.Response.Headers.CacheControl = "private, no-store";
            return ApiSupport.Ok(await db.QueryAsync("""
                SELECT u.id,p.nickname,COALESCE(a.image_url,p.avatar_url) AS avatar_url
                FROM friendship f JOIN app_user u ON u.id=CASE WHEN f.first_id=@viewer THEN f.second_id ELSE f.first_id END
                LEFT JOIN user_profile p ON p.user_id=u.id
                LEFT JOIN system_avatar a ON p.avatar_url='system:'||a.id::text
                WHERE (f.first_id=@viewer OR f.second_id=@viewer) AND direct_contact_visible(@viewer,u.id)
                ORDER BY p.nickname,u.id
                """, new { viewer }, ct));
        });
        friends.MapDelete("/{peer:guid}", async (
            Guid peer, HttpContext context, Db db, RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("SELECT remove_friend(@viewer,@peer)", new { viewer, peer }, ct);
            await realtime.PublishAsync([viewer, peer], "conversation.changed", new { }, ct);
            return Results.NoContent();
        });
        friends.MapGet("/preferences", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var allow = await db.ScalarAsync<bool>("""
                SELECT COALESCE((SELECT allow_friend_requests FROM direct_contact_preference WHERE user_id=@viewer),true)
                """, new { viewer }, ct);
            return ApiSupport.Ok(new { allow });
        });
        friends.MapPut("/preferences", async (FriendPreference input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("""
                INSERT INTO direct_contact_preference(user_id,allow_friend_requests) VALUES (@viewer,@allow)
                ON CONFLICT (user_id) DO UPDATE SET allow_friend_requests=EXCLUDED.allow_friend_requests
                """, new { viewer, input.Allow }, ct);
            return ApiSupport.Ok(input);
        });

        var requests = api.MapGroup("/friend-requests");
        requests.MapGet("", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            context.Response.Headers.CacheControl = "private, no-store";
            return ApiSupport.Ok(await db.QueryAsync("""
                SELECT r.id, r.recipient_id=@viewer AS incoming, u.id AS peer_id,
                       p.nickname AS peer_nickname,COALESCE(a.image_url,p.avatar_url) AS peer_avatar,
                       r.body,r.created_at,
                       CASE WHEN r.sender_id=@viewer AND r.status IN ('ignored','declined','closed')
                            THEN 'closed' ELSE r.status END AS status
                FROM friend_request r
                JOIN app_user u ON u.id=CASE WHEN r.recipient_id=@viewer THEN r.sender_id ELSE r.recipient_id END
                LEFT JOIN user_profile p ON p.user_id=u.id
                LEFT JOIN system_avatar a ON p.avatar_url='system:'||a.id::text
                WHERE (r.sender_id=@viewer OR r.recipient_id=@viewer) AND direct_contact_visible(r.sender_id,r.recipient_id)
                ORDER BY (r.status='pending') DESC,r.created_at DESC,r.id LIMIT 100
                """, new { viewer }, ct));
        });
        requests.MapPost("", async (
            FriendRequestInput input, HttpContext context, Db db, RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var peer = input.UserId;
            var note = input.Body?.Trim();
            if (peer == Guid.Empty || peer == viewer || note?.Length > 200)
                throw new ApiException(400, "invalid_friend_request", "请选择申请对象，说明最多 200 字");
            if (note?.Length == 0) note = null;
            var status = await db.ScalarAsync<string>("SELECT send_friend_request(@viewer,@peer,@note)",
                new { viewer, peer, note }, ct);
            if (status == "limited")
                throw new ApiException(429, "friend_request_limit", "24 小时内最多发送 10 条好友申请");
            if (status == "unavailable")
                throw new ApiException(409, "friend_request_unavailable", "当前无法发送好友申请");
            if (status is "created" or "accepted")
            {
                await realtime.PublishAsync([peer], "notification.created", new
                {
                    notificationType = status == "created" ? "friend_request" : "friend_accepted"
                }, ct);
            }
            if (status == "accepted")
                await realtime.PublishAsync([viewer, peer], "conversation.changed", new { }, ct);
            return ApiSupport.Ok(new { status = status == "created" ? "pending" : status });
        });
        requests.MapPost("/{id:guid}/respond", async (
            Guid id, FriendDecision input, HttpContext context, Db db, RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            if (input.Decision is not ("accepted" or "declined" or "ignored" or "withdrawn"))
                throw new ApiException(400, "invalid_friend_decision", "请选择有效的申请操作");
            var peer = await db.ScalarAsync<Guid>("SELECT respond_friend_request(@id,@viewer,@decision)",
                new { id, viewer, input.Decision }, ct);
            if (peer == Guid.Empty)
                throw new ApiException(409, "friend_request_unavailable", "申请已处理或当前无法操作");
            if (input.Decision == "accepted")
            {
                await realtime.PublishAsync([peer], "notification.created", new { notificationType = "friend_accepted" }, ct);
                await realtime.PublishAsync([viewer, peer], "conversation.changed", new { }, ct);
            }
            await realtime.PublishAsync(input.Decision == "withdrawn" ? [peer] : [viewer], "unread.changed", new { }, ct);
            return ApiSupport.Ok(new { status = input.Decision });
        });
    }

    public sealed record FriendRequestInput(Guid UserId, string? Body);
    public sealed record FriendPreference(bool Allow);
    public sealed record FriendDecision(string? Decision);
}

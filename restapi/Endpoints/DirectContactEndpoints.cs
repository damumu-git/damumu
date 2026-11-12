using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class DirectContactEndpoints
{
    private const string SharedAttendance = """
        FROM event_member sender
        JOIN event_member recipient ON recipient.event_id=sender.event_id
        JOIN event e ON e.id=sender.event_id
        WHERE sender.user_id=@viewer AND recipient.user_id=@peer
          AND sender.status='attended' AND recipient.status='attended'
          AND sender.left_at IS NULL AND recipient.left_at IS NULL
          AND e.deleted_at IS NULL AND e.status<>'cancelled'
          AND EXISTS (SELECT 1 FROM event_schedule s WHERE s.event_id=e.id)
          AND NOT EXISTS (SELECT 1 FROM event_schedule s WHERE s.event_id=e.id AND s.ends_at>now())
        """;

    public static void MapDirectContactEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/contact-requests/options", async (
            Guid userId, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var options = await db.QueryOneAsync($"""
                SELECT direct_chat_allowed(@viewer,@peer) AS can_chat,
                       EXISTS(SELECT 1 FROM web_follow WHERE user_id=@viewer AND target_id=@peer) AS following,
                       (SELECT e.id {SharedAttendance}
                        AND direct_contact_visible(@viewer,@peer)
                        AND COALESCE((SELECT allow_attended_requests FROM direct_contact_preference WHERE user_id=@peer),true)
                        AND NOT EXISTS (SELECT 1 FROM direct_contact_request r
                            WHERE r.sender_id=@viewer AND r.recipient_id=@peer AND r.kind='attended'
                              AND (r.event_id=e.id OR r.status='pending' OR r.responded_at>now()-interval '7 days'))
                        ORDER BY e.created_at DESC,e.id LIMIT 1) AS request_event_id
                """, new { viewer, peer = userId }, ct);
            return ApiSupport.Ok(options);
        });

        api.MapGet("/me/contact-preferences", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var allowed = await db.ScalarAsync<bool>(
                "SELECT COALESCE((SELECT allow_attended_requests FROM direct_contact_preference WHERE user_id=@viewer),true)",
                new { viewer }, ct);
            return ApiSupport.Ok(new { allowAttendedRequests = allowed });
        });
        api.MapPut("/me/contact-preferences", async (
            ContactPreferences input, HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("""
                INSERT INTO direct_contact_preference (user_id,allow_attended_requests) VALUES (@viewer,@allow)
                ON CONFLICT (user_id) DO UPDATE SET allow_attended_requests=EXCLUDED.allow_attended_requests
                """, new { viewer, allow = input.AllowAttendedRequests }, ct);
            return ApiSupport.Ok(input);
        });

        api.MapGet("/contact-requests", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync("""
                SELECT r.id,r.kind,r.status,r.body,r.conversation_id,r.created_at,
                       r.recipient_id=@viewer AS incoming, peer.id AS peer_id, p.nickname AS peer_nickname,
                       COALESCE(sa.image_url,p.avatar_url) AS peer_avatar, e.title AS event_title
                FROM direct_contact_request r
                JOIN app_user peer ON peer.id=CASE WHEN r.recipient_id=@viewer THEN r.sender_id ELSE r.recipient_id END
                LEFT JOIN user_profile p ON p.user_id=peer.id
                LEFT JOIN system_avatar sa ON p.avatar_url='system:'||sa.id::text
                LEFT JOIN event e ON e.id=r.event_id
                WHERE (r.sender_id=@viewer OR r.recipient_id=@viewer)
                  AND direct_contact_visible(r.sender_id,r.recipient_id)
                ORDER BY (r.recipient_id=@viewer AND r.status='pending') DESC,r.created_at DESC LIMIT 100
                """, new { viewer }, ct));
        });

        api.MapPost("/contact-requests", async (
            ContactRequestInput input, HttpContext context, Db db, RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            var body = input.Body?.Trim();
            if (input.Kind is not ("inquiry" or "attended") || body is null || body.Length is < 1 or > 500)
                throw new ApiException(400, "invalid_contact_request", "请输入 1 至 500 字的联系内容");
            var peer = input.Kind == "inquiry"
                ? await db.ScalarAsync<Guid>("""
                    SELECT e.organizer_user_id FROM event e
                    WHERE e.id=@eventId AND e.deleted_at IS NULL AND e.visibility='public'
                      AND e.status IN ('published','full')
                      AND EXISTS (SELECT 1 FROM event_schedule s
                                  WHERE s.event_id=e.id AND s.status='scheduled' AND s.ends_at>now())
                    """, new { input.EventId }, ct)
                : input.UserId.GetValueOrDefault();
            if (peer == Guid.Empty)
                throw new ApiException(403, "contact_unavailable", "当前无法发起联系");

            var row = await db.QueryOneAsync($"""
                WITH created AS (
                    INSERT INTO direct_contact_request (sender_id,recipient_id,event_id,kind,body)
                    SELECT @viewer,@peer,@eventId,@kind,@body
                    WHERE direct_contact_visible(@viewer,@peer)
                      AND (@kind='inquiry' OR (
                        COALESCE((SELECT allow_attended_requests FROM direct_contact_preference WHERE user_id=@peer),true)
                        AND EXISTS (SELECT 1 {SharedAttendance} AND e.id=@eventId)
                        AND NOT EXISTS (SELECT 1 FROM direct_contact_request
                            WHERE sender_id=@viewer AND recipient_id=@peer AND kind='attended'
                              AND responded_at>now()-interval '7 days')
                      ))
                    ON CONFLICT DO NOTHING RETURNING id,status,recipient_id
                ), alerted AS (
                    INSERT INTO notification (user_id,notification_type,title,body,data)
                    SELECT recipient_id,'contact_request',
                           CASE WHEN @kind='inquiry' THEN '收到活动咨询' ELSE '收到私聊请求' END,
                           '可在消息中的联系请求查看。',jsonb_build_object('requestId',id)
                    FROM created
                )
                SELECT id,status FROM created
                """, new { viewer, peer, input.EventId, input.Kind, body }, ct);
            if (row is null)
                throw new ApiException(409, "contact_unavailable", "当前无法发送，或已发送过联系请求");
            await realtime.PublishAsync([peer], "notification.created", new { notificationType = "contact_request" }, ct);
            return ApiSupport.Ok(row);
        });

        api.MapPost("/contact-requests/{id:guid}/respond", async (
            Guid id, ContactResponse input, HttpContext context, Db db, RealtimeConnectionManager realtime, CancellationToken ct) =>
        {
            var viewer = ApiSupport.RequireUserId(context);
            if (!await db.ScalarAsync<bool>("SELECT respond_direct_contact(@id,@viewer,@accept)",
                    new { id, viewer, input.Accept }, ct))
                throw new ApiException(409, "contact_unavailable", "此请求已处理或当前无法回复");
            var row = await db.QueryOneAsync("""
                SELECT status, conversation_id,sender_id FROM direct_contact_request WHERE id=@id AND recipient_id=@viewer
                """, new { id, viewer }, ct);
            await realtime.PublishAsync([viewer], "unread.changed", new { }, ct);
            if (input.Accept && row?["sender_id"] is Guid sender)
                await realtime.PublishAsync([sender], "notification.created", new { notificationType = "contact_accepted" }, ct);
            return ApiSupport.Ok(new { status = row?["status"], conversationId = row?["conversation_id"] });
        });
    }
}

public sealed record ContactRequestInput(string? Kind, Guid EventId, Guid? UserId, string? Body);
public sealed record ContactResponse(bool Accept);
public sealed record ContactPreferences(bool AllowAttendedRequests);

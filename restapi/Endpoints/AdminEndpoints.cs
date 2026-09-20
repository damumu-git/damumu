using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class AdminEndpoints
{
    public static RouteGroupBuilder MapAdminEndpoints(this RouteGroupBuilder api)
    {
        var admin = api.MapGroup("/admin").RequireAdmin();

        admin.MapGet("/dashboard", async (Db db, CancellationToken ct) =>
        {
            var metrics = await db.QueryOneAsync(
                """
                SELECT
                    (SELECT count(*) FROM app_user WHERE deleted_at IS NULL) AS total_users,
                    (SELECT count(*) FROM app_user WHERE created_at >= now()-interval '7 days') AS new_users_7d,
                    (SELECT count(*) FROM event WHERE deleted_at IS NULL) AS total_events,
                    (SELECT count(*) FROM event WHERE status IN ('published','full')) AS active_events,
                    (SELECT count(*) FROM report WHERE status IN ('submitted','triaged','investigating','appealed')) AS open_reports,
                    (SELECT count(*) FROM safety_alert WHERE status IN ('open','contacted')) AS open_safety_alerts,
                    (SELECT count(*) FROM event_member WHERE status='attended') AS total_checkins,
                    (SELECT count(*) FROM message WHERE created_at >= now()-interval '24 hours') AS messages_24h
                """, cancellationToken: ct);
            var trend = await db.QueryAsync(
                """
                WITH days AS (
                    SELECT generate_series(
                        current_date - interval '6 days',
                        current_date,
                        interval '1 day'
                    )::date AS day
                )
                SELECT d.day,
                       (SELECT count(*) FROM app_user u WHERE u.created_at::date=d.day) AS users,
                       (SELECT count(*) FROM event e WHERE e.created_at::date=d.day) AS events,
                       (SELECT count(*) FROM event_member em WHERE em.created_at::date=d.day) AS applications
                FROM days d ORDER BY d.day
                """, cancellationToken: ct);
            var recentEvents = await db.QueryAsync(
                """
                SELECT e.id, e.title, e.status, e.city_code, e.district_code,
                       e.approved_count, e.capacity, e.created_at,
                       up.nickname AS organizer_name, s.starts_at
                FROM event e
                LEFT JOIN user_profile up ON up.user_id=e.organizer_user_id
                LEFT JOIN LATERAL (
                    SELECT starts_at FROM event_schedule
                    WHERE event_id=e.id ORDER BY starts_at LIMIT 1
                ) s ON true
                WHERE e.deleted_at IS NULL
                ORDER BY e.created_at DESC LIMIT 6
                """, cancellationToken: ct);
            var priorityReports = await db.QueryAsync(
                """
                SELECT r.id, r.target_type, r.category_code, r.priority, r.status,
                       r.created_at, up.nickname AS reporter_name
                FROM report r
                LEFT JOIN user_profile up ON up.user_id=r.reporter_user_id
                WHERE r.status IN ('submitted','triaged','investigating','appealed')
                ORDER BY r.priority, r.created_at LIMIT 6
                """, cancellationToken: ct);
            return ApiSupport.Ok(new { metrics, trend, recentEvents, priorityReports });
        });

        admin.MapGet("/users", async (
            Db db, string? q, string? status, string? role, int? limit, int? offset, CancellationToken ct) =>
        {
            var take = Math.Clamp(limit ?? 30, 1, 100);
            var skip = Math.Max(offset ?? 0, 0);
            var rows = await db.QueryAsync(
                """
                SELECT u.id, u.status, u.role, u.locale, u.last_login_at, u.created_at,
                       p.nickname, p.avatar_url, p.city_code, p.district_code,
                       COALESCE(ts.score, 0) AS trust_score,
                       COALESCE(ts.attended_count, 0) AS attended_count,
                       COALESCE(ts.no_show_count, 0) AS no_show_count,
                       (SELECT count(*) FROM report r WHERE r.reported_user_id=u.id) AS report_count
                FROM app_user u
                LEFT JOIN user_profile p ON p.user_id=u.id
                LEFT JOIN trust_snapshot ts ON ts.user_id=u.id
                WHERE u.deleted_at IS NULL
                  AND (@q IS NULL OR p.nickname ILIKE '%'||@q||'%' OR u.id::text ILIKE @q||'%')
                  AND (@status IS NULL OR u.status=@status)
                  AND (@role IS NULL OR u.role=@role)
                ORDER BY u.created_at DESC
                LIMIT @limit OFFSET @offset
                """, new { q, status, role, limit = take, offset = skip }, ct);
            var total = await db.ScalarAsync<long>(
                """
                SELECT count(*)
                FROM app_user u LEFT JOIN user_profile p ON p.user_id=u.id
                WHERE u.deleted_at IS NULL
                  AND (@q IS NULL OR p.nickname ILIKE '%'||@q||'%' OR u.id::text ILIKE @q||'%')
                  AND (@status IS NULL OR u.status=@status)
                  AND (@role IS NULL OR u.role=@role)
                """, new { q, status, role }, ct);
            return ApiSupport.Ok(rows, new { total, limit = take, offset = skip });
        });

        admin.MapGet("/users/{id:guid}", async (Guid id, Db db, CancellationToken ct) =>
        {
            var user = await db.QueryOneAsync(
                """
                SELECT u.*, p.nickname, p.avatar_url, p.bio, p.city_code, p.district_code,
                       p.languages, p.gender, p.occupation, p.arrival_year,
                       ts.score AS trust_score, ts.review_count, ts.attended_count,
                       ts.no_show_count, ts.organized_count, ts.tag_counts
                FROM app_user u
                LEFT JOIN user_profile p ON p.user_id=u.id
                LEFT JOIN trust_snapshot ts ON ts.user_id=u.id
                WHERE u.id=@id
                """, new { id }, ct);
            if (user is null) throw new ApiException(404, "user_not_found", "用户不存在");
            var events = await db.QueryAsync(
                """
                SELECT e.id, e.title, e.status AS event_status, em.status AS member_status,
                       em.member_role, em.checked_in_at, em.created_at
                FROM event_member em JOIN event e ON e.id=em.event_id
                WHERE em.user_id=@id ORDER BY em.created_at DESC LIMIT 20
                """, new { id }, ct);
            var reports = await db.QueryAsync(
                """
                SELECT id, target_type, category_code, priority, status, created_at
                FROM report WHERE reported_user_id=@id ORDER BY created_at DESC LIMIT 20
                """, new { id }, ct);
            return ApiSupport.Ok(new { user, events, reports });
        });

        admin.MapPatch("/users/{id:guid}/status", async (
            Guid id, AdminUserStatusRequest request, Db db, CancellationToken ct) =>
        {
            if (request.Status is not ("active" or "suspended" or "banned"))
                throw new ApiException(400, "invalid_status", "不支持的用户状态");
            var user = await db.QueryOneAsync(
                """
                UPDATE app_user SET status=@status
                WHERE id=@id AND deleted_at IS NULL
                RETURNING id, status, role, row_version, updated_at
                """, new { id, request.Status }, ct);
            if (user is null) throw new ApiException(404, "user_not_found", "用户不存在");
            await WriteAudit(db, request.ActorUserId, "admin.user.status_changed", "user", id,
                new { request.Status, request.Reason }, ct);
            return ApiSupport.Ok(user);
        });

        admin.MapGet("/events", async (
            Db db, string? q, string? status, string? city, int? limit, int? offset, CancellationToken ct) =>
        {
            var take = Math.Clamp(limit ?? 30, 1, 100);
            var skip = Math.Max(offset ?? 0, 0);
            var rows = await db.QueryAsync(
                """
                SELECT e.id, e.title, e.status, e.visibility, e.city_code, e.district_code,
                       e.capacity, e.approved_count, e.waitlist_count, e.price_amount,
                       e.created_at, e.published_at, e.row_version,
                       COALESCE(e.custom_subcategory, c.name_zh_cn) AS category_name,
                       c.icon AS category_icon,
                       p.name AS place_name, up.nickname AS organizer_name,
                       s.starts_at, s.ends_at,
                       (SELECT count(*) FROM report r WHERE r.target_type='event' AND r.target_id=e.id) AS report_count
                FROM event e
                JOIN category c ON c.id=e.category_id
                LEFT JOIN place p ON p.id=e.place_id
                LEFT JOIN user_profile up ON up.user_id=e.organizer_user_id
                LEFT JOIN LATERAL (
                    SELECT starts_at, ends_at FROM event_schedule
                    WHERE event_id=e.id ORDER BY starts_at LIMIT 1
                ) s ON true
                WHERE e.deleted_at IS NULL
                  AND (@q IS NULL OR e.title ILIKE '%'||@q||'%')
                  AND (@status IS NULL OR e.status=@status)
                  AND (@city IS NULL OR e.city_code=@city)
                ORDER BY e.created_at DESC
                LIMIT @limit OFFSET @offset
                """, new { q, status, city, limit = take, offset = skip }, ct);
            var total = await db.ScalarAsync<long>(
                """
                SELECT count(*) FROM event e
                WHERE e.deleted_at IS NULL
                  AND (@q IS NULL OR e.title ILIKE '%'||@q||'%')
                  AND (@status IS NULL OR e.status=@status)
                  AND (@city IS NULL OR e.city_code=@city)
                """, new { q, status, city }, ct);
            return ApiSupport.Ok(rows, new { total, limit = take, offset = skip });
        });

        admin.MapPatch("/events/{id:guid}/moderation", async (
            Guid id, AdminEventModerationRequest request, Db db, CancellationToken ct) =>
        {
            if (request.Status is not ("published" or "hidden" or "cancelled"))
                throw new ApiException(400, "invalid_status", "不支持的活动处置状态");
            var item = await db.QueryOneAsync(
                """
                UPDATE event
                SET status=@status,
                    visibility=CASE WHEN @status='hidden' THEN 'unlisted' ELSE visibility END,
                    cancellation_reason=CASE WHEN @status='cancelled' THEN @reason ELSE cancellation_reason END,
                    cancelled_at=CASE WHEN @status='cancelled' THEN now() ELSE cancelled_at END
                WHERE id=@id AND deleted_at IS NULL
                RETURNING id, title, status, visibility, row_version, updated_at
                """, new { id, request.Status, request.Reason }, ct);
            if (item is null) throw new ApiException(404, "event_not_found", "活动不存在");
            if (request.ActorUserId.HasValue)
            {
                await db.ExecuteAsync(
                    """
                    INSERT INTO moderation_action (
                        moderator_user_id, target_type, target_id, action_type, reason_code, reason_note
                    )
                    VALUES (@actorUserId, 'event', @id, @actionType, @reasonCode, @reason)
                    """, new
                    {
                        request.ActorUserId,
                        id,
                        actionType = request.Status == "published" ? "restore" : request.Status == "hidden" ? "hide" : "remove",
                        reasonCode = request.ReasonCode ?? "admin_decision",
                        request.Reason
                    }, ct);
            }
            await WriteAudit(db, request.ActorUserId, "admin.event.moderated", "event", id,
                new { request.Status, request.Reason }, ct);
            return ApiSupport.Ok(item);
        });

        admin.MapGet("/reports", async (
            Db db, string? status, short? priority, string? targetType,
            int? limit, int? offset, CancellationToken ct) =>
        {
            var take = Math.Clamp(limit ?? 30, 1, 100);
            var skip = Math.Max(offset ?? 0, 0);
            var rows = await db.QueryAsync(
                """
                SELECT r.id, r.target_type, r.target_id, r.category_code, r.description,
                       r.priority, r.status, r.assigned_to_user_id, r.resolution_code,
                       r.resolved_at, r.created_at, r.row_version,
                       reporter.nickname AS reporter_name,
                       reported.nickname AS reported_user_name,
                       CASE WHEN r.target_type='event' THEN e.title
                            WHEN r.target_type='message' THEN left(m.body, 100)
                            ELSE NULL END AS target_summary,
                       (SELECT count(*) FROM report_evidence re WHERE re.report_id=r.id) AS evidence_count
                FROM report r
                LEFT JOIN user_profile reporter ON reporter.user_id=r.reporter_user_id
                LEFT JOIN user_profile reported ON reported.user_id=r.reported_user_id
                LEFT JOIN event e ON r.target_type='event' AND e.id=r.target_id
                LEFT JOIN message m ON r.target_type='message' AND m.id=r.target_id
                WHERE (@status IS NULL OR r.status=@status)
                  AND (@priority IS NULL OR r.priority=@priority)
                  AND (@targetType IS NULL OR r.target_type=@targetType)
                ORDER BY r.priority, r.created_at
                LIMIT @limit OFFSET @offset
                """, new { status, priority, targetType, limit = take, offset = skip }, ct);
            var total = await db.ScalarAsync<long>(
                """
                SELECT count(*) FROM report
                WHERE (@status IS NULL OR status=@status)
                  AND (@priority IS NULL OR priority=@priority)
                  AND (@targetType IS NULL OR target_type=@targetType)
                """, new { status, priority, targetType }, ct);
            return ApiSupport.Ok(rows, new { total, limit = take, offset = skip });
        });

        admin.MapGet("/reports/{id:guid}", async (Guid id, Db db, CancellationToken ct) =>
        {
            var report = await db.QueryOneAsync("SELECT * FROM report WHERE id=@id", new { id }, ct);
            if (report is null) throw new ApiException(404, "report_not_found", "举报不存在");
            var evidence = await db.QueryAsync(
                """
                SELECT re.id, re.evidence_type, re.snapshot, re.retention_until, re.created_at,
                       ma.storage_key, ma.mime_type, ma.status AS media_status
                FROM report_evidence re
                LEFT JOIN media_asset ma ON ma.id=re.media_asset_id
                WHERE re.report_id=@id ORDER BY re.created_at
                """, new { id }, ct);
            var actions = await db.QueryAsync(
                """
                SELECT ma.*, up.nickname AS moderator_name
                FROM moderation_action ma
                LEFT JOIN user_profile up ON up.user_id=ma.moderator_user_id
                WHERE ma.report_id=@id ORDER BY ma.created_at
                """, new { id }, ct);
            return ApiSupport.Ok(new { report, evidence, actions });
        });

        admin.MapPatch("/reports/{id:guid}", async (
            Guid id, AdminReportActionRequest request, Db db, CancellationToken ct) =>
        {
            if (request.Status is not ("triaged" or "investigating" or "resolved" or "dismissed"))
                throw new ApiException(400, "invalid_status", "不支持的举报状态");
            var report = await db.QueryOneAsync(
                """
                UPDATE report
                SET status=@status,
                    assigned_to_user_id=COALESCE(@actorUserId, assigned_to_user_id),
                    resolution_code=CASE WHEN @status IN ('resolved','dismissed') THEN @resolutionCode ELSE resolution_code END,
                    resolved_at=CASE WHEN @status IN ('resolved','dismissed') THEN now() ELSE NULL END
                WHERE id=@id AND row_version=@rowVersion
                RETURNING id, status, priority, assigned_to_user_id, resolution_code,
                          resolved_at, row_version, updated_at
                """, new
                {
                    id,
                    request.Status,
                    request.ActorUserId,
                    request.ResolutionCode,
                    request.RowVersion
                }, ct);
            if (report is null)
                throw new ApiException(409, "version_conflict", "举报不存在或已被其他管理员更新");
            await WriteAudit(db, request.ActorUserId, "admin.report.updated", "report", id,
                new { request.Status, request.ResolutionCode, request.Note }, ct);
            return ApiSupport.Ok(report);
        });

        admin.MapGet("/safety-alerts", async (
            Db db, string? status, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT sa.id, sa.alert_type, sa.status, sa.contact_notified_at,
                       sa.resolved_at, sa.created_at, ss.user_id, ss.event_id,
                       ss.next_due_at, up.nickname, e.title AS event_title
                FROM safety_alert sa
                JOIN safety_session ss ON ss.id=sa.safety_session_id
                LEFT JOIN user_profile up ON up.user_id=ss.user_id
                LEFT JOIN event e ON e.id=ss.event_id
                WHERE (@status IS NULL OR sa.status=@status)
                ORDER BY CASE sa.status WHEN 'open' THEN 0 WHEN 'contacted' THEN 1 ELSE 2 END,
                         sa.created_at
                """, new { status }, ct)));

        admin.MapPatch("/safety-alerts/{id:guid}", async (
            Guid id, AdminSafetyAlertRequest request, Db db, CancellationToken ct) =>
        {
            if (request.Status is not ("contacted" or "acknowledged" or "resolved" or "false_alarm"))
                throw new ApiException(400, "invalid_status", "不支持的警报状态");
            var alert = await db.QueryOneAsync(
                """
                UPDATE safety_alert
                SET status=@status,
                    contact_notified_at=CASE WHEN @status='contacted' THEN now() ELSE contact_notified_at END,
                    resolved_at=CASE WHEN @status IN ('resolved','false_alarm') THEN now() ELSE resolved_at END,
                    resolution_note=COALESCE(@note, resolution_note)
                WHERE id=@id
                RETURNING id, status, contact_notified_at, resolved_at, resolution_note, updated_at
                """, new { id, request.Status, request.Note }, ct);
            if (alert is null) throw new ApiException(404, "alert_not_found", "安全警报不存在");
            await WriteAudit(db, request.ActorUserId, "admin.safety_alert.updated", "safety_alert", id,
                new { request.Status, request.Note }, ct);
            return ApiSupport.Ok(alert);
        });

        admin.MapGet("/system-avatars", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, code, name_zh_cn, name_en_us, name_ko_kr,
                       image_url, mime_type, byte_size, width, height,
                       sort_order, is_active, created_at, updated_at
                FROM system_avatar ORDER BY sort_order, created_at
                """, cancellationToken: ct)));

        admin.MapPost("/system-avatars", async (
            HttpContext context, Db db, IWebHostEnvironment environment, CancellationToken ct) =>
        {
            var form = await context.Request.ReadFormAsync(ct);
            var image = form.Files.GetFile("image")
                ?? throw new ApiException(400, "image_required", "请上传头像图片");
            AvatarImageValidator.Validate(image);
            var code = Required(form["code"].FirstOrDefault(), "请输入头像代码");
            var nameZhCn = Required(form["nameZhCn"].FirstOrDefault(), "请输入中文名称");
            var nameEnUs = Required(form["nameEnUs"].FirstOrDefault(), "请输入英文名称");
            var nameKoKr = Required(form["nameKoKr"].FirstOrDefault(), "请输入韩文名称");
            _ = int.TryParse(form["sortOrder"].FirstOrDefault(), out var sortOrder);

            var id = Guid.NewGuid();
            var directory = Path.Combine(environment.ContentRootPath, "uploads", "system-avatars");
            Directory.CreateDirectory(directory);
            var fileName = $"{id:N}.jpg";
            var fullPath = Path.Combine(directory, fileName);
            await using (var output = File.Create(fullPath))
                await image.CopyToAsync(output, ct);
            var imageUrl = $"/uploads/system-avatars/{fileName}";

            var item = await db.QueryOneAsync(
                """
                INSERT INTO system_avatar (
                    id, code, name_zh_cn, name_en_us, name_ko_kr,
                    image_url, mime_type, byte_size, width, height, sort_order
                )
                VALUES (
                    @id, @code, @nameZhCn, @nameEnUs, @nameKoKr,
                    @imageUrl, 'image/jpeg', @byteSize, 512, 512, @sortOrder
                )
                RETURNING *
                """, new
                {
                    id, code, nameZhCn, nameEnUs, nameKoKr, imageUrl,
                    byteSize = checked((int)image.Length), sortOrder
                }, ct);
            return ApiSupport.Created($"/api/v1/admin/system-avatars/{id}", item);
        }).DisableAntiforgery();

        admin.MapPatch("/system-avatars/{id:guid}", async (
            Guid id, AdminSystemAvatarRequest request, Db db, CancellationToken ct) =>
        {
            var item = await db.QueryOneAsync(
                """
                UPDATE system_avatar
                SET code=@code,
                    name_zh_cn=@nameZhCn,
                    name_en_us=@nameEnUs,
                    name_ko_kr=@nameKoKr,
                    sort_order=@sortOrder,
                    is_active=@isActive,
                    updated_at=now()
                WHERE id=@id
                RETURNING *
                """, new
                {
                    id, request.Code, request.NameZhCn, request.NameEnUs,
                    request.NameKoKr, request.SortOrder, request.IsActive
                }, ct);
            if (item is null) throw new ApiException(404, "avatar_not_found", "系统头像不存在");
            return ApiSupport.Ok(item);
        });

        admin.MapGet("/categories", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                """
                WITH RECURSIVE category_tree AS (
                    SELECT c.id, c.name_zh_cn::text AS full_path
                    FROM category c WHERE c.parent_id IS NULL
                    UNION ALL
                    SELECT child.id, tree.full_path || ' / ' || child.name_zh_cn
                    FROM category child JOIN category_tree tree ON tree.id=child.parent_id
                )
                SELECT c.*, parent.name_zh_cn AS parent_name, tree.full_path,
                       (SELECT count(*) FROM category child WHERE child.parent_id=c.id) AS child_count,
                       (SELECT count(*) FROM event e WHERE e.category_id=c.id AND e.deleted_at IS NULL) AS event_count
                FROM category c
                LEFT JOIN category parent ON parent.id=c.parent_id
                LEFT JOIN category_tree tree ON tree.id=c.id
                ORDER BY c.level, c.parent_id NULLS FIRST, c.sort_order, c.name_zh_cn
                """, cancellationToken: ct)));

        admin.MapPost("/categories", async (
            AdminCategoryRequest request, Db db, CancellationToken ct) =>
        {
            var item = await db.QueryOneAsync(
                """
                INSERT INTO category (
                    code, name_zh_cn, name_en_us, name_ko_kr,
                    description_zh_cn, description_en_us, description_ko_kr,
                    icon, icon_key, color, parent_id, sort_order, is_active, is_featured
                )
                VALUES (
                    @code, @nameZhCn, @nameEnUs, @nameKoKr,
                    @descriptionZhCn, @descriptionEnUs, @descriptionKoKr,
                    @icon, @iconKey, @color, @parentId, @sortOrder, @isActive, @isFeatured
                )
                RETURNING *
                """, new
                {
                    request.Code,
                    request.NameZhCn,
                    request.NameEnUs,
                    request.NameKoKr,
                    request.DescriptionZhCn,
                    request.DescriptionEnUs,
                    request.DescriptionKoKr,
                    request.Icon,
                    request.IconKey,
                    request.Color,
                    request.ParentId,
                    request.SortOrder,
                    request.IsActive,
                    request.IsFeatured
                }, ct);
            return ApiSupport.Created($"/api/v1/admin/categories/{item!["id"]}", item);
        });

        admin.MapPatch("/categories/{id:guid}", async (
            Guid id, AdminCategoryRequest request, Db db, CancellationToken ct) =>
        {
            var item = await db.QueryOneAsync(
                """
                UPDATE category
                SET code=@code, name_zh_cn=@nameZhCn, name_en_us=@nameEnUs,
                    name_ko_kr=@nameKoKr, description_zh_cn=@descriptionZhCn,
                    description_en_us=@descriptionEnUs, description_ko_kr=@descriptionKoKr,
                    icon=@icon, icon_key=@iconKey, color=@color, parent_id=@parentId,
                    sort_order=@sortOrder, is_active=@isActive, is_featured=@isFeatured
                WHERE id=@id RETURNING *
                """, new
                {
                    id,
                    request.Code,
                    request.NameZhCn,
                    request.NameEnUs,
                    request.NameKoKr,
                    request.DescriptionZhCn,
                    request.DescriptionEnUs,
                    request.DescriptionKoKr,
                    request.Icon,
                    request.IconKey,
                    request.Color,
                    request.ParentId,
                    request.SortOrder,
                    request.IsActive,
                    request.IsFeatured
                }, ct);
            if (item is null) throw new ApiException(404, "category_not_found", "分类不存在");
            return ApiSupport.Ok(item);
        });

        admin.MapDelete("/categories/{id:guid}", async (
            Guid id, Db db, CancellationToken ct) =>
        {
            var references = await db.ScalarAsync<long>(
                "SELECT count(*) FROM event WHERE category_id=@id AND deleted_at IS NULL",
                new { id }, ct);
            var children = await db.ScalarAsync<long>(
                "SELECT count(*) FROM category WHERE parent_id=@id",
                new { id }, ct);
            if (references > 0 || children > 0)
                throw new ApiException(409, "category_in_use", "分类已被活动或子分类使用，只能停用");
            var deleted = await db.ExecuteAsync("DELETE FROM category WHERE id=@id", new { id }, ct);
            if (deleted == 0) throw new ApiException(404, "category_not_found", "分类不存在");
            return Results.NoContent();
        });

        admin.MapGet("/regions", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT r.*, parent.name_zh_cn AS parent_name,
                       (SELECT count(*) FROM administrative_region child WHERE child.parent_code=r.code) AS child_count,
                       (SELECT count(*) FROM event e
                        WHERE (e.city_code=r.code OR e.district_code=r.code) AND e.deleted_at IS NULL) AS event_count
                FROM administrative_region r
                LEFT JOIN administrative_region parent ON parent.code=r.parent_code
                ORDER BY r.level, r.parent_code NULLS FIRST, r.sort_order, r.code
                """, cancellationToken: ct)));

        admin.MapPost("/regions", async (
            AdminRegionRequest request, Db db, CancellationToken ct) =>
        {
            await ValidateRegion(request, db, ct);
            var item = await db.QueryOneAsync(
                """
                INSERT INTO administrative_region
                    (code, parent_code, level, name_zh_cn, name_ko_kr, name_en_us, sort_order, is_active)
                VALUES (@code, @parentCode, @level, @nameZhCn, @nameKoKr, @nameEnUs, @sortOrder, @isActive)
                RETURNING *
                """, new {
                    code = request.Code.Trim(), request.ParentCode, request.Level,
                    nameZhCn = Required(request.NameZhCn, "请输入中文名称"),
                    nameKoKr = Required(request.NameKoKr, "请输入韩文名称"),
                    nameEnUs = Required(request.NameEnUs, "请输入英文名称"),
                    request.SortOrder, request.IsActive
                }, ct);
            return ApiSupport.Created($"/api/v1/admin/regions/{request.Code}", item);
        });

        admin.MapPatch("/regions/{code}", async (
            string code, AdminRegionRequest request, Db db, CancellationToken ct) =>
        {
            if (!string.Equals(code, request.Code, StringComparison.Ordinal))
                throw new ApiException(400, "region_code_immutable", "地区代码创建后不可修改");
            await ValidateRegion(request, db, ct);
            var item = await db.QueryOneAsync(
                """
                UPDATE administrative_region
                SET parent_code=@parentCode, level=@level, name_zh_cn=@nameZhCn,
                    name_ko_kr=@nameKoKr, name_en_us=@nameEnUs,
                    sort_order=@sortOrder, is_active=@isActive, updated_at=now()
                WHERE code=@code RETURNING *
                """, new {
                    code, request.ParentCode, request.Level,
                    nameZhCn = Required(request.NameZhCn, "请输入中文名称"),
                    nameKoKr = Required(request.NameKoKr, "请输入韩文名称"),
                    nameEnUs = Required(request.NameEnUs, "请输入英文名称"),
                    request.SortOrder, request.IsActive
                }, ct);
            if (item is null) throw new ApiException(404, "region_not_found", "地区不存在");
            return ApiSupport.Ok(item);
        });

        admin.MapDelete("/regions/{code}", async (
            string code, Db db, CancellationToken ct) =>
        {
            var references = await db.ScalarAsync<long>(
                "SELECT count(*) FROM event WHERE (city_code=@code OR district_code=@code) AND deleted_at IS NULL",
                new { code }, ct);
            var children = await db.ScalarAsync<long>(
                "SELECT count(*) FROM administrative_region WHERE parent_code=@code",
                new { code }, ct);
            if (references > 0 || children > 0)
                throw new ApiException(409, "region_in_use", "地区已被活动或下级地区使用，只能停用");
            var deleted = await db.ExecuteAsync(
                "DELETE FROM administrative_region WHERE code=@code", new { code }, ct);
            if (deleted == 0) throw new ApiException(404, "region_not_found", "地区不存在");
            return Results.NoContent();
        });

        admin.MapPost("/events/{id:guid}/review", async (
            Guid id, AdminEventReviewRequest request, Db db, CancellationToken ct) =>
        {
            if (request.Status is not ("approved" or "rejected"))
                throw new ApiException(400, "review_status_invalid", "审核状态无效");
            if (request.Status == "rejected" && string.IsNullOrWhiteSpace(request.Reason))
                throw new ApiException(400, "review_reason_required", "拒绝活动时必须填写理由");
            var item = await db.QueryOneAsync(
                """
                UPDATE event SET review_status=@status, review_reason=@reason,
                    reviewed_at=now(), reviewed_by_user_id=@actorUserId
                WHERE id=@id AND deleted_at IS NULL
                RETURNING id, title, status, review_status, review_reason, reviewed_at
                """, new { id, request.Status, request.Reason, request.ActorUserId }, ct);
            if (item is null) throw new ApiException(404, "event_not_found", "活动不存在");
            return ApiSupport.Ok(item);
        });

        admin.MapGet("/feature-flags", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                "SELECT key, description, enabled, rules, version, updated_at FROM feature_flag ORDER BY key",
                cancellationToken: ct)));

        admin.MapPatch("/feature-flags/{key}", async (
            string key, AdminFeatureFlagRequest request, Db db, CancellationToken ct) =>
        {
            var flag = await db.QueryOneAsync(
                """
                UPDATE feature_flag
                SET enabled=@enabled, version=version+1, updated_by_user_id=@actorUserId
                WHERE key=@key
                RETURNING key, description, enabled, rules, version, updated_at
                """, new { key, request.Enabled, request.ActorUserId }, ct);
            if (flag is null) throw new ApiException(404, "feature_flag_not_found", "功能开关不存在");
            return ApiSupport.Ok(flag);
        });

        admin.MapGet("/audit", async (
            Db db, string? action, string? targetType, int? limit, int? offset, CancellationToken ct) =>
        {
            var take = Math.Clamp(limit ?? 50, 1, 200);
            var skip = Math.Max(offset ?? 0, 0);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT al.id, al.actor_user_id, al.actor_role, al.action, al.target_type,
                       al.target_id, al.trace_id, al.metadata, al.created_at,
                       up.nickname AS actor_name
                FROM audit_log al
                LEFT JOIN user_profile up ON up.user_id=al.actor_user_id
                WHERE (@action IS NULL OR al.action=@action)
                  AND (@targetType IS NULL OR al.target_type=@targetType)
                ORDER BY al.created_at DESC
                LIMIT @limit OFFSET @offset
                """, new { action, targetType, limit = take, offset = skip }, ct));
        });

        admin.MapPost("/announcements", async (
            AdminAnnouncementRequest request, Db db, CancellationToken ct) =>
        {
            var created = await db.ExecuteAsync(
                """
                INSERT INTO notification (user_id, notification_type, title, body, data)
                SELECT id, 'announcement', @title, @body, '{}'::jsonb
                FROM app_user
                WHERE status='active' AND deleted_at IS NULL
                """, new { request.Title, request.Body }, ct);
            await WriteAudit(db, request.ActorUserId, "admin.announcement.published",
                "notification", null, new { request.Title, recipients = created }, ct);
            return ApiSupport.Ok(new { recipients = created });
        });

        return api;
    }

    private static Task<int> WriteAudit(
        Db db,
        Guid? actorUserId,
        string action,
        string targetType,
        Guid? targetId,
        object metadata,
        CancellationToken ct) =>
        db.ExecuteAsync(
            """
            INSERT INTO audit_log (
                actor_user_id, actor_role, action, target_type, target_id, metadata
            )
            VALUES (@actorUserId, 'admin', @action, @targetType, @targetId, @metadata::jsonb)
            """, new
            {
                actorUserId,
                action,
                targetType,
                targetId,
                metadata = System.Text.Json.JsonSerializer.Serialize(metadata)
            }, ct);

    private static string Required(string? value, string message) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new ApiException(400, "field_required", message)
            : value.Trim();

    private static async Task ValidateRegion(
        AdminRegionRequest request, Db db, CancellationToken ct)
    {
        if (request.Level is not (1 or 2))
            throw new ApiException(400, "region_level_invalid", "地区层级只能是城市或区县");
        if ((request.Level == 1) != string.IsNullOrWhiteSpace(request.ParentCode))
            throw new ApiException(400, "region_parent_invalid", "城市不能有上级，区县必须选择所属城市");
        if (request.Level == 2)
        {
            var parentLevel = await db.ScalarAsync<short>(
                "SELECT level FROM administrative_region WHERE code=@parentCode",
                new { request.ParentCode }, ct);
            if (parentLevel != 1)
                throw new ApiException(400, "region_parent_invalid", "请选择有效的上级城市");
        }
    }

}

public sealed record AdminUserStatusRequest(
    string Status, string? Reason, Guid? ActorUserId);
public sealed record AdminEventModerationRequest(
    string Status, string? ReasonCode, string? Reason, Guid? ActorUserId);
public sealed record AdminReportActionRequest(
    string Status, string? ResolutionCode, string? Note, long RowVersion, Guid? ActorUserId);
public sealed record AdminSafetyAlertRequest(
    string Status, string? Note, Guid? ActorUserId);
public sealed record AdminCategoryRequest(
    string Code,
    string NameZhCn,
    string? NameEnUs,
    string? NameKoKr,
    string? DescriptionZhCn,
    string? DescriptionEnUs,
    string? DescriptionKoKr,
    string? Icon,
    string? IconKey,
    string? Color,
    Guid? ParentId,
    int SortOrder,
    bool IsActive,
    bool IsFeatured);
public sealed record AdminRegionRequest(
    string Code,
    string? ParentCode,
    short Level,
    string NameZhCn,
    string NameKoKr,
    string NameEnUs,
    int SortOrder,
    bool IsActive);
public sealed record AdminFeatureFlagRequest(bool Enabled, Guid? ActorUserId);
public sealed record AdminEventReviewRequest(string Status, string? Reason, Guid? ActorUserId);
public sealed record AdminAnnouncementRequest(string Title, string Body, Guid? ActorUserId);
public sealed record AdminSystemAvatarRequest(
    string Code,
    string NameZhCn,
    string NameEnUs,
    string NameKoKr,
    int SortOrder,
    bool IsActive);

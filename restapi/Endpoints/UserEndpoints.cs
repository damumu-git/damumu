using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class UserEndpoints
{
    public static RouteGroupBuilder MapUserEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/system-avatars", async (
            Db db, string? locale, CancellationToken ct) =>
        {
            var language = NormalizeLocale(locale);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, code,
                       CASE @locale
                           WHEN 'en' THEN name_en_us
                           WHEN 'ko' THEN name_ko_kr
                           ELSE name_zh_cn
                       END AS name,
                       image_url AS "imageUrl", width, height
                FROM system_avatar
                WHERE is_active=true
                ORDER BY sort_order, created_at
                """, new { locale = language }, ct));
        });

        api.MapPost("/auth/register", async (
            RegisterRequest request, Db db, AuthService auth, CancellationToken ct) =>
        {
            var nickname = request.Nickname?.Trim();
            var email = request.Email?.Trim().ToLowerInvariant();
            ValidateCredentials(nickname, email, request.Password);
            var avatarId = await ResolveAvatarId(db, request.AvatarId, ct);
            var avatarImageUrl = avatarId.HasValue
                ? await db.ScalarAsync<string>(
                    "SELECT image_url FROM system_avatar WHERE id=@avatarId",
                    new { avatarId }, ct)
                : null;
            var existing = await db.ScalarAsync<int>(
                "SELECT count(*) FROM user_credential WHERE lower(email)=@email",
                new { email }, ct);
            if (existing > 0)
                throw new ApiException(409, "email_exists", "该邮箱已注册");

            var userId = Guid.NewGuid();
            var passwordHash = auth.HashPassword(request.Password!);
            await db.ExecuteAsync(
                """
                WITH new_user AS (
                    INSERT INTO app_user (id, status, role, adult_confirmed_at)
                    VALUES (@userId, 'active', 'user', now())
                    RETURNING id
                ), new_profile AS (
                    INSERT INTO user_profile (
                        user_id, nickname, avatar_url, city_code, languages, profile_completed_at
                    )
                    SELECT id, @nickname, @avatarUrl, 'SEOUL', ARRAY['zh-CN']::varchar[], now()
                    FROM new_user
                    RETURNING user_id
                )
                INSERT INTO user_credential (user_id, email, password_hash)
                SELECT user_id, @email, @passwordHash FROM new_profile
                """,
                new
                {
                    userId,
                    nickname,
                    avatarUrl = avatarId.HasValue ? $"system:{avatarId}" : null,
                    email,
                    passwordHash
                }, ct);

            return ApiSupport.Created($"/api/v1/users/{userId}", new
            {
                accessToken = auth.CreateToken(userId),
                user = new
                {
                    id = userId,
                    nickname,
                    email,
                    avatarUrl = avatarId.HasValue ? $"system:{avatarId}" : null,
                    avatarImageUrl
                }
            });
        });

        api.MapPost("/auth/login", async (
            LoginRequest request, Db db, AuthService auth, CancellationToken ct) =>
        {
            var email = request.Email?.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(email) || string.IsNullOrEmpty(request.Password))
                throw new ApiException(400, "credentials_required", "请输入邮箱和密码");
            var user = await db.QueryOneAsync(
                """
                SELECT u.id, u.status, c.email, c.password_hash,
                       p.nickname, p.avatar_url AS "avatarUrl",
                       sa.image_url AS "avatarImageUrl"
                FROM user_credential c
                JOIN app_user u ON u.id=c.user_id
                JOIN user_profile p ON p.user_id=u.id
                LEFT JOIN system_avatar sa ON p.avatar_url='system:'||sa.id::text
                WHERE lower(c.email)=@email AND u.deleted_at IS NULL
                """, new { email }, ct);
            if (user is null || !auth.VerifyPassword(
                    request.Password, (string)user["password_hash"]!))
                throw new ApiException(401, "invalid_credentials", "邮箱或密码不正确");
            if (!string.Equals(user["status"]?.ToString(), "active", StringComparison.Ordinal))
                throw new ApiException(403, "account_unavailable", "账号当前不可用");

            var userId = (Guid)user["id"]!;
            await db.ExecuteAsync(
                "UPDATE user_credential SET last_login_at=now() WHERE user_id=@userId",
                new { userId }, ct);
            return ApiSupport.Ok(new
            {
                accessToken = auth.CreateToken(userId),
                user = new
                {
                    id = userId,
                    nickname = user["nickname"],
                    email = user["email"],
                    avatarUrl = user["avatarUrl"],
                    avatarImageUrl = user["avatarImageUrl"]
                }
            });
        });

        api.MapPost("/auth/dev-login", async (DevLoginRequest request, Db db, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.Nickname))
                throw new ApiException(400, "nickname_required", "请输入昵称");

            var userId = Guid.NewGuid();
            await db.ExecuteAsync(
                """
                WITH new_user AS (
                    INSERT INTO app_user (id, status, role, adult_confirmed_at)
                    VALUES (@userId, 'active', 'user', now())
                    RETURNING id
                )
                INSERT INTO user_profile (user_id, nickname, city_code, languages, profile_completed_at)
                SELECT id, @nickname, @cityCode, ARRAY['zh-CN']::varchar[], now()
                FROM new_user
                """,
                new
                {
                    userId,
                    nickname = request.Nickname.Trim(),
                    cityCode = request.CityCode ?? "SEOUL"
                }, ct);
            return ApiSupport.Created($"/api/v1/users/{userId}", new
            {
                userId,
                accessToken = $"dev:{userId}",
                usage = "开发环境请求请发送 X-User-Id"
            });
        });

        api.MapGet("/me", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var user = await db.QueryOneAsync(
                """
                SELECT u.id, u.status, u.role, u.locale, u.timezone, u.adult_confirmed_at,
                       u.created_at, p.nickname, p.avatar_url AS "avatarUrl",
                       COALESCE(sa.image_url, CASE
                           WHEN p.avatar_url LIKE '/uploads/%' THEN p.avatar_url
                           ELSE NULL
                       END) AS "avatarImageUrl",
                       c.email,
                       p.bio, p.city_code, p.contact_type AS "contactType",
                       p.contact_value AS "contactValue",
                       p.district_code, p.languages, p.gender, p.occupation, p.arrival_year,
                       COALESCE(t.score, 0) AS trust_score,
                       COALESCE(t.review_count, 0) AS review_count,
                       COALESCE(t.attended_count, 0) AS attended_count,
                       COALESCE(t.organized_count, 0) AS organized_count
                FROM app_user u
                LEFT JOIN user_profile p ON p.user_id=u.id
                LEFT JOIN user_credential c ON c.user_id=u.id
                LEFT JOIN system_avatar sa ON p.avatar_url='system:'||sa.id::text
                LEFT JOIN trust_snapshot t ON t.user_id=u.id
                WHERE u.id=@userId AND u.deleted_at IS NULL
                """, new { userId }, ct);
            if (user is null) throw new ApiException(404, "user_not_found", "用户不存在");
            return ApiSupport.Ok(user);
        });

        api.MapPatch("/me", async (HttpContext context, UpdateProfileRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var profile = await db.QueryOneAsync(
                """
                UPDATE user_profile
                SET nickname=COALESCE(@nickname, nickname),
                    avatar_url=COALESCE(@avatarUrl, avatar_url),
                    bio=COALESCE(@bio, bio),
                    city_code=COALESCE(@cityCode, city_code),
                    district_code=COALESCE(@districtCode, district_code),
                    languages=COALESCE(@languages, languages),
                    occupation=COALESCE(@occupation, occupation),
                    arrival_year=COALESCE(@arrivalYear, arrival_year),
                    contact_type=COALESCE(@contactType, contact_type),
                    contact_value=COALESCE(@contactValue, contact_value)
                WHERE user_id=@userId
                RETURNING user_id, nickname, avatar_url, bio, city_code, district_code,
                          languages, occupation, arrival_year, contact_type, contact_value,
                          row_version, updated_at
                """, new
                {
                    userId,
                    nickname = EmptyToNull(request.Nickname),
                    avatarUrl = EmptyToNull(request.AvatarUrl),
                    bio = EmptyToNull(request.Bio),
                    cityCode = EmptyToNull(request.CityCode),
                    districtCode = EmptyToNull(request.DistrictCode),
                    languages = request.Languages,
                    occupation = EmptyToNull(request.Occupation),
                    arrivalYear = request.ArrivalYear,
                    contactType = EmptyToNull(request.ContactType),
                    contactValue = EmptyToNull(request.ContactValue)
                }, ct);
            if (profile is null) throw new ApiException(404, "profile_not_found", "用户资料不存在");
            return ApiSupport.Ok(profile);
        });

        api.MapPut("/me/avatar/system", async (
            HttpContext context, SystemAvatarRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var avatarId = await ResolveAvatarId(db, request.AvatarId, ct);
            if (!avatarId.HasValue)
                throw new ApiException(400, "avatar_required", "请选择系统头像");
            var avatarUrl = $"system:{avatarId}";
            var count = await db.ExecuteAsync(
                "UPDATE user_profile SET avatar_url=@avatarUrl WHERE user_id=@userId",
                new { userId, avatarUrl }, ct);
            if (count == 0) throw new ApiException(404, "profile_not_found", "用户资料不存在");
            var avatarImageUrl = await db.ScalarAsync<string>(
                "SELECT image_url FROM system_avatar WHERE id=@avatarId",
                new { avatarId }, ct);
            return ApiSupport.Ok(new { avatarUrl, avatarImageUrl });
        });

        api.MapPost("/me/avatar", async (
            HttpContext context, IFormFile avatar, Db db, IWebHostEnvironment environment,
            CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            AvatarImageValidator.Validate(avatar);
            await using var input = avatar.OpenReadStream();
            var relativeDirectory = Path.Combine("avatars", userId.ToString("N"));
            var directory = Path.Combine(environment.ContentRootPath, "uploads", relativeDirectory);
            Directory.CreateDirectory(directory);
            var fileName = $"{Guid.NewGuid():N}.jpg";
            var fullPath = Path.Combine(directory, fileName);
            await using (var output = File.Create(fullPath))
                await input.CopyToAsync(output, ct);

            var avatarUrl = $"/uploads/avatars/{userId:N}/{fileName}";
            var count = await db.ExecuteAsync(
                "UPDATE user_profile SET avatar_url=@avatarUrl WHERE user_id=@userId",
                new { userId, avatarUrl }, ct);
            if (count == 0) throw new ApiException(404, "profile_not_found", "用户资料不存在");
            return ApiSupport.Ok(new
            {
                avatarUrl,
                width = 512,
                height = 512,
                format = "jpeg",
                bytes = avatar.Length
            });
        }).DisableAntiforgery();

        api.MapPut("/me/interests", async (HttpContext context, SetInterestsRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("DELETE FROM user_interest WHERE user_id=@userId", new { userId }, ct);
            foreach (var interestId in request.InterestIds.Distinct().Take(20))
            {
                await db.ExecuteAsync(
                    """
                    INSERT INTO user_interest (user_id, interest_id)
                    VALUES (@userId, @interestId)
                    ON CONFLICT DO NOTHING
                    """, new { userId, interestId }, ct);
            }
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT i.id, i.code, i.name_zh_cn, i.icon
                FROM user_interest ui
                JOIN interest i ON i.id=ui.interest_id
                WHERE ui.user_id=@userId
                ORDER BY i.sort_order
                """, new { userId }, ct));
        });

        api.MapGet("/me/activities", async (HttpContext context, Db db, string? status, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT e.id, e.title, e.description, e.status AS event_status,
                       e.city_code, e.district_code, e.approval_mode,
                       e.capacity, e.approved_count, e.price_amount, e.price_currency,
                       em.status AS membership_status, em.member_role, em.checked_in_at,
                       s.starts_at, s.ends_at,
                       c.name_zh_cn AS category_name, c.icon AS category_icon,
                       city.name_zh_cn AS city_name, district.name_zh_cn AS district_name
                FROM event_member em
                JOIN event e ON e.id=em.event_id
                JOIN category c ON c.id=e.category_id
                LEFT JOIN administrative_region city ON city.code=e.city_code
                LEFT JOIN administrative_region district ON district.code=e.district_code
                LEFT JOIN LATERAL (
                    SELECT starts_at, ends_at FROM event_schedule
                    WHERE event_id=e.id ORDER BY starts_at LIMIT 1
                ) s ON true
                WHERE em.user_id=@userId
                  AND (@status IS NULL OR em.status=@status)
                  AND e.deleted_at IS NULL
                ORDER BY s.starts_at DESC NULLS LAST
                """, new { userId, status }, ct));
        });

        api.MapGet("/me/notifications", async (
            HttpContext context, Db db, bool? unreadOnly, int? limit, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var take = Math.Clamp(limit ?? 30, 1, 100);
            return ApiSupport.Ok(await db.QueryAsync(
                """
                SELECT id, notification_type, title, body, data, read_at, created_at
                FROM notification
                WHERE user_id=@userId AND (NOT @unreadOnly OR read_at IS NULL)
                ORDER BY created_at DESC
                LIMIT @limit
                """, new { userId, unreadOnly = unreadOnly ?? false, limit = take }, ct));
        });

        api.MapPost("/me/notifications/{id:guid}/read", async (
            Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var count = await db.ExecuteAsync(
                "UPDATE notification SET read_at=COALESCE(read_at, now()) WHERE id=@id AND user_id=@userId",
                new { id, userId }, ct);
            if (count == 0) throw new ApiException(404, "notification_not_found", "通知不存在");
            return ApiSupport.Ok(new { id, read = true });
        });

        api.MapPost("/blocks/{blockedUserId:guid}", async (
            Guid blockedUserId, HttpContext context, BlockRequest request, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync(
                """
                INSERT INTO user_block (blocker_user_id, blocked_user_id, reason_code)
                VALUES (@userId, @blockedUserId, @reasonCode)
                ON CONFLICT (blocker_user_id, blocked_user_id)
                DO UPDATE SET reason_code=EXCLUDED.reason_code
                """, new { userId, blockedUserId, reasonCode = request.ReasonCode }, ct);
            return ApiSupport.Ok(new { blockedUserId, blocked = true });
        });

        api.MapDelete("/blocks/{blockedUserId:guid}", async (
            Guid blockedUserId, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync(
                "DELETE FROM user_block WHERE blocker_user_id=@userId AND blocked_user_id=@blockedUserId",
                new { userId, blockedUserId }, ct);
            return Results.NoContent();
        });

        api.MapDelete("/me", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync(
                """
                UPDATE app_user
                SET status='deleting', deletion_requested_at=now()
                WHERE id=@userId AND deleted_at IS NULL
                """, new { userId }, ct);
            return Results.Accepted(value: new
            {
                data = new { status = "deleting" },
                meta = (object?)null,
                error = (object?)null,
                traceId = System.Diagnostics.Activity.Current?.Id
            });
        });

        return api;
    }

    private static string? EmptyToNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static async Task<Guid?> ResolveAvatarId(
        Db db, Guid? avatarId, CancellationToken ct)
    {
        if (!avatarId.HasValue)
            return await db.ScalarAsync<Guid>(
                """
                SELECT id FROM system_avatar
                WHERE is_active=true ORDER BY sort_order, created_at LIMIT 1
                """, cancellationToken: ct);
        var exists = await db.ScalarAsync<int>(
            "SELECT count(*) FROM system_avatar WHERE id=@avatarId AND is_active=true",
            new { avatarId }, ct);
        if (exists == 0)
            throw new ApiException(400, "avatar_invalid", "所选系统头像不存在或已停用");
        return avatarId;
    }

    private static string NormalizeLocale(string? locale) =>
        locale?.ToLowerInvariant().StartsWith("en") == true ? "en"
        : locale?.ToLowerInvariant().StartsWith("ko") == true ? "ko"
        : "zh";

    private static void ValidateCredentials(string? nickname, string? email, string? password)
    {
        if (nickname is null || nickname.Length is < 2 or > 30)
            throw new ApiException(400, "nickname_invalid", "昵称长度需要为 2–30 个字符");
        if (email is null || email.Length > 254
            || !System.Net.Mail.MailAddress.TryCreate(email, out _))
            throw new ApiException(400, "email_invalid", "请输入有效邮箱");
        if (password is null || password.Length is < 8 or > 128
            || !password.Any(char.IsLetter) || !password.Any(char.IsDigit))
            throw new ApiException(400, "password_weak", "密码需为 8–128 位，并同时包含字母和数字");
    }
}

public sealed record RegisterRequest(string? Nickname, string? Email, string? Password, Guid? AvatarId);
public sealed record LoginRequest(string? Email, string? Password);
public sealed record SystemAvatarRequest(Guid? AvatarId);
public sealed record DevLoginRequest(string Nickname, string? CityCode);
public sealed record UpdateProfileRequest(
    string? Nickname,
    string? AvatarUrl,
    string? Bio,
    string? CityCode,
    string? DistrictCode,
    string[]? Languages,
    string? Occupation,
    short? ArrivalYear,
    string? ContactType,
    string? ContactValue);
public sealed record SetInterestsRequest(Guid[] InterestIds);
public sealed record BlockRequest(string? ReasonCode);

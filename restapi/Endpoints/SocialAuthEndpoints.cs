using Muda.Api.Infrastructure;
using Npgsql;

namespace Muda.Api.Endpoints;

public static class SocialAuthEndpoints
{
    public static RouteGroupBuilder MapSocialAuthEndpoints(this RouteGroupBuilder api)
    {
        api.MapPost("/auth/social/{provider}", async (string provider, SocialLoginRequest request,
            HttpContext context, ISocialIdentityVerifier verifier, SocialAccountService accounts,
            AuthService auth, CancellationToken ct) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            var identity = await verifier.VerifyAsync(provider, request.Token ?? "", ct);
            var user = await accounts.LoginAsync(identity, request, ct);
            return user is null
                ? ApiSupport.Ok(new { registrationRequired = true })
                : ApiSupport.Ok(new { accessToken = auth.CreateToken((Guid)user["id"]!), user });
        });
        return api;
    }
}

public sealed record SocialLoginRequest(string? Token, string? Nickname = null,
    bool AgeConfirmed = false, bool PrivacyAcknowledged = false, string? PrivacyVersion = null,
    string? Locale = null);

public sealed class SocialAccountService(NpgsqlDataSource source)
{
    public async Task<Dictionary<string, object?>?> LoginAsync(SocialIdentity identity,
        SocialLoginRequest request, CancellationToken ct)
    {
        await using var connection = await source.OpenConnectionAsync(ct);
        await using var transaction = await connection.BeginTransactionAsync(ct);
        // Serialize creation across API instances, not just within this process.
        await using (var gate = new NpgsqlCommand(
            "SELECT pg_advisory_xact_lock(hashtextextended(@key, 0))", connection, transaction))
        {
            gate.Parameters.AddWithValue("key", $"social:{identity.Provider}:{identity.Subject}");
            await gate.ExecuteNonQueryAsync(ct);
        }
        Guid? userId;
        await using (var find = new NpgsqlCommand(
            "SELECT user_id FROM user_external_identity WHERE provider=@provider AND subject=@subject",
            connection, transaction))
        {
            find.Parameters.AddWithValue("provider", identity.Provider);
            find.Parameters.AddWithValue("subject", identity.Subject);
            userId = await find.ExecuteScalarAsync(ct) as Guid?;
        }
        if (userId is null)
        {
            if (request.Nickname is null) return null; // no local account or session yet
            PrivacyRules.ValidateRegistration(request.AgeConfirmed, request.PrivacyAcknowledged, request.PrivacyVersion);
            var nickname = request.Nickname.Trim();
            if (nickname.Length is < 2 or > 30)
                throw new ApiException(400, "nickname_invalid", "昵称长度需要为 2–30 个字符");
            var locale = request.Locale is "en" or "ko" ? request.Locale : "zh";
            userId = Guid.NewGuid();
            await using var create = new NpgsqlCommand(
                """
                INSERT INTO app_user(id, status, role, locale, minimum_age_confirmed_at,
                    privacy_notice_version, privacy_notice_acknowledged_at)
                VALUES (@userId, 'active', 'user', @locale, now(), @version, now());
                INSERT INTO user_profile(user_id, nickname, avatar_url, city_code, languages, profile_completed_at)
                VALUES (@userId, @nickname,
                    (SELECT 'system:'||id::text FROM system_avatar WHERE is_active=true ORDER BY sort_order, created_at LIMIT 1),
                    'SEOUL', ARRAY[@locale]::varchar[], now());
                INSERT INTO user_external_identity(provider, subject, user_id) VALUES (@provider, @subject, @userId);
                """, connection, transaction);
            create.Parameters.AddWithValue("userId", userId.Value);
            create.Parameters.AddWithValue("nickname", nickname);
            create.Parameters.AddWithValue("locale", locale);
            create.Parameters.AddWithValue("version", PrivacyRules.NoticeVersion);
            create.Parameters.AddWithValue("provider", identity.Provider);
            create.Parameters.AddWithValue("subject", identity.Subject);
            await create.ExecuteNonQueryAsync(ct);
        }
        Dictionary<string, object?> user;
        await using (var read = new NpgsqlCommand(
            """
            SELECT u.id, u.status, u.deleted_at, p.nickname, p.avatar_url AS "avatarUrl",
                   sa.image_url AS "avatarImageUrl", c.email
            FROM app_user u JOIN user_profile p ON p.user_id=u.id
            LEFT JOIN user_credential c ON c.user_id=u.id
            LEFT JOIN system_avatar sa ON p.avatar_url='system:'||sa.id::text
            WHERE u.id=@userId FOR UPDATE OF u
            """, connection, transaction))
        {
            read.Parameters.AddWithValue("userId", userId.Value);
            await using var reader = await read.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct) || reader.GetString(1) != "active" || !reader.IsDBNull(2))
                throw new ApiException(403, "account_unavailable", "账号当前不可用");
            user = new(StringComparer.OrdinalIgnoreCase);
            foreach (var key in new[] { "id", "nickname", "avatarUrl", "avatarImageUrl", "email" })
                user[key] = reader.IsDBNull(reader.GetOrdinal(key)) ? null : reader[key];
        }
        await using (var update = new NpgsqlCommand(
            "UPDATE user_external_identity SET last_login_at=now() WHERE provider=@provider AND subject=@subject",
            connection, transaction))
        {
            update.Parameters.AddWithValue("provider", identity.Provider);
            update.Parameters.AddWithValue("subject", identity.Subject);
            await update.ExecuteNonQueryAsync(ct);
        }
        await transaction.CommitAsync(ct);
        return user;
    }
}

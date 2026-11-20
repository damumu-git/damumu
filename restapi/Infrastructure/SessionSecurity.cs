using System.Security.Cryptography;
using System.Text;

namespace Muda.Api.Infrastructure;

public sealed class SessionSecurity(Db db, AuthService auth)
{
    public const string CookieName = "__Host-damu-session";
    public const string AdminCookie = "__Host-damu-admin";
    public const string WebOrigin = "https://www.damumu.com";
    public const string AdminOrigin = "https://admin.damumu.com";

    public static string Hash(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    public static CookieOptions Cookie(DateTimeOffset? expires = null) => new()
    {
        HttpOnly = true, Secure = true, SameSite = SameSiteMode.Strict, Path = "/", Expires = expires
    };

    public async Task<object> SignInAsync(HttpContext context, Guid userId, object user,
        bool remember, CancellationToken ct)
    {
        var web = context.Request.Host.Host == "www.damumu.com";
        var expires = DateTimeOffset.UtcNow.AddDays(web ? 7 : 30);
        var accessExpires = web ? expires : DateTimeOffset.UtcNow.AddMinutes(15);
        var token = auth.CreateToken(userId, accessExpires);
        var refresh = web ? null : Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        await db.ExecuteAsync("""
            INSERT INTO auth_session(token_hash,user_id,expires_at,access_expires_at,refresh_hash)
            VALUES (@hash,@userId,@expires,@accessExpires,@refreshHash)
            """, new { hash = Hash(token), userId, expires, accessExpires, refreshHash = refresh is null ? null : Hash(refresh) }, ct);
        context.Response.Headers.CacheControl = "no-store";
        if (web)
        {
            if (context.Request.Headers.Origin != WebOrigin)
                throw new ApiException(403, "invalid_origin", "登录请求来源无效");
            context.Response.Cookies.Append(CookieName, token, Cookie(remember ? expires : null));
            return new { user, expiresAt = expires.ToUnixTimeMilliseconds() };
        }
        return new { accessToken = token, refreshToken = refresh, expiresAt = expires.ToUnixTimeMilliseconds(), user };
    }

    public async Task<Guid?> ValidateAsync(string? token, CancellationToken ct)
    {
        if (token is null || token.Length > 1024 || !auth.TryValidateToken(token, out var userId)) return null;
        var valid = await db.ScalarAsync<bool>("""
            SELECT EXISTS(SELECT 1 FROM auth_session s JOIN app_user u ON u.id=s.user_id
                WHERE s.user_id=@userId AND s.revoked_at IS NULL AND s.expires_at>now()
                  AND ((s.token_hash=@hash AND s.access_expires_at>now())
                    OR (s.previous_access_hash=@hash AND s.previous_access_expires_at>now()))
                  AND u.status='active' AND u.deleted_at IS NULL)
            """, new { hash = Hash(token), userId }, ct);
        return valid ? userId : null;
    }

    public async Task<object> RefreshAsync(string? refresh, CancellationToken ct)
    {
        if (refresh?.Length != 64) throw new ApiException(401, "session_expired", "登录已失效，请重新登录");
        var hash = Hash(refresh);
        var result = await db.InTransactionAsync<object?>(async transaction =>
        {
            var session = await transaction.QueryOneAsync("""
                SELECT s.user_id,s.expires_at,s.refresh_hash,s.rotated_at,s.token_hash
                FROM auth_session s JOIN app_user u ON u.id=s.user_id
                WHERE (s.refresh_hash=@hash OR s.previous_refresh_hash=@hash)
                    AND s.revoked_at IS NULL AND s.expires_at>now() AND u.status='active' AND u.deleted_at IS NULL
                FOR UPDATE OF s
                """, new { hash }, ct);
            if (session is null) return null;
            if (session["refresh_hash"]?.ToString() != hash &&
                (session["rotated_at"] is not DateTime rotated || rotated < DateTime.UtcNow.AddSeconds(-30)))
            {
                await transaction.ExecuteAsync("UPDATE auth_session SET revoked_at=now() WHERE token_hash=@tokenHash",
                    new { tokenHash = session["token_hash"] }, ct);
                return null;
            }
            var accessExpires = DateTimeOffset.UtcNow.AddMinutes(15);
            var expires = new DateTimeOffset((DateTime)session["expires_at"]!);
            if (accessExpires > expires) accessExpires = expires;
            var token = auth.CreateToken((Guid)session["user_id"]!, accessExpires);
            var nextRefresh = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            await transaction.ExecuteAsync("""
                UPDATE auth_session SET previous_access_hash=token_hash,previous_access_expires_at=access_expires_at,
                    token_hash=@tokenHash,access_expires_at=@accessExpires,
                    previous_refresh_hash=@hash,refresh_hash=@refreshHash,rotated_at=now()
                WHERE token_hash=@oldHash
                """, new
                {
                    tokenHash = Hash(token), accessExpires, hash, refreshHash = Hash(nextRefresh), oldHash = session["token_hash"]
                }, ct);
            return new { accessToken = token, refreshToken = nextRefresh, expiresAt = expires.ToUnixTimeMilliseconds() };
        }, ct);
        return result ?? throw new ApiException(401, "session_expired", "登录已失效，请重新登录");
    }

    public static string? RequestToken(HttpContext context)
    {
        var value = context.Request.Headers.Authorization.ToString();
        if (value.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) return value[7..].Trim();
        return context.Request.Cookies[CookieName];
    }

    public async Task CheckAttemptAsync(string bucket, CancellationToken ct)
    {
        var blocked = await db.ScalarAsync<bool>("""
            SELECT EXISTS(SELECT 1 FROM auth_attempt WHERE bucket=@bucket AND blocked_until>now())
            """, new { bucket = Hash(bucket) }, ct);
        if (blocked) throw new ApiException(429, "login_limited", "尝试次数过多，请稍后再试");
    }

    public Task FailedAttemptAsync(string bucket, CancellationToken ct) => db.ExecuteAsync("""
        INSERT INTO auth_attempt(bucket,failures) VALUES (@bucket,1)
        ON CONFLICT(bucket) DO UPDATE SET
            failures=CASE WHEN auth_attempt.window_started_at<now()-interval '15 minutes'
                          THEN 1 ELSE auth_attempt.failures+1 END,
            blocked_until=CASE WHEN auth_attempt.window_started_at>=now()-interval '15 minutes'
                                  AND auth_attempt.failures>=4 THEN now()+interval '15 minutes'
                              ELSE auth_attempt.blocked_until END,
            window_started_at=CASE WHEN auth_attempt.window_started_at<now()-interval '15 minutes'
                                   THEN now() ELSE auth_attempt.window_started_at END
        """, new { bucket = Hash(bucket) }, ct);
}

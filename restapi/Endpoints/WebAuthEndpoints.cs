using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.WebUtilities;
using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class WebAuthEndpoints
{
    private const string Origin = "https://app.damumu.com";
    private const string Path = "/api/v1/auth/web";
    private const string StateCookie = "__Host-damu-oauth-state";
    private const string IdentityCookie = "__Host-damu-oauth-identity";
    private static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);

    public static RouteGroupBuilder MapWebAuthEndpoints(this RouteGroupBuilder api)
    {
        var group = api.MapGroup("/auth/web");
        group.AddEndpointFilter(async (context, next) =>
        {
            context.HttpContext.Response.Headers.CacheControl = "no-store";
            context.HttpContext.Response.Headers["Referrer-Policy"] = "no-referrer";
            return await next(context);
        });

        group.MapGet("/options", (IConfiguration configuration) => ApiSupport.Ok(new
        {
            google = ReadProvider(configuration, "google") is not null,
            kakao = ReadProvider(configuration, "kakao") is not null,
            privacyVersion = PrivacyRules.NoticeVersion
        }));

        group.MapGet("/{provider}/start", (string provider, HttpContext context,
            IConfiguration configuration, IDataProtectionProvider protection) =>
        {
            var settings = ReadProvider(configuration, provider)
                ?? throw new ApiException(503, "web_login_unavailable", "该网页登录方式尚未配置");
            var state = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
            var verifier = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
            var transaction = new OAuthTransaction(provider, state, verifier);
            WriteCookie(context, StateCookie, Protect(protection, StateCookie, transaction), SameSiteMode.Lax);
            context.Response.Cookies.Delete(IdentityCookie, Cookie(SameSiteMode.Strict));
            var parameters = new Dictionary<string, string?>
            {
                ["client_id"] = settings.ClientId,
                ["response_type"] = "code",
                ["redirect_uri"] = Callback(provider),
                ["state"] = state
            };
            if (provider == "google")
            {
                parameters["scope"] = "openid";
                parameters["code_challenge_method"] = "S256";
                parameters["code_challenge"] = WebEncoders.Base64UrlEncode(
                    SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
            }
            return Results.Redirect(QueryHelpers.AddQueryString(settings.Authorize, parameters));
        });

        group.MapGet("/{provider}/callback", async (string provider, string? code, string? state,
            HttpContext context, IConfiguration configuration, IDataProtectionProvider protection,
            IHttpClientFactory clients, CancellationToken ct) =>
        {
            var transaction = ReadCookie<OAuthTransaction>(context, protection, StateCookie);
            if (transaction is null || transaction.Provider != provider || state is null ||
                !CryptographicOperations.FixedTimeEquals(
                    Encoding.UTF8.GetBytes(state), Encoding.UTF8.GetBytes(transaction.State)))
                return Results.Redirect("/#social-error");
            context.Response.Cookies.Delete(StateCookie, Cookie(SameSiteMode.Lax));
            var settings = ReadProvider(configuration, provider);
            if (settings is null || string.IsNullOrWhiteSpace(code) || code.Length > 4096)
                return Results.Redirect("/#social-error");

            var form = new Dictionary<string, string>
            {
                ["grant_type"] = "authorization_code",
                ["client_id"] = settings.ClientId,
                ["client_secret"] = settings.ClientSecret,
                ["redirect_uri"] = Callback(provider),
                ["code"] = code
            };
            if (provider == "google") form["code_verifier"] = transaction.Verifier;
            try
            {
                using var content = new FormUrlEncodedContent(form);
                var client = clients.CreateClient(nameof(WebAuthEndpoints));
                using var response = await client.PostAsync(settings.Token, content, ct);
                if (!response.IsSuccessStatusCode) return Results.Redirect("/#social-error");
                using var body = await JsonDocument.ParseAsync(
                    await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
                var tokenKey = provider == "google" ? "id_token" : "access_token";
                if (!body.RootElement.TryGetProperty(tokenKey, out var value) ||
                    value.ValueKind != JsonValueKind.String || string.IsNullOrEmpty(value.GetString()))
                    return Results.Redirect("/#social-error");
                var token = value.GetString()!;
                var identity = provider == "google"
                    ? await SocialIdentityVerifier.VerifyGoogleAsync(token, settings.ClientId)
                    : await SocialIdentityVerifier.VerifyKakaoAsync(client, token, settings.KakaoAppId, ct);
                WriteCookie(context, IdentityCookie, Protect(protection, IdentityCookie, identity), SameSiteMode.Strict);
                return Results.Redirect("/#social-complete");
            }
            catch (Exception error) when (error is ApiException or HttpRequestException or JsonException
                or InvalidOperationException or Google.Apis.Auth.InvalidJwtException
                || error is OperationCanceledException && !ct.IsCancellationRequested)
            {
                return Results.Redirect("/#social-error");
            }
        });

        group.MapPost("/complete", async (WebSocialRegistration request, HttpContext context,
            IDataProtectionProvider protection, SocialAccountService accounts, AuthService auth,
            CancellationToken ct) =>
        {
            if (!string.Equals(context.Request.Headers.Origin, Origin, StringComparison.Ordinal))
                throw new ApiException(403, "web_origin_invalid", "网页登录请求来源无效");
            var identity = ReadCookie<SocialIdentity>(context, protection, IdentityCookie)
                ?? throw new ApiException(401, "web_login_expired", "登录已失效，请重新授权");
            var user = await accounts.LoginAsync(identity, new SocialLoginRequest(null, request.Nickname,
                request.AgeConfirmed, request.PrivacyAcknowledged, request.PrivacyVersion, "zh"), ct);
            if (user is null)
                return ApiSupport.Ok(new { registrationRequired = true, privacyVersion = PrivacyRules.NoticeVersion });
            context.Response.Cookies.Delete(IdentityCookie, Cookie(SameSiteMode.Strict));
            return ApiSupport.Ok(new { accessToken = auth.CreateToken((Guid)user["id"]!), user });
        });
        return api;
    }

    private static Provider? ReadProvider(IConfiguration configuration, string provider)
    {
        if (provider is not ("google" or "kakao")) return null;
        var section = configuration.GetSection($"WebSocialLogin:{provider}");
        var id = section["ClientId"];
        var secret = section["ClientSecret"];
        if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(secret)) return null;
        if (provider == "google")
            return new(id, secret, "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token");
        if (!long.TryParse(configuration["SocialLogin:kakao:AppId"], out var appId) || appId <= 0) return null;
        return new(id, secret, "https://kauth.kakao.com/oauth/authorize", "https://kauth.kakao.com/oauth/token", appId);
    }

    private static string Callback(string provider) => $"{Origin}{Path}/{provider}/callback";

    private static CookieOptions Cookie(SameSiteMode sameSite) => new()
    {
        Path = "/", Secure = true, HttpOnly = true, SameSite = sameSite, IsEssential = true
    };

    private static void WriteCookie(HttpContext context, string key, string value, SameSiteMode sameSite)
    {
        var options = Cookie(sameSite);
        options.MaxAge = Lifetime;
        context.Response.Cookies.Append(key, value, options);
    }

    private static string Protect<T>(IDataProtectionProvider protection, string key, T value) =>
        protection.CreateProtector(key).ToTimeLimitedDataProtector()
            .Protect(JsonSerializer.Serialize(value), Lifetime);

    private static T? ReadCookie<T>(HttpContext context, IDataProtectionProvider protection, string key)
    {
        if (!context.Request.Cookies.TryGetValue(key, out var value)) return default;
        try
        {
            return JsonSerializer.Deserialize<T>(protection.CreateProtector(key)
                .ToTimeLimitedDataProtector().Unprotect(value));
        }
        catch (Exception error) when (error is CryptographicException or JsonException)
        {
            return default;
        }
    }

    private sealed record OAuthTransaction(string Provider, string State, string Verifier);
    private sealed record Provider(string ClientId, string ClientSecret, string Authorize, string Token, long KakaoAppId = 0);
}

public sealed record WebSocialRegistration(string? Nickname, bool AgeConfirmed, bool PrivacyAcknowledged,
    string? PrivacyVersion);

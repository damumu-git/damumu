using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;
using Google.Apis.Auth;

namespace Muda.Api.Infrastructure;

public sealed record SocialIdentity(string Provider, string Subject);

public interface ISocialIdentityVerifier
{
    Task<SocialIdentity> VerifyAsync(string provider, string token, CancellationToken ct);
}

public sealed class SocialIdentityVerifier(HttpClient http, IConfiguration configuration) : ISocialIdentityVerifier
{
    public async Task<SocialIdentity> VerifyAsync(string provider, string token, CancellationToken ct)
    {
        if (provider is not ("google" or "kakao"))
            throw new ApiException(404, "provider_not_supported", "不支持的登录方式");
        if (string.IsNullOrWhiteSpace(token) || token.Length > 8192
            || token.Any(c => !char.IsAsciiLetterOrDigit(c) && !"-._~+/=".Contains(c)))
            throw new ApiException(400, "provider_token_required", "请重新进行第三方登录");
        if (!configuration.GetValue<bool>($"SocialLogin:{provider}:Enabled"))
            throw Unavailable();
        try
        {
            if (provider == "google")
            {
                var audience = configuration["SocialLogin:google:ClientId"];
                if (string.IsNullOrWhiteSpace(audience)) throw Unavailable();
                // Google's library verifies signature, issuer, audience and expiry.
                // Never accept a decoded-but-unverified JWT or a client profile ID.
                var payload = await GoogleJsonWebSignature.ValidateAsync(token,
                    new GoogleJsonWebSignature.ValidationSettings { Audience = [audience] });
                if (string.IsNullOrWhiteSpace(payload.Subject) || payload.Subject.Length > 255)
                    throw InvalidToken();
                return new(provider, payload.Subject);
            }

            if (!long.TryParse(configuration["SocialLogin:kakao:AppId"], out var expectedAppId)
                || expectedAppId <= 0) throw Unavailable();
            using var request = new HttpRequestMessage(HttpMethod.Get,
                "https://kapi.kakao.com/v1/user/access_token_info");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var response = await http.SendAsync(request, ct);
            if ((int)response.StatusCode >= 500) throw UpstreamUnavailable();
            if (!response.IsSuccessStatusCode) throw InvalidToken();
            using var body = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
            var root = body.RootElement;
            if (!ReadLong(root, "app_id", out var appId) || appId != expectedAppId
                || !ReadLong(root, "expires_in", out var seconds) || seconds <= 0
                || !ReadLong(root, "id", out var subject) || subject <= 0)
                throw InvalidToken();
            return new(provider, subject.ToString(CultureInfo.InvariantCulture));
        }
        catch (InvalidJwtException) { throw InvalidToken(); }
        catch (JsonException) { throw UpstreamUnavailable(); }
        catch (HttpRequestException) { throw UpstreamUnavailable(); }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested) { throw UpstreamUnavailable(); }
    }

    private static bool ReadLong(JsonElement root, string name, out long value)
    {
        value = default;
        return root.ValueKind == JsonValueKind.Object && root.TryGetProperty(name, out var element)
            && element.ValueKind == JsonValueKind.Number && element.TryGetInt64(out value);
    }

    private static ApiException Unavailable() => new(503, "social_login_unavailable", "该登录方式暂未开放，请使用邮箱登录");
    private static ApiException InvalidToken() => new(401, "invalid_provider_token", "第三方登录已失效，请重新登录");
    private static ApiException UpstreamUnavailable() => new(503, "provider_unavailable", "登录服务暂时不可用，请稍后重试");
}

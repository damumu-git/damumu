using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Muda.Api.Endpoints;
using Muda.Api.Infrastructure;
using Npgsql;

internal static class WebAuthChecks
{
    public static async Task RunAsync()
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddSingleton<IDataProtectionProvider, EphemeralDataProtectionProvider>();
        builder.Services.AddHttpClient(nameof(WebAuthEndpoints))
            .ConfigurePrimaryHttpMessageHandler(() => new KakaoFixture());
        builder.Services.AddSingleton(NpgsqlDataSource.Create("Host=127.0.0.1;Port=1;Database=unused"));
        builder.Services.AddSingleton<SocialAccountService>();
        builder.Services.AddSingleton<AuthService>();
        builder.Services.AddSingleton<MediaStorage>();
        builder.Configuration["Media:RootPath"] = Path.GetTempPath();
        builder.Configuration["Media:PublicBaseUrl"] = "https://api.damumu.com/uploads";
        builder.Configuration["Auth:TokenKey"] = "local-test-value-only-web-oauth-check";

        await using var app = builder.Build();
        app.Use(async (context, next) =>
        {
            try { await next(); }
            catch (ApiException error) { context.Response.StatusCode = error.StatusCode; }
        });
        app.MapGroup("/api/v1").MapWebAuthEndpoints();
        await app.StartAsync();
        using var client = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
        {
            BaseAddress = new Uri(app.Urls.Single())
        };
        const string path = "/api/v1/auth/web";
        using var initial = JsonDocument.Parse(await client.GetStringAsync(path + "/options"));
        var options = initial.RootElement.GetProperty("data");
        Check(!options.GetProperty("google").GetBoolean() && !options.GetProperty("kakao").GetBoolean(),
            "Providers should be unavailable before configuration");

        app.Configuration["WebSocialLogin:google:ClientId"] = "google-web-fixture";
        app.Configuration["WebSocialLogin:google:ClientSecret"] = "fixture-secret";
        app.Configuration["WebSocialLogin:kakao:ClientId"] = "kakao-web-fixture";
        app.Configuration["WebSocialLogin:kakao:ClientSecret"] = "fixture-secret";
        app.Configuration["SocialLogin:kakao:AppId"] = "1234";

        foreach (var (provider, expectedHost) in new[] { ("google", "accounts.google.com"), ("kakao", "kauth.kakao.com") })
        {
            using var start = await client.GetAsync($"{path}/{provider}/start");
            var url = start.Headers.Location!;
            var query = QueryHelpers.ParseQuery(url.Query);
            Check(start.StatusCode == HttpStatusCode.Redirect && url.Host == expectedHost &&
                query["redirect_uri"] == $"https://app.damumu.com{path}/{provider}/callback" &&
                query["state"].ToString().Length >= 40 && !query.ContainsKey("client_secret"),
                "Invalid authorization redirect");
            Check(provider != "google" || (query["code_challenge_method"] == "S256" &&
                query["code_challenge"].ToString().Length >= 40), "Google PKCE is required");
            var cookie = start.Headers.GetValues("Set-Cookie").Single(value => value.StartsWith("__Host-damu-oauth-state="));
            Check(cookie.Contains("httponly", StringComparison.OrdinalIgnoreCase) &&
                cookie.Contains("secure", StringComparison.OrdinalIgnoreCase) &&
                cookie.Contains("samesite=lax", StringComparison.OrdinalIgnoreCase), "Invalid OAuth state cookie");

            using var callback = new HttpRequestMessage(HttpMethod.Get,
                $"{path}/{provider}/callback?code=fake&state=wrong");
            callback.Headers.TryAddWithoutValidation("Cookie", cookie.Split(';')[0]);
            using var rejected = await client.SendAsync(callback);
            Check(rejected.Headers.Location?.OriginalString == "/#social-error" &&
                !rejected.Headers.Contains("Set-Cookie"), "Invalid state must stop before token exchange");
        }

        using var kakaoStart = await client.GetAsync(path + "/kakao/start");
        var kakaoState = QueryHelpers.ParseQuery(kakaoStart.Headers.Location!.Query)["state"].ToString();
        var kakaoCookie = kakaoStart.Headers.GetValues("Set-Cookie")
            .Single(value => value.StartsWith("__Host-damu-oauth-state="));
        using var kakaoCallback = new HttpRequestMessage(HttpMethod.Get,
            $"{path}/kakao/callback?code=fixture-code&state={kakaoState}");
        kakaoCallback.Headers.TryAddWithoutValidation("Cookie", kakaoCookie.Split(';')[0]);
        using var authorized = await client.SendAsync(kakaoCallback);
        Check(authorized.Headers.Location?.OriginalString == "/#social-complete" &&
            authorized.Headers.GetValues("Set-Cookie").Any(cookie =>
                cookie.StartsWith("__Host-damu-oauth-identity=") &&
                cookie.Contains("samesite=strict", StringComparison.OrdinalIgnoreCase) &&
                !cookie.Contains("fixture-access-token")),
            "Kakao callback must use a protected handoff cookie");

        using var complete = new HttpRequestMessage(HttpMethod.Post, path + "/complete")
        {
            Content = new StringContent("{}", Encoding.UTF8, "application/json")
        };
        complete.Headers.TryAddWithoutValidation("Origin", "https://unrelated.example");
        using var forbidden = await client.SendAsync(complete);
        Check(forbidden.StatusCode == HttpStatusCode.Forbidden, "Completion must enforce the web origin");
        Console.WriteLine("PASS: web OAuth configuration, redirects, state cookie, PKCE, mismatched state and origin");
    }

    private sealed class KakaoFixture : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (request.RequestUri?.AbsoluteUri == "https://kauth.kakao.com/oauth/token")
            {
                var form = await request.Content!.ReadAsStringAsync(cancellationToken);
                Check(request.Method == HttpMethod.Post && form.Contains("code=fixture-code") &&
                    form.Contains("client_secret=fixture-secret"), "Invalid Kakao token exchange");
                return Json("""{"access_token":"fixture-access-token"}""");
            }
            Check(request.RequestUri?.AbsoluteUri == "https://kapi.kakao.com/v1/user/access_token_info" &&
                request.Headers.Authorization?.Parameter == "fixture-access-token", "Invalid Kakao token validation");
            return Json("""{"app_id":1234,"id":42,"expires_in":900}""");
        }

        private static HttpResponseMessage Json(string value) => new(HttpStatusCode.OK)
        {
            Content = new StringContent(value, Encoding.UTF8, "application/json")
        };
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}

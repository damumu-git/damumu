using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Muda.Api.Endpoints;
using Muda.Api.Infrastructure;
using Npgsql;

internal static class SocialLoginChecks
{
    public static async Task VerifyTokens()
    {
        var settings = new Dictionary<string, string?>
        {
            ["SocialLogin:kakao:Enabled"] = "true", ["SocialLogin:kakao:AppId"] = "123",
            ["SocialLogin:google:Enabled"] = "true", ["SocialLogin:google:ClientId"] = "test-client",
        };
        foreach (var item in new[] {
            ("{\"id\":42,\"app_id\":123,\"expires_in\":3600}", 0),
            ("{\"id\":42,\"app_id\":999,\"expires_in\":3600}", 401),
            ("{\"id\":42,\"app_id\":123,\"expires_in\":0}", 401),
            ("{\"id\":-1,\"app_id\":123,\"expires_in\":3600}", 401),
            ("{\"id\":42}", 401), ("[]", 401),
            ("{\"id\":42,\"app_id\":\"123\",\"expires_in\":3600}", 401), ("not-json", 503),
        })
        {
            using var http = new HttpClient(new ReplyHandler(item.Item1));
            var verifier = new SocialIdentityVerifier(http, new ConfigurationBuilder().AddInMemoryCollection(settings).Build());
            if (item.Item2 == 0)
            {
                var identity = await verifier.VerifyAsync("kakao", "test-token", default);
                Check(identity == new SocialIdentity("kakao", "42"), "Verified Kakao identity incorrect");
            }
            else await Reject(() => verifier.VerifyAsync("kakao", "test-token", default), item.Item2);
        }
        using var client = new HttpClient(new ReplyHandler("{}"));
        var disabled = new SocialIdentityVerifier(client, new ConfigurationBuilder().Build());
        await Reject(() => disabled.VerifyAsync("google", "test", default), 503);
        await Reject(() => disabled.VerifyAsync("other", "test", default), 404);
        await Reject(() => disabled.VerifyAsync("kakao", "", default), 400);
        await Reject(() => disabled.VerifyAsync("kakao", "bad\r\nheader", default), 400);
        var configured = new SocialIdentityVerifier(client, new ConfigurationBuilder().AddInMemoryCollection(settings).Build());
        await Reject(() => configured.VerifyAsync("google", "not-a-jwt", default), 401);
        Console.WriteLine("PASS: disabled providers, invalid Google JWT, Kakao app/expiry/subject checks and safe malformed response");
    }

    public static async Task RunDatabase()
    {
        var cs = Environment.GetEnvironmentVariable("SOCIAL_LOGIN_TEST_DATABASE")
            ?? throw new Exception("SOCIAL_LOGIN_TEST_DATABASE is required");
        var parsed = new NpgsqlConnectionStringBuilder(cs);
        if (parsed.Host != "127.0.0.1" || parsed.Port != 55441 || parsed.Database != "social_login_check")
            throw new Exception("Only the isolated 127.0.0.1:55441/social_login_check database is allowed");
        await using var source = NpgsqlDataSource.Create(cs);
        var db = new Db(source);
        var root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../"));
        // Use the actual auth-related table definitions. PostGIS-dependent event
        // tables are intentionally outside this focused local integration check.
        var migrations = Path.Combine(root, "restapi/Migrations");
        var sql = string.Join("\n", Directory.GetFiles(migrations, "*.sql").Order().Select(File.ReadAllText));
        foreach (var table in new[] { "app_user", "user_profile", "system_avatar" })
        {
            var ddl = Regex.Match(sql, $@"CREATE TABLE IF NOT EXISTS {table} \([\s\S]*?\n\);").Value;
            Check(ddl.Length > 0, $"Missing table {table}");
            await db.ExecuteAsync(ddl);
        }
        await db.ExecuteAsync(File.ReadAllText(Path.Combine(migrations, "002_user_auth.sql")));
        await db.ExecuteAsync(File.ReadAllText(Path.Combine(migrations, "024_social_login.sql")));
        await db.ExecuteAsync(File.ReadAllText(Path.Combine(migrations, "024_social_login.sql")));
        await db.ExecuteAsync("ALTER TABLE app_user ADD COLUMN IF NOT EXISTS minimum_age_confirmed_at timestamptz; ALTER TABLE app_user ADD COLUMN IF NOT EXISTS privacy_notice_version varchar(32); ALTER TABLE app_user ADD COLUMN IF NOT EXISTS privacy_notice_acknowledged_at timestamptz;");
        // Never truncate a database; use unique fake provider subjects per run.
        var run = Guid.NewGuid().ToString("N");
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Configuration["Auth:TokenKey"] = "social-test-only-signing-key-at-least-32-characters";
        builder.Configuration["Media:RootPath"] = Path.Combine(root, ".dev-data/social-login-media");
        builder.Configuration["Media:PublicBaseUrl"] = "https://example.invalid/uploads";
        builder.Logging.ClearProviders();
        builder.Services.AddSingleton(source);
        builder.Services.AddSingleton<SocialAccountService>();
        builder.Services.AddSingleton<AuthService>();
        builder.Services.AddSingleton<MediaStorage>();
        builder.Services.AddSingleton<ISocialIdentityVerifier>(new TestVerifier(run));
        await using var app = builder.Build();
        app.Use(async (context, next) =>
        {
            try { await next(); }
            catch (ApiException error) { context.Response.StatusCode = error.StatusCode; }
        });
        app.MapGroup("/api/v1").MapSocialAuthEndpoints();
        await app.StartAsync();
        try
        {
            var uri = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
            using var http = new HttpClient { BaseAddress = new Uri(uri) };
            async Task<HttpResponseMessage> Send(string provider, string token, string? nickname = null,
                bool age = false, bool notice = false, string? version = null) =>
                await http.PostAsJsonAsync($"/api/v1/auth/social/{provider}", new {
                    token, nickname, ageConfirmed = age, privacyAcknowledged = notice, privacyVersion = version });
            async Task<Guid> UserId(HttpResponseMessage response)
            {
                Check(response.IsSuccessStatusCode, $"Unexpected status {response.StatusCode}");
                var json = await response.Content.ReadFromJsonAsync<JsonElement>();
                var data = json.GetProperty("data");
                var token = data.GetProperty("accessToken").GetString()!;
                Check(app.Services.GetRequiredService<AuthService>().TryValidateToken(token, out var id), "Invalid local session");
                Check(id == data.GetProperty("user").GetProperty("id").GetGuid(), "Session identity mismatch");
                Check(response.Headers.CacheControl?.NoStore == true, "Auth response can be cached");
                return id;
            }
            var start = await Send("google", "alpha");
            var pending = await start.Content.ReadFromJsonAsync<JsonElement>();
            Check(pending.GetProperty("data").GetProperty("registrationRequired").GetBoolean(), "Missing onboarding");
            Check(await db.ScalarAsync<int>("SELECT count(*) FROM user_external_identity WHERE subject LIKE @run", new { run = run + "%" }) == 0, "Created account before consent");
            Check((await Send("google", "alpha", "Test", false, true, PrivacyRules.NoticeVersion)).StatusCode == HttpStatusCode.BadRequest, "Age bypass");
            Check((await Send("google", "alpha", "Test", true, false, PrivacyRules.NoticeVersion)).StatusCode == HttpStatusCode.BadRequest, "Notice bypass");
            Check((await Send("google", "alpha", "Test", true, true, "old")).StatusCode == HttpStatusCode.BadRequest, "Policy version bypass");
            var created = await UserId(await Send("google", "alpha", "Test", true, true, PrivacyRules.NoticeVersion));
            Check(await UserId(await Send("google", "alpha")) == created, "Returning user duplicated");
            var kakao = await UserId(await Send("kakao", "alpha", "Test", true, true, PrivacyRules.NoticeVersion));
            Check(kakao != created, "Different providers silently linked");
            var concurrent = await Task.WhenAll(Enumerable.Range(0, 8).Select(async _ =>
                await UserId(await Send("google", "parallel", "Parallel", true, true, PrivacyRules.NoticeVersion))));
            Check(concurrent.Distinct().Count() == 1, "Concurrent sign-in duplicated identity");
            await db.ExecuteAsync("UPDATE app_user SET status='suspended' WHERE id=@created", new { created });
            Check((await Send("google", "alpha")).StatusCode == HttpStatusCode.Forbidden, "Suspended account signed in");
            await db.ExecuteAsync("UPDATE app_user SET status='deleted',deleted_at=now() WHERE id=@created", new { created });
            Check((await Send("google", "alpha")).StatusCode == HttpStatusCode.Forbidden, "Deleted account signed in");
            Console.WriteLine("PASS: real HTTP onboarding/consent/version, local sessions, repeat/concurrent login, provider separation, suspended/deleted rejection, idempotent 024");
        }
        finally { await app.StopAsync(); }
    }

    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static async Task Reject(Func<Task<SocialIdentity>> operation, int status)
    {
        try { await operation(); throw new Exception("Unsafe provider accepted"); }
        catch (ApiException error) { Check(error.StatusCode == status, $"Unexpected error {error.Code}"); }
    }
    private sealed class ReplyHandler(string body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Check(request.RequestUri?.AbsoluteUri == "https://kapi.kakao.com/v1/user/access_token_info", "Unexpected token destination");
            Check(request.Headers.Authorization?.ToString() == "Bearer test-token", "Token not sent in header");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) });
        }
    }
    private sealed class TestVerifier(string prefix) : ISocialIdentityVerifier
    {
        public Task<SocialIdentity> VerifyAsync(string provider, string token, CancellationToken ct) =>
            Task.FromResult(new SocialIdentity(provider, prefix + token));
    }
}

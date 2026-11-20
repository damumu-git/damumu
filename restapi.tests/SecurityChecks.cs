using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Json;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Configuration;
using Muda.Api.Infrastructure;
using Npgsql;

internal static class SecurityChecks
{
    public static async Task RunAsync()
    {
        var connection = Environment.GetEnvironmentVariable("SECURITY_TEST_CONNECTION")
            ?? throw new Exception("Set SECURITY_TEST_CONNECTION to an isolated security test database.");
        var cs = new NpgsqlConnectionStringBuilder(connection);
        if (cs.Host != "127.0.0.1" || cs.Database?.Contains("security_test") != true)
            throw new Exception("Security checks require a local database named *security_test*.");
        var url = Environment.GetEnvironmentVariable("SECURITY_TEST_URL") ?? "http://127.0.0.1:55446";
        var keys = Environment.GetEnvironmentVariable("SECURITY_TEST_KEYS")
            ?? throw new Exception("Set SECURITY_TEST_KEYS to the test API key directory.");
        await using var source = NpgsqlDataSource.Create(connection);
        var db = new Db(source);
        using var client = new HttpClient(new HttpClientHandler { UseCookies = false }) { BaseAddress = new Uri(url) };
        var ip = 0;
        async Task<(JsonElement Data, HttpResponseMessage Response)> Send(
            string method, string path, HttpStatusCode status, object? body = null,
            string? token = null, string? cookie = null, string host = "api.damumu.com",
            string? origin = null, bool csrf = false)
        {
            using var request = new HttpRequestMessage(new HttpMethod(method),
                path.StartsWith("/uploads/") ? path : "/api/v1" + path);
            request.Headers.Host = host;
            request.Headers.Add("X-Forwarded-For", "192.0.2." + (++ip % 250 + 1));
            if (token is not null) request.Headers.Add("Authorization", "Bearer " + token);
            if (cookie is not null) request.Headers.Add("Cookie", cookie);
            if (origin is not null) request.Headers.Add("Origin", origin);
            if (csrf) request.Headers.Add("X-Damu-CSRF", "1");
            if (body is not null) request.Content = JsonContent.Create(body);
            var response = await client.SendAsync(request);
            if (response.StatusCode != status)
                throw new Exception($"{method} {path}: expected {(int)status}, received {(int)response.StatusCode}");
            var text = await response.Content.ReadAsStringAsync();
            var data = text.Length == 0 ? default : JsonDocument.Parse(text).RootElement.GetProperty("data").Clone();
            return (data, response);
        }
        void Check(bool value, string label)
        {
            if (!value) throw new Exception(label);
            Console.WriteLine("PASS: " + label);
        }
        var run = Guid.NewGuid().ToString("N");
        object Registration(string name) => new
        {
            nickname = "Security " + name, email = $"{run}-{name}@example.invalid", password = "SecurityTestPassword123!",
            ageConfirmed = true, privacyAcknowledged = true, privacyVersion = PrivacyRules.NoticeVersion
        };
        var first = (await Send("POST", "/auth/register", HttpStatusCode.Created, Registration("first"))).Data;
        var second = (await Send("POST", "/auth/register", HttpStatusCode.Created, Registration("second"))).Data;
        var token = first.GetProperty("accessToken").GetString()!;
        var refresh = first.GetProperty("refreshToken").GetString()!;
        var userId = first.GetProperty("user").GetProperty("id").GetGuid();
        var otherToken = second.GetProperty("accessToken").GetString()!;
        var otherId = second.GetProperty("user").GetProperty("id").GetGuid();
        var sessions = (await Send("GET", "/me/sessions", HttpStatusCode.OK, token: token)).Data;
        var sessionId = sessions[0].GetProperty("id").GetGuid();
        await Send("DELETE", "/me/sessions/" + sessionId, HttpStatusCode.NoContent, token: otherToken);
        await Send("GET", "/me", HttpStatusCode.OK, token: token);
        Check(sessions[0].GetProperty("current").GetBoolean(), "session list identifies current login and cannot revoke another account");
        await Send("PATCH", "/me", HttpStatusCode.BadRequest,
            new { avatarUrl = "https://untrusted.invalid/track.jpg" }, token: token);
        await db.ExecuteAsync("UPDATE auth_session SET access_expires_at=now()-interval '1 second' WHERE user_id=@userId",
            new { userId });
        await Send("GET", "/me", HttpStatusCode.Unauthorized, token: token);
        var renewed = (await Send("POST", "/auth/refresh", HttpStatusCode.OK, new { refreshToken = refresh })).Data;
        var newToken = renewed.GetProperty("accessToken").GetString()!;
        var newRefresh = renewed.GetProperty("refreshToken").GetString()!;
        await Send("GET", "/me", HttpStatusCode.OK, token: newToken);
        Check(newToken != token && newRefresh != refresh, "expired access token refreshes with rotated credentials");
        await Send("POST", "/auth/logout-all", HttpStatusCode.NoContent, token: newToken);
        await Send("GET", "/me", HttpStatusCode.Unauthorized, token: newToken);
        await Send("POST", "/auth/refresh", HttpStatusCode.Unauthorized, new { refreshToken = newRefresh });
        Console.WriteLine("PASS: logout revokes access and refresh credentials");
        await Send("POST", "/auth/refresh", HttpStatusCode.OK,
            new { refreshToken = second.GetProperty("refreshToken").GetString() });
        await Send("GET", "/me", HttpStatusCode.OK, token: otherToken);
        Console.WriteLine("PASS: refresh preserves unexpired access for in-flight requests");
        var replay = (await Send("POST", "/auth/login", HttpStatusCode.OK,
            new { email = $"{run}-first@example.invalid", password = "SecurityTestPassword123!" })).Data;
        var staleRefresh = replay.GetProperty("refreshToken").GetString();
        var rotatedSession = (await Send("POST", "/auth/refresh", HttpStatusCode.OK,
            new { refreshToken = staleRefresh })).Data;
        await db.ExecuteAsync("UPDATE auth_session SET rotated_at=now()-interval '1 minute' WHERE user_id=@userId",
            new { userId });
        await Send("POST", "/auth/refresh", HttpStatusCode.Unauthorized, new { refreshToken = staleRefresh });
        await Send("GET", "/me", HttpStatusCode.Unauthorized, token: rotatedSession.GetProperty("accessToken").GetString());
        Console.WriteLine("PASS: refresh reuse beyond the retry window revokes that device");

        var web = await Send("POST", "/auth/register", HttpStatusCode.Created, Registration("web"),
            host: "www.damumu.com", origin: SessionSecurity.WebOrigin, csrf: true);
        var setCookie = web.Response.Headers.GetValues("Set-Cookie").Single(value => value.StartsWith(SessionSecurity.CookieName));
        var cookie = setCookie.Split(';')[0];
        Check(!web.Data.TryGetProperty("accessToken", out _) && setCookie.Contains("httponly", StringComparison.OrdinalIgnoreCase)
            && setCookie.Contains("secure", StringComparison.OrdinalIgnoreCase) && !setCookie.Contains("expires=", StringComparison.OrdinalIgnoreCase),
            "web login returns HttpOnly Secure session cookie without exposing a bearer token");
        await Send("GET", "/me", HttpStatusCode.OK, cookie: cookie, host: "www.damumu.com");
        await Send("POST", "/auth/logout", HttpStatusCode.Forbidden, cookie: cookie, host: "www.damumu.com",
            origin: "https://untrusted.invalid", csrf: true);
        await Send("POST", "/auth/logout", HttpStatusCode.NoContent, cookie: cookie, host: "www.damumu.com",
            origin: SessionSecurity.WebOrigin, csrf: true);
        await Send("GET", "/me", HttpStatusCode.Unauthorized, cookie: cookie, host: "www.damumu.com");
        Console.WriteLine("PASS: cross-origin cookie writes fail and web logout revokes the session");

        var eventId = Guid.NewGuid();
        await db.ExecuteAsync("""
            INSERT INTO event(id,organizer_user_id,category_id,title,description,status,capacity,approved_count,city_code)
            SELECT @eventId,@otherId,id,'Security test event','','published',8,1,'SEOUL' FROM category LIMIT 1;
            INSERT INTO event_schedule(event_id,starts_at,ends_at)
            VALUES(@eventId,now()+interval '1 day',now()+interval '1 day 1 hour');
            INSERT INTO event_member(event_id,user_id,status,member_role) VALUES(@eventId,@otherId,'approved','organizer');
            """, new { eventId, otherId });
        var anonymous = (await Send("GET", "/events/" + eventId, HttpStatusCode.OK)).Data;
        var approved = (await Send("GET", "/events/" + eventId, HttpStatusCode.OK, token: otherToken)).Data;
        Check(anonymous.GetProperty("members").GetArrayLength() == 0 && approved.GetProperty("members").GetArrayLength() > 0,
            "activity participant names require approved access");
        foreach (var path in new[] { "/emergency-contacts", "/safety-sessions/active" })
            await Send("GET", path, HttpStatusCode.NotFound);
        Console.WriteLine("PASS: retired safety APIs have no endpoints");
        var mediaRoot = Environment.GetEnvironmentVariable("SECURITY_TEST_MEDIA")
            ?? throw new Exception("Set SECURITY_TEST_MEDIA to the isolated API media directory.");
        var privateFile = Path.Combine(mediaRoot, "messages", "security-proof.png");
        await File.WriteAllBytesAsync(privateFile, [137, 80, 78, 71, 13, 10, 26, 10]);
        try
        {
            await Send("GET", "/uploads/messages/security-proof.png", HttpStatusCode.Unauthorized);
            await Send("GET", "/uploads//messages/security-proof.png", HttpStatusCode.NotFound);
            await Send("GET", "/uploads/messages%2Fsecurity-proof.png", HttpStatusCode.NotFound);
            Console.WriteLine("PASS: private media rejects path-normalization bypasses");
        }
        finally { File.Delete(privateFile); }

        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Auth:TokenKey"] = "isolated-security-tests-only-at-least-32-bytes"
        }).Build();
        var auth = new AuthService(configuration);
        var protection = DataProtectionProvider.Create(new DirectoryInfo(keys), builder => builder.SetApplicationName("DAMUMU"));
        var protector = protection.CreateProtector("damumu.admin.totp.v1");
        const string secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
        foreach (var role in new[] { "owner", "viewer" })
        {
            var username = role + run;
            await db.ExecuteAsync("""
                INSERT INTO admin_account(username,password_hash,totp_secret,role) VALUES(@username,@password,@secret,@role)
                """, new { username, password = auth.HashPassword("AdministratorTestPassword123!"), secret = protector.Protect(secret), role });
            var login = await Send("POST", "/admin-auth/login", HttpStatusCode.OK,
                new { username, password = "AdministratorTestPassword123!", code = Totp() },
                host: "admin.damumu.com", origin: SessionSecurity.AdminOrigin, csrf: true);
            var adminCookie = login.Response.Headers.GetValues("Set-Cookie")
                .Single(value => value.StartsWith(SessionSecurity.AdminCookie)).Split(';')[0];
            await Send("GET", "/admin/dashboard", HttpStatusCode.OK, cookie: adminCookie, host: "admin.damumu.com");
            await Send("POST", "/admin-auth/login", HttpStatusCode.Unauthorized,
                new { username, password = "AdministratorTestPassword123!", code = Totp() },
                host: "admin.damumu.com", origin: SessionSecurity.AdminOrigin, csrf: true);
            await Send("POST", "/admin/announcements", role == "owner" ? HttpStatusCode.OK : HttpStatusCode.Forbidden,
                new { title = "Security test", body = "Only test accounts in this isolated database." },
                cookie: adminCookie, host: "admin.damumu.com", origin: SessionSecurity.AdminOrigin, csrf: true);
            await Send("POST", "/admin-auth/logout", HttpStatusCode.NoContent, cookie: adminCookie,
                host: "admin.damumu.com", origin: SessionSecurity.AdminOrigin, csrf: true);
            await Send("GET", "/admin/dashboard", HttpStatusCode.Unauthorized, cookie: adminCookie, host: "admin.damumu.com");
        }
        var audits = await db.ScalarAsync<long>("SELECT count(*) FROM audit_log WHERE admin_account_id IS NOT NULL");
        Check(audits > 0, "admin MFA, replay prevention, role checks, logout and individual audit identity");
        using (var legacy = new HttpRequestMessage(HttpMethod.Get, "/api/v1/admin/dashboard"))
        {
            legacy.Headers.Host = "admin.damumu.com";
            legacy.Headers.Add("X-Admin-Key", "muda-admin-local");
            using var denied = await client.SendAsync(legacy);
            Check(denied.StatusCode == HttpStatusCode.Unauthorized, "legacy browser API key cannot authenticate an administrator");
        }
        for (var attempt = 0; attempt < 6; attempt++)
            await Send("POST", "/auth/login", attempt < 5 ? HttpStatusCode.Unauthorized : HttpStatusCode.TooManyRequests,
                new { email = run + "-unknown@example.invalid", password = "InvalidPassword123!" });
        Console.WriteLine("PASS: account login throttling survives changes of client IP");
        var rateLimited = false;
        for (var attempt = 0; attempt < 12; attempt++)
        {
            using var response = await client.GetAsync("/api/v1/health");
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                rateLimited = response.Headers.Contains("Retry-After");
                break;
            }
        }
        Check(rateLimited, "public health endpoint is rate limited and returns retry guidance");

        var banned = (await Send("POST", "/auth/login", HttpStatusCode.OK,
            new { email = $"{run}-second@example.invalid", password = "SecurityTestPassword123!" })).Data;
        using var socket = new ClientWebSocket();
        await socket.ConnectAsync(new Uri(url.Replace("http://", "ws://") + "/api/v1/realtime"), CancellationToken.None);
        var authenticate = JsonSerializer.SerializeToUtf8Bytes(new
        {
            type = "authenticate", token = banned.GetProperty("accessToken").GetString()
        });
        await socket.SendAsync(authenticate, WebSocketMessageType.Text, true, CancellationToken.None);
        var buffer = new byte[2048];
        using var socketTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(25));
        var connected = await socket.ReceiveAsync(buffer, socketTimeout.Token);
        Check(Encoding.UTF8.GetString(buffer, 0, connected.Count).Contains("connected"), "realtime authenticates a database-backed session");
        await db.ExecuteAsync("UPDATE app_user SET status='suspended' WHERE id=@otherId", new { otherId });
        await Send("POST", "/auth/refresh", HttpStatusCode.Unauthorized,
            new { refreshToken = banned.GetProperty("refreshToken").GetString() });
        await db.ExecuteAsync("UPDATE app_user SET status='active' WHERE id=@otherId", new { otherId });
        await Send("GET", "/me", HttpStatusCode.Unauthorized, token: otherToken);
        await Task.Delay(TimeSpan.FromSeconds(16));
        await socket.SendAsync(Encoding.UTF8.GetBytes("{\"type\":\"ping\"}"),
            WebSocketMessageType.Text, true, socketTimeout.Token);
        var closed = await socket.ReceiveAsync(buffer, socketTimeout.Token);
        Check(closed.MessageType == WebSocketMessageType.Close, "revoked realtime session is closed");
        await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "test_finished", socketTimeout.Token);
        Console.WriteLine("PASS: suspension permanently revokes existing sessions");
    }

    private static string Totp()
    {
        var counter = new byte[8];
        BinaryPrimitives.WriteInt64BigEndian(counter, DateTimeOffset.UtcNow.ToUnixTimeSeconds() / 30);
        var hash = HMACSHA1.HashData(Encoding.ASCII.GetBytes("12345678901234567890"), counter);
        var offset = hash[^1] & 15;
        return ((BinaryPrimitives.ReadInt32BigEndian(hash.AsSpan(offset, 4)) & 0x7fffffff) % 1000000).ToString("D6");
    }
}

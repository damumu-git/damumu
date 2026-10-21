using System.Net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Logging;
using Muda.Api.Infrastructure;
using Npgsql;

internal static class PrivacyChecks
{
    public static void ValidateRegistration()
    {
        foreach (var input in new[] { (false, true, PrivacyRules.NoticeVersion), (true, false, PrivacyRules.NoticeVersion), (true, true, "old") })
        {
            try { PrivacyRules.ValidateRegistration(input.Item1, input.Item2, input.Item3); throw new Exception("Registration confirmation bypassed"); }
            catch (ApiException exception) { Check(exception.StatusCode == 400, "Unsafe registration error"); }
        }
        PrivacyRules.ValidateRegistration(true, true, PrivacyRules.NoticeVersion);
        Console.WriteLine("PASS: age/notice confirmation and policy version are required");
    }

    public static async Task RunDatabase()
    {
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__Muda")
            ?? throw new Exception("ConnectionStrings__Muda is required");
        var settings = new NpgsqlConnectionStringBuilder(connectionString);
        if (settings.Database != "privacy_check" || settings.Host != "127.0.0.1")
            throw new Exception("Use only the isolated local privacy_check database");
        await using var source = NpgsqlDataSource.Create(connectionString);
        var db = new Db(source);
        var owner = Guid.NewGuid(); var member = Guid.NewGuid(); var outsider = Guid.NewGuid(); var deleting = Guid.NewGuid();
        var oldMedia = Guid.NewGuid(); var evidenceMedia = Guid.NewGuid(); var liveMedia = Guid.NewGuid();
        var oldEvent = Guid.NewGuid(); var futureEvent = Guid.NewGuid();
        var conversation = Guid.NewGuid();
        var oldKey = $"messages/{owner:N}/{oldMedia:N}.jpg";
        var evidenceKey = $"messages/{owner:N}/{evidenceMedia:N}.jpg";
        var liveKey = $"messages/{owner:N}/{liveMedia:N}.jpg";
        var root = Path.Combine(Path.GetTempPath(), $"damumu-privacy-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            await db.ExecuteAsync(
                """
                INSERT INTO app_user(id) SELECT unnest(@users);
                INSERT INTO user_profile(user_id,nickname) SELECT unnest(@users), 'privacy-check';
                INSERT INTO media_asset(id,owner_user_id,storage_key,mime_type,created_at)
                VALUES (@oldMedia,@owner,@oldKey,'image/jpeg',now()-interval '4 months'),
                       (@evidenceMedia,@owner,@evidenceKey,'image/jpeg',now()-interval '4 months'),
                       (@liveMedia,@owner,@liveKey,'image/jpeg',now()-interval '4 months');
                INSERT INTO conversation(id,conversation_type,direct_key) VALUES (@conversation,'direct',@directKey);
                INSERT INTO conversation_member(conversation_id,user_id) VALUES (@conversation,@owner),(@conversation,@member);
                INSERT INTO message(conversation_id,sender_user_id,media_asset_id,created_at)
                VALUES (@conversation,@owner,@oldMedia,now()-interval '4 months'),
                       (@conversation,@owner,@evidenceMedia,now()-interval '4 months'),
                       (@conversation,@owner,@liveMedia,now()-interval '1 day');
                WITH r AS (
                  INSERT INTO report(reporter_user_id,target_type,target_id,category_code)
                  VALUES (@member,'message',@evidenceMedia,'privacy_violation') RETURNING id
                ) INSERT INTO report_evidence(report_id,evidence_type,media_asset_id,snapshot)
                  SELECT id,'image',@evidenceMedia,'{"necessary":"evidence"}'::jsonb FROM r;
                WITH r AS (
                  INSERT INTO report(reporter_user_id,target_type,target_id,category_code,created_at)
                  VALUES (@member,'user',@owner,'privacy_violation',now()-interval '4 months') RETURNING id
                ) INSERT INTO report_evidence(report_id,evidence_type,snapshot) SELECT id,'text','{}'::jsonb FROM r;
                INSERT INTO event(id,organizer_user_id,category_id,title,description,capacity,city_code,status)
                  SELECT @oldEvent,@owner,id,'old event','private old description',5,'SEOUL','published'
                  FROM category WHERE level=2 LIMIT 1;
                INSERT INTO event_schedule(event_id,starts_at,ends_at)
                  VALUES (@oldEvent,now()-interval '4 months 1 day',now()-interval '4 months');
                INSERT INTO event(id,organizer_user_id,category_id,title,description,capacity,city_code,status,created_at)
                  SELECT @futureEvent,@owner,id,'future event','keep',5,'SEOUL','published',now()-interval '4 months'
                  FROM category WHERE level=2 LIMIT 1;
                INSERT INTO event_schedule(event_id,starts_at,ends_at)
                  VALUES (@futureEvent,now()+interval '1 day',now()+interval '2 days');
                """, new { users = new[] { owner, member, outsider, deleting }, owner, member,
                    oldMedia, evidenceMedia, liveMedia, oldKey, evidenceKey, liveKey,
                    conversation, directKey = Guid.NewGuid().ToString(), oldEvent, futureEvent });

            var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Development", ContentRootPath = root });
            builder.WebHost.UseUrls("http://127.0.0.1:0");
            builder.Configuration["Media:RootPath"] = Path.Combine(root, "uploads");
            builder.Configuration["Media:PublicBaseUrl"] = "https://api.example.test/uploads";
            builder.Configuration["Auth:TokenKey"] = "isolated-privacy-check-only-1234567890";
            builder.Services.AddSingleton(source);
            builder.Services.AddSingleton(db);
            builder.Services.AddSingleton<AuthService>();
            builder.Services.AddSingleton<MediaStorage>();
            await using var app = builder.Build();
            var media = app.Services.GetRequiredService<MediaStorage>();
            media.Initialize(Path.Combine(root, "no-presets"));
            foreach (var key in new[] { oldKey, evidenceKey, liveKey })
            {
                Directory.CreateDirectory(Path.GetDirectoryName(media.GetPath(key))!);
                await File.WriteAllTextAsync(media.GetPath(key), "privacy-check-image");
            }
            var avatar = media.GetPath($"avatars/{deleting:N}/test.jpg");
            Directory.CreateDirectory(Path.GetDirectoryName(avatar)!);
            await File.WriteAllTextAsync(avatar, "avatar");
            var deletion = new AccountDeletionService(source, media, app.Services.GetRequiredService<ILogger<AccountDeletionService>>());
            var result = await deletion.DeleteAsync(deleting, CancellationToken.None);
            Check(result?.AvatarFilesDeleted == true && !File.Exists(avatar), "Account avatar was not removed");
            var nickname = await db.ScalarAsync<string>("SELECT nickname FROM user_profile WHERE user_id=@deleting", new { deleting });
            Check(nickname?.StartsWith("注销用户_", StringComparison.Ordinal) == true, "Deleted-user number missing");
            await db.ExecuteAsync("UPDATE app_user SET deleted_at=now()-interval '4 months' WHERE id=@deleting", new { deleting });
            var retention = new PrivacyRetentionService(db, media, app.Services.GetRequiredService<ILogger<PrivacyRetentionService>>());
            await retention.RunOnceAsync(CancellationToken.None);
            await retention.RunOnceAsync(CancellationToken.None);
            Check(!File.Exists(media.GetPath(oldKey)), "Expired original file was retained");
            Check(File.Exists(media.GetPath(evidenceKey)), "Current report evidence was deleted");
            Check(await db.ScalarAsync<int>("SELECT count(*) FROM event WHERE id=@oldEvent", new { oldEvent }) == 0, "Expired event survived");
            Check(await db.ScalarAsync<int>("SELECT count(*) FROM event WHERE id=@futureEvent", new { futureEvent }) == 1, "Future event deleted based on creation time");
            Check(await db.ScalarAsync<int>("SELECT count(*) FROM app_user WHERE id=@deleting", new { deleting }) == 0, "Expired account tombstone survived");
            Check(await db.ScalarAsync<int>("SELECT count(*) FROM report WHERE reporter_user_id=@member", new { member }) == 1, "Report retention incorrect");
            Check(await db.ScalarAsync<int>("SELECT count(*) FROM message WHERE conversation_id=@conversation", new { conversation }) == 1, "Message retention incorrect");
            app.Use(async (context, next) =>
            {
                try { await next(); }
                catch (ApiException exception) { context.Response.StatusCode = exception.StatusCode; }
            });
            app.UseMiddleware<PrivateMediaMiddleware>();
            app.UseStaticFiles(new Microsoft.AspNetCore.Builder.StaticFileOptions
            {
                FileProvider = new PhysicalFileProvider(media.RootPath), RequestPath = "/uploads"
            });
            await app.StartAsync();
            try
            {
                var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
                using var client = new HttpClient { BaseAddress = new Uri(address) };
                var url = $"/uploads/{liveKey}";
                Check((await client.GetAsync(url)).StatusCode == HttpStatusCode.Unauthorized, "Anonymous private image read allowed");
                var auth = app.Services.GetRequiredService<AuthService>();
                client.DefaultRequestHeaders.Authorization = new("Bearer", auth.CreateToken(outsider));
                Check((await client.GetAsync(url)).StatusCode == HttpStatusCode.NotFound, "Non-member private image read allowed");
                client.DefaultRequestHeaders.Authorization = new("Bearer", auth.CreateToken(member));
                var allowed = await client.GetAsync(url);
                Check(allowed.StatusCode == HttpStatusCode.OK && allowed.Headers.CacheControl?.NoStore == true, "Member read or private cache policy failed");
                await db.ExecuteAsync("UPDATE conversation_member SET left_at=now() WHERE conversation_id=@conversation AND user_id=@member", new { conversation, member });
                Check((await client.GetAsync(url)).StatusCode == HttpStatusCode.NotFound, "Former member private image read allowed");
                await db.ExecuteAsync(
                    "UPDATE media_asset SET created_at=now() WHERE id=@liveMedia; UPDATE conversation_member SET left_at=now() WHERE conversation_id=@conversation AND user_id=@owner",
                    new { liveMedia, conversation, owner });
                client.DefaultRequestHeaders.Authorization = new("Bearer", auth.CreateToken(owner));
                Check((await client.GetAsync(url)).StatusCode == HttpStatusCode.NotFound, "Sent-image owner bypassed membership after leaving");
            }
            finally { await app.StopAsync(); }
            await db.ExecuteAsync(
                "UPDATE report SET created_at=now()-interval '4 months' WHERE id IN (SELECT report_id FROM report_evidence WHERE media_asset_id=@evidenceMedia)",
                new { evidenceMedia });
            await retention.RunOnceAsync(CancellationToken.None);
            Check(!File.Exists(media.GetPath(evidenceKey)), "Expired report evidence file survived");
            Console.WriteLine("PASS: real DB retention, report-evidence protection, future events, account deletion, file queue, idempotence, and private-image HTTP authorization");
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}

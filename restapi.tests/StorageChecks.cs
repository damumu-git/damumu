using System.Net;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Muda.Api;
using Muda.Api.Infrastructure;

internal static class StorageChecks
{
    public static async Task Validate()
    {
        var root = Path.Combine(Path.GetTempPath(), $"damumu-storage-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var builder = WebApplication.CreateBuilder(new WebApplicationOptions
            {
                EnvironmentName = "Development",
                ContentRootPath = root
            });
            builder.WebHost.UseUrls("http://127.0.0.1:0");
            builder.Configuration["Media:RootPath"] = Path.Combine(root, "external-storage");
            builder.Configuration["Media:PublicBaseUrl"] = "https://media.example.test/uploads/";
            builder.Services.AddSingleton<MediaStorage>();
            await using var app = builder.Build();
            var media = app.Services.GetRequiredService<MediaStorage>();
            var presets = Path.Combine(root, "presets");
            Directory.CreateDirectory(presets);
            await File.WriteAllBytesAsync(Path.Combine(presets, "test.jpg"), [0xff, 0xd8, 0xff, 0xd9]);
            media.Initialize(presets);
            var avatar = media.GetPath("system-avatars/test.jpg");
            Check(File.Exists(avatar), "Missing preset was not seeded");
            await File.WriteAllTextAsync(avatar, "operator-managed-file");
            media.Initialize(presets);
            Check(await File.ReadAllTextAsync(avatar) == "operator-managed-file", "Preset initialization overwrote an existing asset");

            foreach (var key in new[] { "../outside.jpg", "/outside.jpg", "events/../../outside", "events\\outside.jpg", "C:/outside.jpg", "events//file" })
            {
                try { media.GetPath(key); throw new Exception($"Unsafe key accepted: {key}"); }
                catch (ArgumentException) { }
            }
            var upload = media.GetPath("avatars/test/upload.jpg");
            Directory.CreateDirectory(Path.GetDirectoryName(upload)!);
            await File.WriteAllTextAsync(upload, "uploaded-file");
            Check(!File.Exists(Path.Combine(root, "uploads", "avatars", "test", "upload.jpg")), "Upload used the application's content directory");
            Check(media.ToStoredReference("https://media.example.test/uploads/avatars/test/upload.jpg") == "/uploads/avatars/test/upload.jpg", "Profile URL round trip is not portable");
            media.DeleteFile("avatars/test/upload.jpg");
            Check(!File.Exists(upload), "Delete did not use the external root");

            app.UseStaticFiles(new StaticFileOptions
            {
                FileProvider = new PhysicalFileProvider(media.RootPath),
                RequestPath = "/uploads"
            });
            object Payload() => new
            {
                items = new object[]
                {
                    new { image_url = "/uploads/system-avatars/test.jpg", name = "/uploads/this-is-text" },
                    new { coverUrl = "/uploads/events/test/thumb.webp", coverOriginalUrl = "/uploads/events/test/original.jpg" },
                    new { media_url = "/uploads/messages/test/image.jpg", media_thumbnail_url = "/uploads/messages/test/thumb.webp" },
                    new { avatarUrl = "system:test", avatarImageUrl = "/uploads/system-avatars/test.jpg" },
                    new { imageUrl = "https://cdn.example.test/existing.jpg" }
                }
            };
            app.MapGet("/test", () => ApiSupport.Ok(Payload(), new { total = 5 }));
            app.MapPost("/test", () => ApiSupport.Created("/api/v1/test/1", Payload()));
            await app.StartAsync();
            try
            {
                var address = app.Services.GetRequiredService<IServer>().Features
                    .Get<IServerAddressesFeature>()!.Addresses.Single();
                using var client = new HttpClient { BaseAddress = new Uri(address) };
                client.DefaultRequestHeaders.Add("X-Forwarded-Host", "spoofed.example.test");
                var response = await client.GetAsync("/test");
                var json = JsonNode.Parse(await response.Content.ReadAsStringAsync())!;
                Check(response.StatusCode == HttpStatusCode.OK && (int)json["meta"]!["total"]! == 5, "Response envelope or status changed");
                var items = json["data"]!["items"]!;
                Check((string?)items[0]!["image_url"] == "https://media.example.test/uploads/system-avatars/test.jpg", "Legacy avatar URL did not become a configured absolute URL");
                Check((string?)items[0]!["name"] == "/uploads/this-is-text", "Non-URL text was rewritten");
                Check((string?)items[1]!["coverUrl"] == "https://media.example.test/uploads/events/test/thumb.webp", "Cover thumbnail URL missing");
                Check((string?)items[1]!["coverOriginalUrl"] == "https://media.example.test/uploads/events/test/original.jpg", "Cover original URL missing");
                Check((string?)items[2]!["media_thumbnail_url"] == "https://media.example.test/uploads/messages/test/thumb.webp", "Chat URL missing");
                Check((string?)items[3]!["avatarUrl"] == "system:test", "System avatar identifier changed");
                Check((string?)items[4]!["imageUrl"] == "https://cdn.example.test/existing.jpg", "Existing absolute URL was prefixed twice");
                Check(!json.ToJsonString().Contains(root, StringComparison.Ordinal), "Filesystem root leaked in API response");
                var created = await client.PostAsync("/test", null);
                Check(created.StatusCode == HttpStatusCode.Created && created.Headers.Location?.OriginalString == "/api/v1/test/1", "Created status or Location was lost");
                var image = await client.GetAsync("/uploads/system-avatars/test.jpg");
                Check(image.StatusCode == HttpStatusCode.OK && await image.Content.ReadAsStringAsync() == "operator-managed-file", "Static reads did not use the mounted root");
                Check((await client.GetAsync("/api/v1/uploads/system-avatars/test.jpg")).StatusCode == HttpStatusCode.NotFound, "Incorrect API-prefixed image path unexpectedly resolved");
            }
            finally { await app.StopAsync(); }

            builder.Environment.EnvironmentName = "Production";
            foreach (var badUrl in new[] { "", "/uploads", "http://media.example.test/uploads", "https://user:password@media.example.test/uploads", "https://media.example.test/uploads?token=x" })
            {
                builder.Configuration["Media:PublicBaseUrl"] = badUrl;
                try { _ = new MediaStorage(builder.Configuration, builder.Environment); throw new Exception("Unsafe production URL accepted"); }
                catch (InvalidOperationException) { }
            }
            builder.Configuration["Media:PublicBaseUrl"] = "https://media.example.test/uploads";
            foreach (var badRoot in new[] { "", "relative/uploads" })
            {
                builder.Configuration["Media:RootPath"] = badRoot;
                try { _ = new MediaStorage(builder.Configuration, builder.Environment); throw new Exception("Unsafe production root accepted"); }
                catch (InvalidOperationException) { }
            }
            Console.WriteLine("PASS: external storage, preset seeding, safe paths, deletion, absolute media URLs, envelope/Created compatibility and live HTTP static reads");
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}

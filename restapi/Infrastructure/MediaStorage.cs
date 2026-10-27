using System.Text.Json.Nodes;

namespace Muda.Api.Infrastructure;

/// <summary>Disk locations are private; only configured HTTP URLs cross the API boundary.</summary>
public sealed class MediaStorage
{
    private static readonly HashSet<string> UrlFields = new(StringComparer.OrdinalIgnoreCase)
    {
        "imageUrl", "image_url", "avatarUrl", "avatar_url", "avatarImageUrl",
        "organizer_avatar", "sender_avatar", "coverUrl", "cover_url",
        "coverOriginalUrl", "cover_original_url", "mediaUrl", "media_url",
        "mediaThumbnailUrl", "media_thumbnail_url", "icon_url", "category_icon_url"
    };

    public string RootPath { get; }
    public string PublicBaseUrl { get; }

    public MediaStorage(IConfiguration configuration, IWebHostEnvironment environment)
    {
        var root = configuration["Media:RootPath"];
        if (string.IsNullOrWhiteSpace(root) && !environment.IsDevelopment())
            throw new InvalidOperationException("Media:RootPath is required outside Development.");
        if (!string.IsNullOrWhiteSpace(root) && !Path.IsPathFullyQualified(root))
            throw new InvalidOperationException("Media:RootPath must be an absolute filesystem path.");
        RootPath = Path.GetFullPath(string.IsNullOrWhiteSpace(root)
            ? Path.Combine(environment.ContentRootPath, "uploads") : root);

        var publicUrl = configuration["Media:PublicBaseUrl"];
        if (string.IsNullOrWhiteSpace(publicUrl) && environment.IsDevelopment())
            publicUrl = "http://localhost:8080/uploads";
        if (!Uri.TryCreate(publicUrl, UriKind.Absolute, out var uri)
            || uri.Scheme is not ("http" or "https")
            || !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query)
            || !string.IsNullOrEmpty(uri.Fragment)
            || (!environment.IsDevelopment() && uri.Scheme != "https"))
            throw new InvalidOperationException("Media:PublicBaseUrl must be an absolute public URL (HTTPS outside Development).");
        PublicBaseUrl = uri.AbsoluteUri.TrimEnd('/');
    }

    public string GetPath(string storageKey)
    {
        var segments = storageKey.Split('/');
        if (segments.Any(segment => string.IsNullOrWhiteSpace(segment)
                || segment is "." or ".." || segment.Contains('\\') || segment.Contains(':')))
            throw new ArgumentException("Invalid media storage key.", nameof(storageKey));
        var path = Path.GetFullPath(Path.Combine(RootPath, Path.Combine(segments)));
        if (!path.StartsWith(RootPath.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar,
                OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
            throw new ArgumentException("Media path must stay within the storage root.", nameof(storageKey));
        return path;
    }

    public string ToPublicUrl(string value) => value.StartsWith("/uploads/", StringComparison.Ordinal)
        ? $"{PublicBaseUrl}/{value[9..]}"
        : value;

    public string? ToStoredReference(string? value) => value?.StartsWith(PublicBaseUrl + "/", StringComparison.Ordinal) == true
        ? "/uploads/" + value[(PublicBaseUrl.Length + 1)..]
        : value;

    public void RewriteResponseUrls(JsonNode? node)
    {
        if (node is JsonObject obj)
        {
            foreach (var property in obj.ToArray())
            {
                if (UrlFields.Contains(property.Key) && property.Value is JsonValue value
                    && value.TryGetValue<string>(out var url))
                    obj[property.Key] = ToPublicUrl(url);
                else
                    RewriteResponseUrls(property.Value);
            }
        }
        else if (node is JsonArray array)
            foreach (var item in array) RewriteResponseUrls(item);
    }

    public void Initialize(string presetDirectory)
    {
        foreach (var directory in new[] { "avatars", "events", "messages", "system-avatars" })
            Directory.CreateDirectory(GetPath(directory));
        if (!Directory.Exists(presetDirectory)) return;
        foreach (var source in Directory.EnumerateFiles(presetDirectory, "*.jpg"))
        {
            var target = GetPath($"system-avatars/{Path.GetFileName(source)}");
            // Existing operator-managed assets and uploads must never be overwritten.
            if (!File.Exists(target)) File.Copy(source, target, overwrite: false);
        }
    }

    public void InitializeEmoji(string presetDirectory)
    {
        Directory.CreateDirectory(GetPath("emoji"));
        if (!Directory.Exists(presetDirectory)) return;
        foreach (var source in Directory.EnumerateFiles(presetDirectory, "*.png"))
        {
            var target = GetPath($"emoji/{Path.GetFileName(source)}");
            if (!File.Exists(target)) File.Copy(source, target, overwrite: false);
        }
    }

    public void DeleteFile(string? storageKey)
    {
        if (string.IsNullOrWhiteSpace(storageKey)) return;
        var path = GetPath(storageKey);
        if (File.Exists(path)) File.Delete(path);
    }

    public void DeleteAvatarDirectory(string storageKey)
    {
        var parts = storageKey.Split('/');
        if (parts.Length != 2 || parts[0] != "avatars" || !Guid.TryParseExact(parts[1], "N", out _))
            throw new ArgumentException("Only a user avatar directory may be removed.", nameof(storageKey));
        var path = GetPath(storageKey);
        if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
    }
}

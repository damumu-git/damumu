using Muda.Api.Infrastructure;
using SkiaSharp;
using System.Text.RegularExpressions;

namespace Muda.Api.Endpoints;

public static class EmojiAssetEndpoints
{
    public static RouteGroupBuilder MapEmojiAssetEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/emoji-assets", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync(
                "SELECT key, emoji, name, image_url, width, height FROM emoji_asset WHERE is_active ORDER BY key",
                cancellationToken: ct)));
        var admin = api.MapGroup("/admin/emoji-assets").RequireAdmin();
        admin.MapGet("", async (Db db, CancellationToken ct) =>
            ApiSupport.Ok(await db.QueryAsync("SELECT * FROM emoji_asset ORDER BY key", cancellationToken: ct)));
        admin.MapPost("", SaveImage).DisableAntiforgery();
        admin.MapPatch("/{key}", async (string key, EmojiAssetUpdate request, Db db, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.Name) || request.Name.Length > 100)
                throw new ApiException(400, "invalid_name", "名称须为1至100个字符");
            var row = await db.QueryOneAsync(
                """
                WITH changed AS (
                    UPDATE emoji_asset SET name=@name, is_active=@isActive, updated_at=now() WHERE key=@key RETURNING *
                ), logged AS (
                    INSERT INTO audit_log(actor_role,action,target_type,metadata)
                    SELECT 'admin','admin.emoji_asset.updated','emoji_asset',jsonb_build_object('key',key,'isActive',is_active)
                    FROM changed
                ) SELECT * FROM changed
                """,
                new { key, name = request.Name.Trim(), request.IsActive }, ct);
            if (row is null) throw new ApiException(404, "icon_not_found", "图标不存在");
            return ApiSupport.Ok(row);
        });
        return api;
    }

    private static async Task<IResult> SaveImage(HttpContext context, Db db, MediaStorage media, CancellationToken ct)
    {
        // Bounded, decoded PNG input only. Never accept SVG, arbitrary URLs or filenames.
        if (context.Request.ContentLength is > 300 * 1024)
            throw new ApiException(400, "image_too_large", "请求不能超过300KB");
        var bodyLimit = context.Features.Get<Microsoft.AspNetCore.Http.Features.IHttpMaxRequestBodySizeFeature>();
        if (bodyLimit is { IsReadOnly: false }) bodyLimit.MaxRequestBodySize = 300 * 1024;
        var form = await context.Request.ReadFormAsync(ct);
        var key = form["key"].ToString().Trim();
        var emoji = form["emoji"].ToString().Trim().Replace("\uFE0F", "").Replace("\uFE0E", "");
        var name = form["name"].ToString().Trim();
        if (!Regex.IsMatch(key, "^[a-z][a-z0-9-]{0,63}$") || emoji.Length is < 1 or > 32 || name.Length is < 1 or > 100)
            throw new ApiException(400, "invalid_icon", "资源键仅支持小写英文、数字及连字符；请填写Emoji与名称");
        var file = form.Files.GetFile("image") ?? throw new ApiException(400, "image_required", "请上传64×64 PNG");
        if (file.Length is < 1 or > 200 * 1024)
            throw new ApiException(400, "image_too_large", "PNG不能超过200KB");
        await using var stream = file.OpenReadStream();
        using var codec = SKCodec.Create(stream);
        if (codec is null || codec.EncodedFormat != SKEncodedImageFormat.Png || codec.FrameCount > 1
            || codec.Info.Width != 64 || codec.Info.Height != 64)
            throw new ApiException(400, "invalid_icon_image", "仅接受静态64×64 PNG");
        using var bitmap = SKBitmap.Decode(codec);
        if (bitmap is null) throw new ApiException(400, "invalid_icon_image", "PNG解码失败");
        using var image = SKImage.FromBitmap(bitmap);
        using var encoded = image.Encode(SKEncodedImageFormat.Png, 100)
            ?? throw new ApiException(400, "invalid_icon_image", "PNG编码失败");
        var stored = $"emoji/{key}-{Guid.NewGuid():N}.png";
        var path = media.GetPath(stored);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        await File.WriteAllBytesAsync(path, encoded.ToArray(), ct);
        try
        {
            // A key's Emoji identity is stable so old clients and categories keep their mapping.
            var row = await db.QueryOneAsync(
                """
                WITH saved AS (INSERT INTO emoji_asset(key,emoji,name,image_url,byte_size)
                VALUES(@key,@emoji,@name,@url,@size)
                ON CONFLICT(key) DO UPDATE SET name=EXCLUDED.name, image_url=EXCLUDED.image_url,
                    byte_size=EXCLUDED.byte_size, updated_at=now()
                WHERE emoji_asset.emoji=EXCLUDED.emoji
                RETURNING *), logged AS (
                    INSERT INTO audit_log(actor_role,action,target_type,metadata)
                    SELECT 'admin','admin.emoji_asset.saved','emoji_asset',jsonb_build_object('key',key,'imageUrl',image_url)
                    FROM saved
                ) SELECT * FROM saved
                """, new { key, emoji, name, url = "/uploads/" + stored, size = checked((int)encoded.Size) }, ct);
            if (row is null) throw new ApiException(409, "emoji_identity_conflict", "已有资源键的Emoji不能更改，请使用原Emoji或新资源键");
            return ApiSupport.Ok(row);
        }
        catch
        {
            File.Delete(path);
            throw;
        }
    }
}

public sealed record EmojiAssetUpdate(string Name, bool IsActive);

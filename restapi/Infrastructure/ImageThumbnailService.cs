using SkiaSharp;

namespace Muda.Api.Infrastructure;

public static class ImageThumbnailService
{
    public const long MaximumThumbnailBytes = 200 * 1024;

    public static async Task<ImageThumbnailResult> CreateWebpAsync(
        string sourcePath,
        string thumbnailPath,
        int maximumWidth,
        int maximumHeight,
        CancellationToken cancellationToken = default)
    {
        await using var metadataStream = File.OpenRead(sourcePath);
        using (var codec = SKCodec.Create(metadataStream)
            ?? throw new ApiException(400, "invalid_image", "图片文件无法解码"))
        {
            if (codec.FrameCount > 1)
                throw new ApiException(400, "animated_image_not_supported", "不支持动态图片或 Live Photo");
            if (codec.Info.Width > 6000 || codec.Info.Height > 6000)
                throw new ApiException(400, "image_dimensions_invalid", "图片尺寸过大");
        }

        using var source = SKBitmap.Decode(sourcePath)
            ?? throw new ApiException(400, "invalid_image", "图片文件无法解码");
        var scale = Math.Min(1d, Math.Min(
            (double)maximumWidth / source.Width,
            (double)maximumHeight / source.Height));
        var width = Math.Max(1, (int)Math.Round(source.Width * scale));
        var height = Math.Max(1, (int)Math.Round(source.Height * scale));
        using var resized = source.Resize(
            new SKImageInfo(width, height, SKColorType.Rgba8888, SKAlphaType.Premul),
            new SKSamplingOptions(SKCubicResampler.Mitchell))
            ?? throw new ApiException(400, "thumbnail_failed", "无法生成图片缩略图");

        Directory.CreateDirectory(Path.GetDirectoryName(thumbnailPath)!);
        foreach (var quality in new[] { 70, 60, 50, 40 })
        {
            await EncodeWebpAsync(resized, thumbnailPath, quality, cancellationToken);
            var size = new FileInfo(thumbnailPath).Length;
            if (size <= MaximumThumbnailBytes)
                return new ImageThumbnailResult(size, resized.Width, resized.Height);
        }

        var fallbackScale = Math.Min(1d, Math.Min(480d / resized.Width, 480d / resized.Height));
        using var fallback = resized.Resize(
            new SKImageInfo(
                Math.Max(1, (int)Math.Round(resized.Width * fallbackScale)),
                Math.Max(1, (int)Math.Round(resized.Height * fallbackScale)),
                SKColorType.Rgba8888,
                SKAlphaType.Premul),
            new SKSamplingOptions(SKCubicResampler.Mitchell))
            ?? throw new ApiException(400, "thumbnail_failed", "无法生成图片缩略图");
        await EncodeWebpAsync(fallback, thumbnailPath, 40, cancellationToken);
        var finalSize = new FileInfo(thumbnailPath).Length;
        if (finalSize > MaximumThumbnailBytes)
            throw new ApiException(400, "thumbnail_too_large", "图片内容过于复杂，无法生成缩略图");
        return new ImageThumbnailResult(finalSize, fallback.Width, fallback.Height);
    }

    private static async Task EncodeWebpAsync(
        SKBitmap bitmap,
        string path,
        int quality,
        CancellationToken cancellationToken)
    {
        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Webp, quality)
            ?? throw new ApiException(400, "thumbnail_failed", "无法编码 WebP 缩略图");
        await using var output = File.Create(path);
        await data.AsStream().CopyToAsync(output, cancellationToken);
    }

    public static void DeleteStoredFile(string contentRoot, string? storageKey)
    {
        if (string.IsNullOrWhiteSpace(storageKey)) return;
        var uploadsRoot = Path.GetFullPath(Path.Combine(contentRoot, "uploads"));
        var relative = storageKey.Replace('/', Path.DirectorySeparatorChar);
        var path = Path.GetFullPath(Path.Combine(uploadsRoot, relative));
        if (!path.StartsWith(uploadsRoot + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase)) return;
        if (File.Exists(path)) File.Delete(path);
    }
}

public sealed record ImageThumbnailResult(long ByteSize, int Width, int Height);

using Muda.Api.Infrastructure;
using Npgsql;
using SkiaSharp;

internal static class MediaChecks
{
    public static async Task ValidateThumbnails()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"damumu-media-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        try
        {
            var sourcePath = Path.Combine(directory, "source.jpg");
            using (var bitmap = new SKBitmap(1280, 960))
            {
                for (var y = 0; y < bitmap.Height; y++)
                for (var x = 0; x < bitmap.Width; x++)
                    bitmap.SetPixel(x, y, new SKColor(
                        (byte)((x * 17 + y * 3) % 256),
                        (byte)((x * 5 + y * 11) % 256),
                        (byte)((x + y * 19) % 256)));
                using var image = SKImage.FromBitmap(bitmap);
                using var jpeg = image.Encode(SKEncodedImageFormat.Jpeg, 92);
                await using var output = File.Create(sourcePath);
                await jpeg.AsStream().CopyToAsync(output);
            }

            await ValidateSize(sourcePath, Path.Combine(directory, "event.webp"), 640, 480);
            await ValidateSize(sourcePath, Path.Combine(directory, "chat.webp"), 320, 320);
            Console.WriteLine("PASS: 640px/320px WebP thumbnails stay within 200 KB");
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    private static async Task ValidateSize(
        string sourcePath, string outputPath, int maximumWidth, int maximumHeight)
    {
        var result = await ImageThumbnailService.CreateWebpAsync(
            sourcePath, outputPath, maximumWidth, maximumHeight);
        if (result.ByteSize <= 0 || result.ByteSize > ImageThumbnailService.MaximumThumbnailBytes)
            throw new Exception("Thumbnail byte limit was not enforced");
        if (result.Width > maximumWidth || result.Height > maximumHeight)
            throw new Exception("Thumbnail dimension limit was not enforced");
        await using var input = File.OpenRead(outputPath);
        using var codec = SKCodec.Create(input);
        if (codec is null || codec.EncodedFormat != SKEncodedImageFormat.Webp)
            throw new Exception("Thumbnail was not encoded as WebP");
    }

    public static async Task RunMigration(string migrationPath, bool apply)
    {
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__Muda")
            ?? throw new Exception("ConnectionStrings__Muda is required");
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        var sql = await File.ReadAllTextAsync(Path.GetFullPath(migrationPath));
        sql = sql.Replace("BEGIN;", "", StringComparison.Ordinal)
            .Replace("COMMIT;", "", StringComparison.Ordinal);
        await using (var command = new NpgsqlCommand(sql, connection, transaction))
            await command.ExecuteNonQueryAsync();

        await using var verify = new NpgsqlCommand(
            """
            SELECT count(*)
            FROM information_schema.columns
            WHERE table_schema='public' AND table_name='media_asset'
              AND column_name IN (
                'thumbnail_storage_key', 'thumbnail_mime_type', 'thumbnail_byte_size',
                'thumbnail_width', 'thumbnail_height')
            """, connection, transaction);
        if (Convert.ToInt32(await verify.ExecuteScalarAsync()) != 5)
            throw new Exception("Media thumbnail columns were not created");

        if (apply)
        {
            await transaction.CommitAsync();
            Console.WriteLine("PASS: media thumbnail migration applied");
        }
        else
        {
            await transaction.RollbackAsync();
            Console.WriteLine("PASS: media thumbnail migration validated and rolled back");
        }
    }
}

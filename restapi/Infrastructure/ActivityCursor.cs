using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;

namespace Muda.Api.Infrastructure;

// The cursor pins one recommendation snapshot and every ordering key. It is a
// public position, never a credential; decoded values are always SQL parameters.
public sealed record ActivityCursor(
    DateTime AnchorAt,
    string? OriginRegionCode,
    int ScoreKey,
    int RegionRing,
    DateTime SortStartsAt,
    DateTime CreatedAt,
    Guid ActivityId)
{
    private sealed record Payload(
        int Version,
        DateTime AnchorAt,
        string? OriginRegionCode,
        int ScoreKey,
        int RegionRing,
        DateTime SortStartsAt,
        DateTime CreatedAt,
        Guid ActivityId);

    public static string Encode(ActivityCursor value) =>
        WebEncoders.Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new Payload(
            2, value.AnchorAt.ToUniversalTime(), value.OriginRegionCode,
            value.ScoreKey, value.RegionRing, value.SortStartsAt.ToUniversalTime(),
            value.CreatedAt.ToUniversalTime(), value.ActivityId)));

    public static ActivityCursor? Decode(string? cursor)
    {
        if (cursor is null) return null;
        if (cursor.Length is 0 or > 1024 || cursor.Any(c =>
                !char.IsAsciiLetterOrDigit(c) && c != '-' && c != '_'))
            throw InvalidCursor();
        try
        {
            var payload = JsonSerializer.Deserialize<Payload>(WebEncoders.Base64UrlDecode(cursor));
            if (payload is null || payload.Version != 2 || payload.ActivityId == Guid.Empty
                || payload.AnchorAt.Kind != DateTimeKind.Utc || payload.CreatedAt.Kind != DateTimeKind.Utc
                || payload.SortStartsAt.Kind != DateTimeKind.Utc
                || (payload.AnchorAt == DateTime.MinValue || payload.AnchorAt == DateTime.MaxValue)
                || (payload.CreatedAt == DateTime.MinValue || payload.CreatedAt == DateTime.MaxValue)
                || (payload.SortStartsAt == DateTime.MinValue || payload.SortStartsAt == DateTime.MaxValue)
                || payload.ScoreKey is < 0 or > 1000 || payload.RegionRing is < 0 or > 32767
                || payload.OriginRegionCode is { Length: > 32 })
                throw InvalidCursor();
            return new ActivityCursor(payload.AnchorAt, payload.OriginRegionCode, payload.ScoreKey,
                payload.RegionRing, payload.SortStartsAt, payload.CreatedAt, payload.ActivityId);
        }
        catch (Exception exception) when (exception is FormatException or JsonException or ArgumentException)
        {
            throw InvalidCursor();
        }
    }

    private static ApiException InvalidCursor() =>
        new(400, "invalid_cursor", "分页位置无效，请刷新后重试");
}

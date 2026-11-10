using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;

namespace Muda.Api.Infrastructure;

// A cursor is a public position, never an authorization credential. All decoded
// values are validated and passed as SQL parameters, never interpolated in SQL.
public sealed record ActivityCursor(DateTime CreatedAt, Guid ActivityId,
    bool Recommended = false, double? Distance = null, DateTime? Start = null)
{
    private sealed record Payload(int Version, DateTime CreatedAt, Guid ActivityId,
        double? Distance = null, DateTime? Start = null);

    public static string Encode(DateTime createdAt, Guid activityId,
        bool recommended = false, double? distance = null, DateTime? start = null) =>
        WebEncoders.Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(
            new Payload(recommended ? 2 : 1, createdAt.ToUniversalTime(), activityId,
                distance, start?.ToUniversalTime())));

    public static ActivityCursor? Decode(string? cursor)
    {
        if (cursor is null) return null;
        if (cursor.Length is 0 or > 512 || cursor.Any(c =>
                !char.IsAsciiLetterOrDigit(c) && c != '-' && c != '_'))
            throw InvalidCursor();
        try
        {
            var payload = JsonSerializer.Deserialize<Payload>(WebEncoders.Base64UrlDecode(cursor));
            if (payload is null || payload.Version is not (1 or 2) || payload.ActivityId == Guid.Empty
                || (payload.Version == 1 && (payload.Distance.HasValue || payload.Start.HasValue))
                || (payload.Distance is double distance && (!double.IsFinite(distance) || distance < 0))
                || (payload.Start is DateTime start && start.Kind != DateTimeKind.Utc)
                || payload.CreatedAt.Kind != DateTimeKind.Utc
                || payload.CreatedAt == DateTime.MinValue || payload.CreatedAt == DateTime.MaxValue)
                throw InvalidCursor();
            return new ActivityCursor(payload.CreatedAt, payload.ActivityId,
                payload.Version == 2, payload.Distance, payload.Start);
        }
        catch (Exception exception) when (exception is FormatException or JsonException or ArgumentException)
        {
            throw InvalidCursor();
        }
    }

    private static ApiException InvalidCursor() =>
        new(400, "invalid_cursor", "分页位置无效，请刷新后重试");
}

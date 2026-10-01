using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;

namespace Muda.Api.Infrastructure;

public sealed record MessageCursor(DateTime CreatedAt, Guid MessageId)
{
    private sealed record Payload(int Version, DateTime CreatedAt, Guid MessageId);

    public static string Encode(DateTime createdAt, Guid messageId) =>
        WebEncoders.Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(
            new Payload(1, createdAt.ToUniversalTime(), messageId)));

    public static MessageCursor? Decode(string? cursor)
    {
        if (cursor is null) return null;
        if (cursor.Length is 0 or > 512 || cursor.Any(c =>
                !char.IsAsciiLetterOrDigit(c) && c != '-' && c != '_'))
            throw InvalidCursor();
        try
        {
            var payload = JsonSerializer.Deserialize<Payload>(WebEncoders.Base64UrlDecode(cursor));
            if (payload is null || payload.Version != 1 || payload.MessageId == Guid.Empty
                || payload.CreatedAt.Kind != DateTimeKind.Utc
                || payload.CreatedAt == DateTime.MinValue || payload.CreatedAt == DateTime.MaxValue)
                throw InvalidCursor();
            return new(payload.CreatedAt, payload.MessageId);
        }
        catch (Exception exception) when (exception is FormatException or JsonException or ArgumentException)
        {
            throw InvalidCursor();
        }
    }

    private static ApiException InvalidCursor() =>
        new(400, "invalid_message_cursor", "消息分页位置无效，请刷新后重试");
}

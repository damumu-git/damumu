using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Muda.Api.Infrastructure;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var id = Guid.Parse("12345678-1234-1234-1234-123456789abc");
var timestamp = new DateTime(2026, 9, 11, 12, 30, 15, DateTimeKind.Utc).AddTicks(1234560);
var encoded = ActivityCursor.Encode(timestamp, id);
var decoded = ActivityCursor.Decode(encoded)!;
Check(decoded.CreatedAt == timestamp && decoded.ActivityId == id, "Cursor roundtrip lost precision");
Check(ActivityCursor.Decode(null) is null, "First page should have no cursor");
string Payload(int version, DateTime time, Guid key) => WebEncoders.Base64UrlEncode(
    JsonSerializer.SerializeToUtf8Bytes(new { Version = version, CreatedAt = time, ActivityId = key }));
foreach (var invalid in new[] { "", " ", "%%%", "a", new string('a', 513),
    WebEncoders.Base64UrlEncode("{}"u8.ToArray()), Payload(2, timestamp, id),
    Payload(1, timestamp, Guid.Empty), Payload(1, DateTime.SpecifyKind(timestamp, DateTimeKind.Unspecified), id) })
{
    try { ActivityCursor.Decode(invalid); throw new Exception("Invalid cursor accepted"); }
    catch (ApiException error) { Check(error.StatusCode == 400 && error.Code == "invalid_cursor", "Unsafe cursor error"); }
}
Console.WriteLine("PASS: cursor roundtrip, microsecond precision, malformed/oversized/version/UUID/time validation");

if (args.Length > 1) await DatabaseChecks.Run(args[1]);
if (args.Length == 0) return;
using var client = new HttpClient { BaseAddress = new Uri(args[0]) };
var seen = new HashSet<Guid>();
DateTime? previousTime = null;
string? previousId = null;
string? cursor = null;
var pages = 0;
do
{
    var response = await client.GetAsync("api/v1/activities?limit=2" +
        (cursor is null ? "" : "&cursor=" + Uri.EscapeDataString(cursor)));
    Check(response.IsSuccessStatusCode, $"API returned {(int)response.StatusCode}");
    using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
    var data = json.RootElement.GetProperty("data");
    var items = data.GetProperty("items");
    Check(items.GetArrayLength() <= 2, "API exceeded limit");
    foreach (var item in items.EnumerateArray())
    {
        var itemId = item.GetProperty("id").GetGuid();
        var created = item.GetProperty("created_at").GetDateTime();
        var key = itemId.ToString("N");
        Check(seen.Add(itemId), "Duplicate activity across pages");
        Check(previousTime is null || created < previousTime ||
            (created == previousTime && string.CompareOrdinal(key, previousId) < 0), "Incorrect keyset order");
        Check(item.GetProperty("place_name").ValueKind == JsonValueKind.Null &&
            item.GetProperty("address_public").ValueKind == JsonValueKind.Null, "Exact meeting point exposed");
        previousTime = created;
        previousId = key;
    }
    var hasMore = data.GetProperty("hasMore").GetBoolean();
    cursor = data.GetProperty("nextCursor").GetString();
    Check(hasMore == (cursor is not null), "Cursor/end mismatch");
    if (hasMore) Check(items.GetArrayLength() == 2, "Non-full intermediate page");
    pages++;
    Check(pages < 1000, "Pagination did not terminate");
} while (cursor is not null);
var bad = await client.GetAsync("api/v1/activities?cursor=invalid!");
Check((int)bad.StatusCode == 400, "Invalid cursor did not return 400");
Console.WriteLine($"PASS: live API {pages} pages / {seen.Count} activities, order, uniqueness, boundaries, privacy, invalid cursor");

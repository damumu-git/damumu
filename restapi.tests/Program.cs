using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Muda.Api.Infrastructure;

CancellationChecks.ValidateReasons();
FeedbackChecks.Validate();
if (args.FirstOrDefault() == "--thumbnail-check")
{
    await MediaChecks.ValidateThumbnails();
    return;
}
if (args.FirstOrDefault() is "--media-migration-check" or "--media-migration-apply")
{
    if (args.Length != 2) throw new Exception("Usage: --media-migration-check|--media-migration-apply <migration>");
    await MediaChecks.RunMigration(args[1], args[0] == "--media-migration-apply");
    return;
}
if (args.FirstOrDefault() == "--firebase-check")
{
    var configuration = new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Firebase:ProjectId"] = "damumu-app"
        })
        .Build();
    using var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
    var push = new PushNotificationService(
        configuration,
        loggerFactory.CreateLogger<PushNotificationService>());
    if (!push.IsConfigured) throw new Exception("Firebase Admin initialization failed");
    Console.WriteLine("PASS: Firebase Admin service account initialized for damumu-app");
    return;
}
if (args.FirstOrDefault() == "--chat-db")
{
    await ChatChecks.RunDatabase();
    return;
}
if (args.FirstOrDefault() is "--chat-migration-check" or "--chat-migration-apply")
{
    if (args.Length != 2) throw new Exception("Usage: --chat-migration-check|--chat-migration-apply <migration>");
    await ChatChecks.RunMigration(args[1], args[0] == "--chat-migration-apply");
    return;
}
if (args.FirstOrDefault() == "--feedback-db")
{
    if (args.Length != 3) throw new Exception("Usage: --feedback-db <settings> <migration>");
    await FeedbackChecks.ValidateMigration(args[1], args[2]);
    return;
}
if (args.FirstOrDefault() == "--cancellation-db")
{
    await CancellationChecks.RunDatabase();
    return;
}

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var id = Guid.Parse("12345678-1234-1234-1234-123456789abc");
var timestamp = new DateTime(2026, 9, 11, 12, 30, 15, DateTimeKind.Utc).AddTicks(1234560);
var cursorValue = new ActivityCursor(timestamp, "KR-11620", 875, 1, timestamp.AddDays(2), timestamp, id);
var encoded = ActivityCursor.Encode(cursorValue);
var decoded = ActivityCursor.Decode(encoded)!;
Check(decoded == cursorValue, "Cursor roundtrip lost ranking keys or precision");
Check(ActivityCursor.Decode(null) is null, "First page should have no cursor");
string Payload(int version, DateTime time, Guid key) => WebEncoders.Base64UrlEncode(
    JsonSerializer.SerializeToUtf8Bytes(new { Version = version, AnchorAt = time, OriginRegionCode = "KR-11620", ScoreKey = 1, RegionRing = 0, SortStartsAt = time, CreatedAt = time, ActivityId = key }));
foreach (var invalid in new[] { "", " ", "%%%", "a", new string('a', 1025),
    WebEncoders.Base64UrlEncode("{}"u8.ToArray()), Payload(1, timestamp, id),
    Payload(2, timestamp, Guid.Empty), Payload(2, DateTime.SpecifyKind(timestamp, DateTimeKind.Unspecified), id) })
{
    try { ActivityCursor.Decode(invalid); throw new Exception("Invalid cursor accepted"); }
    catch (ApiException error) { Check(error.StatusCode == 400 && error.Code == "invalid_cursor", "Unsafe cursor error"); }
}
Console.WriteLine("PASS: cursor roundtrip, microsecond precision, malformed/oversized/version/UUID/time validation");

Check(ActivityQueries.List.Contains("ST_DWithin", StringComparison.Ordinal), "Nearby candidate query must use ST_DWithin");
Check(!ActivityQueries.List.Contains("public_geo", StringComparison.Ordinal), "Recommendation query must not use exact activity coordinates");
Check(ActivityQueries.List.Contains("user_interest", StringComparison.Ordinal) && ActivityQueries.List.Contains("trust_score", StringComparison.Ordinal), "Recommendation factors are incomplete");
Console.WriteLine("PASS: recommendation query uses region geography and all ranking factors without exact activity coordinates");

var messageId = Guid.Parse("87654321-4321-4321-4321-cba987654321");
var messageCursor = MessageCursor.Encode(timestamp, messageId);
var decodedMessageCursor = MessageCursor.Decode(messageCursor)!;
Check(decodedMessageCursor.CreatedAt == timestamp && decodedMessageCursor.MessageId == messageId,
    "Message cursor roundtrip lost precision");
foreach (var invalid in new[] { "", "%%%", new string('a', 513),
    WebEncoders.Base64UrlEncode("{}"u8.ToArray()) })
{
    try { MessageCursor.Decode(invalid); throw new Exception("Invalid message cursor accepted"); }
    catch (ApiException error) { Check(error.StatusCode == 400 && error.Code == "invalid_message_cursor", "Unsafe message cursor error"); }
}
Console.WriteLine("PASS: message cursor roundtrip and malformed/oversized validation");

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

using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace Muda.Api.Infrastructure;

public static class ActivityLocalization
{
    internal const string SourceHash = "md5(jsonb_build_array(e.title,e.description,e.custom_subcategory)::text)";

    public static async Task AttachAsync(Db db, IReadOnlyList<Dictionary<string, object?>> activities, CancellationToken ct)
    {
        if (activities.Count == 0) return;
        var ids = activities.Select(row => (Guid)row["id"]!).Distinct().ToArray();
        var rows = await db.QueryAsync(
            $"""
            SELECT e.id, e.custom_subcategory, c.name_zh_cn, c.name_en_us, c.name_ko_kr,
                   t.language, t.title, t.description, t.custom_subcategory AS translated_category
            FROM event e JOIN category c ON c.id=e.category_id
            LEFT JOIN activity_translation t ON t.event_id=e.id
                AND t.source_hash={SourceHash} AND t.title IS NOT NULL
            WHERE e.id=ANY(@ids) AND e.deleted_at IS NULL
            """, new { ids }, ct);
        var byId = rows.ToLookup(row => (Guid)row["id"]!);
        foreach (var activity in activities)
        {
            var translations = byId[(Guid)activity["id"]!].ToArray();
            if (translations.Length == 0) continue;
            var category = translations[0];
            activity["category_names"] = new
            {
                zh = category["name_zh_cn"], en = category["name_en_us"], ko = category["name_ko_kr"]
            };
            activity["custom_subcategory"] = category["custom_subcategory"];
            activity["translations"] = translations
                .Where(row => row["language"] is string)
                .ToDictionary(row => (string)row["language"]!, row => new
                {
                    title = row["title"], description = row["description"], category = row["translated_category"]
                });
        }
    }
}

public sealed class ActivityTranslationWorker(
    Db db, IConfiguration configuration, IHttpClientFactory clients, ILogger<ActivityTranslationWorker> log)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!configuration.GetValue<bool>("ActivityTranslation:Enabled") ||
            !Uri.TryCreate(configuration["ActivityTranslation:Endpoint"], UriKind.Absolute, out var endpoint) ||
            endpoint.Scheme is not ("http" or "https"))
            return;

        using var client = clients.CreateClient(nameof(ActivityTranslationWorker));
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));
        do
        {
            try { await TranslateBatch(db, client, endpoint, stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception ex) { log.LogWarning("Activity translation batch failed ({Type})", ex.GetType().Name); }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    private async Task TranslateBatch(Db database, HttpClient client, Uri endpoint, CancellationToken ct)
    {
        var tasks = await database.QueryAsync(
            $"""
            WITH candidates AS (
                SELECT e.id, langs.language, {ActivityLocalization.SourceHash} AS source_hash,
                       e.title, e.description, e.custom_subcategory
                FROM event e CROSS JOIN (VALUES ('zh'), ('en'), ('ko')) langs(language)
                LEFT JOIN activity_translation t ON t.event_id=e.id AND t.language=langs.language
                WHERE e.deleted_at IS NULL AND e.visibility='public'
                  AND e.status IN ('published','full','completed')
                  AND (t.source_hash IS DISTINCT FROM {ActivityLocalization.SourceHash}
                       OR (t.title IS NULL AND t.retry_after<=now()))
                ORDER BY e.created_at DESC, e.id, langs.language LIMIT 9
            ), claimed AS (
                INSERT INTO activity_translation(event_id,language,source_hash,retry_after)
                SELECT id,language,source_hash,now()+interval '5 minutes' FROM candidates
                ON CONFLICT(event_id,language) DO UPDATE
                SET source_hash=excluded.source_hash, title=NULL, description=NULL, custom_subcategory=NULL,
                    retry_after=excluded.retry_after
                WHERE activity_translation.source_hash IS DISTINCT FROM excluded.source_hash
                   OR (activity_translation.title IS NULL AND activity_translation.retry_after<=now())
                RETURNING event_id,language,source_hash
            )
            SELECT c.* FROM candidates c JOIN claimed t
                ON t.event_id=c.id AND t.language=c.language AND t.source_hash=c.source_hash
            """, cancellationToken: ct);

        var failures = 0;
        foreach (var task in tasks)
        {
            try
            {
                var input = new[] { (string)task["title"]!, (string)task["description"]!, task["custom_subcategory"] as string };
                var language = (string)task["language"]!;
                var nonEmpty = input.Where(text => !string.IsNullOrWhiteSpace(text)).ToArray();
                var query = new Dictionary<string, object>
                {
                    ["q"] = nonEmpty, ["source"] = "auto", ["target"] = language, ["format"] = "text"
                };
                if (configuration["ActivityTranslation:ApiKey"] is { Length: > 0 } key) query["api_key"] = key;
                using var body = new StringContent(JsonSerializer.Serialize(query), Encoding.UTF8, "application/json");
                using var response = await client.PostAsync(endpoint, body, ct);
                response.EnsureSuccessStatusCode();
                using var payload = await response.Content.ReadFromJsonAsync<JsonDocument>(cancellationToken: ct);
                var translated = payload!.RootElement.GetProperty("translatedText")
                    .EnumerateArray().Select(value => value.GetString()).ToArray();
                if (translated.Length != nonEmpty.Length ||
                    translated.Any(string.IsNullOrWhiteSpace))
                    throw new InvalidDataException("Translation response is incomplete.");
                var index = 0;
                var values = input.Select(value => string.IsNullOrWhiteSpace(value) ? value : translated[index++]).ToArray();
                await database.ExecuteAsync(
                    """
                    UPDATE activity_translation t SET title=@title, description=@description,
                        custom_subcategory=@category
                    FROM event e
                    WHERE t.event_id=@eventId AND t.language=@language AND t.source_hash=@hash
                      AND e.id=t.event_id AND e.deleted_at IS NULL AND e.visibility='public'
                    """, new { eventId = (Guid)task["id"]!, language, hash = (string)task["source_hash"]!,
                        title = values[0], description = values[1], category = values[2] }, ct);
            }
            catch (Exception) when (!ct.IsCancellationRequested) { failures++; }
        }
        if (failures > 0) log.LogWarning("Activity translation unavailable for {Count} items; retry scheduled.", failures);
    }
}

using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;
using Muda.Api.Infrastructure;

internal static class DatabaseChecks
{
    public static async Task Run(string settingsPath)
    {
        var configuration = new ConfigurationBuilder().AddJsonFile(Path.GetFullPath(settingsPath)).AddEnvironmentVariables().Build();
        await using var connection = new NpgsqlConnection(configuration.GetConnectionString("Muda"));
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        async Task Execute(string sql)
        {
            await using var command = new NpgsqlCommand(sql, connection, transaction);
            await command.ExecuteNonQueryAsync();
        }
        // Session-local tables shadow every table used by the feed query. This
        // keeps the SQL check independent from, and isolated from, local data.
        foreach (var table in new[]
        {
            "event", "category", "app_user", "user_profile", "trust_snapshot",
            "place", "administrative_region", "event_schedule", "event_tag", "interest"
        })
        {
            await Execute($"CREATE TEMP TABLE {table} ON COMMIT DROP AS SELECT * FROM public.{table} WITH NO DATA");
        }
        var organizerId = Guid.Parse("10000000-0000-0000-0000-000000000001");
        var categoryId = Guid.Parse("20000000-0000-0000-0000-000000000001");
        await Execute($"INSERT INTO app_user (id) VALUES ('{organizerId}')");
        await Execute($"INSERT INTO category (id, name_zh_cn) VALUES ('{categoryId}', '测试')");
        var time = new DateTime(2026, 9, 11, 10, 0, 0, DateTimeKind.Utc).AddTicks(1234560);
        async Task Seed(int number, DateTime created)
        {
            await using var command = new NpgsqlCommand("""
                INSERT INTO event (
                    id, organizer_user_id, category_id, title, description,
                    status, visibility, created_at, deleted_at)
                VALUES (
                    @id, @organizerId, @categoryId, '分页测试', '临时测试数据',
                    'published', 'public', @created, NULL)
                """, connection, transaction);
            command.Parameters.AddWithValue("id", Guid.Parse($"00000000-0000-0000-0000-{number:D12}"));
            command.Parameters.AddWithValue("organizerId", organizerId);
            command.Parameters.AddWithValue("categoryId", categoryId);
            command.Parameters.AddWithValue("created", created);
            if (await command.ExecuteNonQueryAsync() != 1) throw new Exception("Could not create temporary SQL fixture");
        }
        foreach (var number in new[] { 1, 2, 3, 4, 5 }) await Seed(number, time);
        await Execute("CREATE INDEX ix_cursor_test ON event (created_at DESC, id DESC) WHERE deleted_at IS NULL AND visibility='public' AND status IN ('published', 'full')");
        async Task<List<ActivityCursor>> Read(ActivityCursor? cursor)
        {
            await using var command = new NpgsqlCommand(ActivityQueries.List, connection, transaction);
            foreach (var name in new[] { "city", "district", "q" }) command.Parameters.Add(name, NpgsqlDbType.Text).Value = DBNull.Value;
            command.Parameters.Add("categoryId", NpgsqlDbType.Uuid).Value = DBNull.Value;
            foreach (var name in new[] { "from", "to" }) command.Parameters.Add(name, NpgsqlDbType.TimestampTz).Value = DBNull.Value;
            command.Parameters.AddWithValue("hasGeo", false);
            command.Parameters.AddWithValue("latitude", 0d);
            command.Parameters.AddWithValue("longitude", 0d);
            command.Parameters.AddWithValue("radius", 10000);
            command.Parameters.AddWithValue("limit", 3); // pageSize + 1
            command.Parameters.AddWithValue("hasCursor", cursor is not null);
            command.Parameters.AddWithValue("cursorCreatedAt", cursor?.CreatedAt ?? DateTime.UnixEpoch);
            command.Parameters.AddWithValue("cursorActivityId", cursor?.ActivityId ?? Guid.Empty);
            var result = new List<ActivityCursor>();
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync()) result.Add(new(reader.GetDateTime(reader.GetOrdinal("created_at")), reader.GetGuid(reader.GetOrdinal("id"))));
            return result;
        }
        var first = await Read(null);
        if (first.Count != 3 || !first[0].ActivityId.ToString().EndsWith("000000000005")) throw new Exception("First page or UUID tie-break failed");
        var boundary = ActivityCursor.Decode(ActivityCursor.Encode(first[1].CreatedAt, first[1].ActivityId));
        await Seed(6, time.AddSeconds(1)); // Concurrent insert at the head.
        await Execute("DELETE FROM event WHERE id='00000000-0000-0000-0000-000000000004'"); // Deleted boundary remains usable.
        var second = await Read(boundary);
        if (second.Count != 3 || !second[0].ActivityId.ToString().EndsWith("000000000003") || !second[1].ActivityId.ToString().EndsWith("000000000002")) throw new Exception("Insert/delete shifted keyset page");
        var last = await Read(second[1]);
        if (last.Count != 1 || !last[0].ActivityId.ToString().EndsWith("000000000001")) throw new Exception("Final page failed");
        if ((await Read(last[0])).Count != 0) throw new Exception("Empty tail failed");
        await transaction.RollbackAsync();
        Console.WriteLine("PASS: actual feed SQL with temporary fixtures, timestamp ties, insertion/deletion between pages, limit+1, final/empty pages; rolled back");
    }
}

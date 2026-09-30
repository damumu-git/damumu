using Muda.Api.Infrastructure;
using Npgsql;

internal static class CancellationChecks
{
    public static void ValidateReasons()
    {
        if (EventCancellation.ValidateReason("  天气原因  ") != "天气原因")
            throw new Exception("Cancellation reason was not trimmed");
        foreach (var reason in new string?[] { null, "", " \n ", new('x', 501) })
        {
            try { EventCancellation.ValidateReason(reason); throw new Exception("Invalid reason accepted"); }
            catch (ApiException error) when (error.StatusCode == 400) { }
        }
        EventCancellation.ValidateReason(new string('x', 500));
        Console.WriteLine("PASS: cancellation reason validation and trimming");
    }

    public static async Task RunDatabase()
    {
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__Muda");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            var password = Environment.GetEnvironmentVariable("DAMUMU_POSTGRES_PASSWORD");
            if (string.IsNullOrEmpty(password)) throw new Exception("Database environment is required");
            connectionString = new NpgsqlConnectionStringBuilder
            {
                Host = Environment.GetEnvironmentVariable("DAMUMU_POSTGRES_HOST") ?? "100.66.109.44",
                Database = Environment.GetEnvironmentVariable("DAMUMU_POSTGRES_DATABASE") ?? "damumu",
                Username = Environment.GetEnvironmentVariable("DAMUMU_POSTGRES_USERNAME") ?? "postgres",
                Password = password, Timeout = 10
            }.ConnectionString;
        }
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        async Task Execute(string sql)
        {
            await using var command = new NpgsqlCommand(sql, connection, transaction);
            await command.ExecuteNonQueryAsync();
        }
        async Task Check(string sql, string failure)
        {
            await using var command = new NpgsqlCommand(sql, connection, transaction);
            if (!Equals(await command.ExecuteScalarAsync(), true)) throw new Exception(failure);
        }
        // Shadow real tables. No business rows are read or changed.
        await Execute("""
            CREATE TEMP TABLE event (id uuid PRIMARY KEY, organizer_user_id uuid, status text,
                cancelled_at timestamptz, cancellation_reason text, deleted_at timestamptz) ON COMMIT DROP;
            CREATE TEMP TABLE conversation (id uuid PRIMARY KEY, event_id uuid,
                conversation_type text, updated_at timestamptz) ON COMMIT DROP;
            CREATE TEMP TABLE message (id uuid DEFAULT gen_random_uuid(), conversation_id uuid,
                sender_user_id uuid, message_type text, body text) ON COMMIT DROP;
            CREATE TEMP TABLE conversation_member (conversation_id uuid, user_id uuid, left_at timestamptz) ON COMMIT DROP;
            CREATE TEMP TABLE notification (user_id uuid, notification_type text, title text, body text, data jsonb) ON COMMIT DROP;
            INSERT INTO event (id, organizer_user_id, status)
            VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','published');
            INSERT INTO conversation VALUES ('00000000-0000-0000-0000-000000000003',
                '00000000-0000-0000-0000-000000000001','event',NULL);
            INSERT INTO conversation_member VALUES
                ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002',NULL),
                ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004',NULL),
                ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000005',now());
            """);
        async Task<bool> Cancel(int user = 2)
        {
            await using var command = new NpgsqlCommand(EventCancellation.Sql, connection, transaction);
            command.Parameters.AddWithValue("id", Guid.Parse("00000000-0000-0000-0000-000000000001"));
            command.Parameters.AddWithValue("userId", Guid.Parse($"00000000-0000-0000-0000-{user:D12}"));
            command.Parameters.AddWithValue("reason", "天气原因\n改期再见");
            return await command.ExecuteScalarAsync() is not null;
        }
        if (await Cancel(4)) throw new Exception("Non-organizer cancelled an event");
        await Execute("UPDATE event SET status='completed'");
        if (await Cancel()) throw new Exception("Completed event was cancelled");
        await Execute("UPDATE event SET status='published', deleted_at=now()");
        if (await Cancel()) throw new Exception("Deleted event was cancelled");
        await Execute("UPDATE event SET deleted_at=NULL");
        // A failed notification insert must roll back the event and message too.
        await Execute("ALTER TABLE notification ADD CONSTRAINT simulate_failure CHECK (false); SAVEPOINT before_failure");
        try { await Cancel(); throw new Exception("Expected insert failure"); }
        catch (PostgresException error) when (error.SqlState == "23514") { }
        await Execute("ROLLBACK TO SAVEPOINT before_failure; ALTER TABLE notification DROP CONSTRAINT simulate_failure");
        await Check("SELECT status='published' AND cancelled_at IS NULL FROM event", "Cancellation leaked on notification failure");
        await Check("SELECT count(*)=0 FROM message", "Message leaked on notification failure");
        if (!await Cancel()) throw new Exception("Organizer cancellation failed");
        if (await Cancel()) throw new Exception("Repeated cancellation succeeded");
        await Check("SELECT status='cancelled' AND cancellation_reason=E'天气原因\n改期再见' FROM event", "Reason/status not persisted");
        await Check("SELECT count(*)=1 AND bool_and(sender_user_id IS NULL AND message_type='event_cancelled') FROM message", "Duplicate or incorrect group notice");
        await Check("SELECT count(*)=1 AND bool_and(title='活动取消' AND user_id='00000000-0000-0000-0000-000000000004') FROM notification", "Wrong notification recipients");
        await Check("SELECT updated_at IS NOT NULL FROM conversation", "Conversation order not updated");
        await transaction.RollbackAsync();
        Console.WriteLine("PASS: PostgreSQL cancellation authorization, closed/deleted events, atomic rollback, duplicate prevention, group notice and active recipients (temporary tables rolled back)");
    }
}

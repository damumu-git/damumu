using Npgsql;
using Muda.Api.Infrastructure;

internal static class ChatChecks
{
    public static async Task RunDatabase()
    {
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__Muda")
            ?? throw new Exception("ConnectionStrings__Muda is required");
        var schema = $"chat_test_{Guid.NewGuid():N}";
        var quoted = new NpgsqlCommandBuilder().QuoteIdentifier(schema);
        await using var admin = new NpgsqlConnection(connectionString);
        await admin.OpenAsync();
        try
        {
            await using (var setup = new NpgsqlCommand($"""
                CREATE SCHEMA {quoted};
                CREATE TABLE {quoted}.app_user (LIKE public.app_user INCLUDING ALL);
                CREATE TABLE {quoted}.conversation (LIKE public.conversation INCLUDING ALL);
                CREATE TABLE {quoted}.conversation_member (LIKE public.conversation_member INCLUDING ALL);
                CREATE TABLE {quoted}.media_asset (LIKE public.media_asset INCLUDING ALL);
                CREATE TABLE {quoted}.message (LIKE public.message INCLUDING ALL);
                CREATE TABLE {quoted}.notification (LIKE public.notification INCLUDING ALL);
                CREATE TABLE {quoted}.report (LIKE public.report INCLUDING ALL);
                CREATE TABLE {quoted}.report_evidence (LIKE public.report_evidence INCLUDING ALL);
                """, admin)) await setup.ExecuteNonQueryAsync();

            var builder = new NpgsqlConnectionStringBuilder(connectionString) { SearchPath = schema };
            await using var source = NpgsqlDataSource.Create(builder.ConnectionString);
            var db = new Db(source);
            var sender = Guid.NewGuid();
            var recipient = Guid.NewGuid();
            var conversation = Guid.NewGuid();
            await db.ExecuteAsync(
                """
                INSERT INTO app_user (id) VALUES (@sender), (@recipient);
                INSERT INTO conversation (id, conversation_type) VALUES (@conversation, 'direct');
                INSERT INTO conversation_member (conversation_id, user_id)
                VALUES (@conversation, @sender), (@conversation, @recipient);
                """, new { sender, recipient, conversation });

            var clientId = Guid.NewGuid();
            var first = await db.SendMessageAsync(conversation, sender, "text", "hello",
                null, null, clientId, CancellationToken.None);
            if (!first.Created || first.RecipientIds.Length != 2)
                throw new Exception("First transactional message send failed");
            var duplicate = await db.SendMessageAsync(conversation, sender, "text", "hello",
                null, null, clientId, CancellationToken.None);
            if (duplicate.Created || !Equals(first.Message["id"], duplicate.Message["id"]))
                throw new Exception("Idempotent message retry did not return the original message");
            if (await db.ScalarAsync<long>("SELECT count(*) FROM notification") != 1)
                throw new Exception("Idempotent retry duplicated notifications");

            var report = await db.ReportMessageAsync(conversation, (Guid)first.Message["id"]!,
                recipient, "spam", "test", CancellationToken.None);
            if (report["id"] is not Guid reportId ||
                await db.ScalarAsync<long>("SELECT count(*) FROM report_evidence WHERE report_id=@reportId",
                    new { reportId }) != 1)
                throw new Exception("Message report evidence snapshot was not stored");

            await db.ExecuteAsync("UPDATE conversation SET status='read_only' WHERE id=@conversation",
                new { conversation });
            try
            {
                await db.SendMessageAsync(conversation, sender, "text", "blocked", null, null,
                    Guid.NewGuid(), CancellationToken.None);
                throw new Exception("Read-only conversation accepted a message");
            }
            catch (ApiException exception) when (exception.Code == "conversation_read_only") { }

            Console.WriteLine("PASS: transactional send, idempotent retry, notification dedupe, report snapshot, read-only enforcement");
        }
        finally
        {
            await using var cleanup = new NpgsqlCommand($"DROP SCHEMA IF EXISTS {quoted} CASCADE", admin);
            await cleanup.ExecuteNonQueryAsync();
        }
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
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        await command.ExecuteNonQueryAsync();

        await using var verify = new NpgsqlCommand(
            """
            SELECT count(*)
            FROM information_schema.columns
            WHERE table_schema='public' AND table_name='conversation'
              AND column_name IN ('read_only_at','archived_at')
            """, connection, transaction);
        if (Convert.ToInt32(await verify.ExecuteScalarAsync()) != 2)
            throw new Exception("Chat lifecycle columns were not created");

        if (apply)
        {
            await transaction.CommitAsync();
            Console.WriteLine("PASS: chat reliability migration applied");
        }
        else
        {
            await transaction.RollbackAsync();
            Console.WriteLine("PASS: chat reliability migration validated and rolled back");
        }
    }
}

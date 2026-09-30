using Muda.Api.Infrastructure;
using Microsoft.Extensions.Configuration;
using Npgsql;

internal static class FeedbackChecks
{
    public static void Validate()
    {
        if (FeedbackPolicy.RiskSignalThreshold != 3)
            throw new Exception("Risk signal threshold changed unexpectedly");

        FeedbackPolicy.Validate("activity", "like", "newcomer_friendly", null);
        FeedbackPolicy.Validate("activity", "report", "unsafe_arrangement", "details");
        FeedbackPolicy.Validate("user", "like", "reliable", null);
        FeedbackPolicy.Validate("user", "report", "harassment", null);

        ExpectCode(() => FeedbackPolicy.Validate("activity", "like", "harassment", null),
            "invalid_feedback_tag");
        ExpectCode(() => FeedbackPolicy.Validate("user", "report", "not_a_tag", null),
            "invalid_feedback_tag");
        ExpectCode(() => FeedbackPolicy.Validate("venue", "like", "punctual", null),
            "invalid_feedback_target");
        ExpectCode(() => FeedbackPolicy.Validate("user", "star", "friendly", null),
            "invalid_feedback_type");
        ExpectCode(() => FeedbackPolicy.Validate("user", "report", "spam", new string('x', 501)),
            "feedback_description_too_long");

        Console.WriteLine("PASS: feedback targets, types, tag allowlists, description limit, risk threshold");
    }

    public static async Task ValidateMigration(string settingsPath, string migrationPath)
    {
        var configuration = new ConfigurationBuilder()
            .AddJsonFile(Path.GetFullPath(settingsPath))
            .AddEnvironmentVariables()
            .Build();
        await using var connection = new NpgsqlConnection(configuration.GetConnectionString("Muda"));
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        var sql = await File.ReadAllTextAsync(Path.GetFullPath(migrationPath));
        sql = sql.Replace("BEGIN;", "", StringComparison.Ordinal)
            .Replace("COMMIT;", "", StringComparison.Ordinal);
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        await command.ExecuteNonQueryAsync();
        await transaction.RollbackAsync();
        Console.WriteLine("PASS: feedback migration SQL applied inside a rolled-back transaction");
    }

    private static void ExpectCode(Action action, string code)
    {
        try
        {
            action();
            throw new Exception($"Expected {code}");
        }
        catch (ApiException error) when (error.Code == code)
        {
        }
    }
}

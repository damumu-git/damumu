using System.Diagnostics;
using System.Text.Json;
using System.Threading.Channels;
using Microsoft.AspNetCore.Routing;
using Npgsql;

namespace Muda.Api.Infrastructure;

public sealed class EventLog(Db db, ILogger<EventLog> logger) : BackgroundService
{
    private readonly Channel<Entry> _pending = Channel.CreateBounded<Entry>(new BoundedChannelOptions(1024)
    {
        SingleReader = true,
        FullMode = BoundedChannelFullMode.Wait
    });
    private long _dropped;
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };

    public void RecordRequest(HttpContext context, string traceId, int status, string code, Exception? exception = null)
    {
        // Persist route templates only. Raw paths and headers can contain private data.
        var route = (context.GetEndpoint() as RouteEndpoint)?.RoutePattern.RawText;
        var method = context.Request.Method is "GET" or "POST" or "PUT" or "PATCH" or "DELETE" or "HEAD" or "OPTIONS"
            ? context.Request.Method : null;
        var provider = route == "/api/v1/auth/social/{provider}" ? context.Request.RouteValues["provider"] as string : null;
        var source = provider is "google" or "kakao" ? $"auth.{provider}" : "http";
        Record(status >= 500 ? "error" : "warning", source, code, traceId, method, route, status, exception);
    }

    public void RecordService(LogLevel level, string category, EventId eventId, Exception? exception) =>
        Record(level >= LogLevel.Error ? "error" : "warning", category,
            eventId.Id == 0 ? "service_failure" : $"service_failure_{eventId.Id}",
            Activity.Current?.Id, null, null, null, exception);

    private void Record(string level, string source, string code, string? traceId, string? method,
        string? route, int? status, Exception? exception)
    {
        var site = exception?.TargetSite;
        var entry = new Entry(DateTime.UtcNow, level, Clip(source, 160)!, Clip(code, 80)!, Clip(traceId, 80),
            method, Clip(route, 200), status, Clip(exception?.GetType().FullName, 160),
            site is null ? null : Clip($"{site.DeclaringType?.FullName}.{site.Name}", 240),
            (exception as PostgresException)?.SqlState);
        if (!_pending.Writer.TryWrite(entry)) Interlocked.Increment(ref _dropped);
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken) =>
        Task.WhenAll(WriteAsync(stoppingToken), MaintainAsync(stoppingToken));

    private async Task WriteAsync(CancellationToken ct)
    {
        var batch = new List<Entry>(64);
        while (await _pending.Reader.WaitToReadAsync(ct))
        {
            while (batch.Count < 64 && _pending.Reader.TryRead(out var entry)) batch.Add(entry);
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(TimeSpan.FromSeconds(3));
                await db.ExecuteAsync(
                    """
                    INSERT INTO public.event_log (occurred_at, level, source, code, trace_id, http_method, route,
                        status_code, exception_type, fault_site, sql_state)
                    SELECT occurred_at, level, source, code, trace_id, http_method, route,
                        status_code, exception_type, fault_site, sql_state
                    FROM jsonb_to_recordset(@payload::jsonb) AS entry (occurred_at timestamptz, level text,
                        source text, code text, trace_id text, http_method text, route text,
                        status_code smallint, exception_type text, fault_site text, sql_state text)
                    """, new { payload = JsonSerializer.Serialize(batch, JsonOptions) }, timeout.Token);
            }
            catch (Exception exception) when (!ct.IsCancellationRequested)
            {
                logger.LogWarning("Event log database write failed ({FailureType}, {SqlState}); {Count} entries skipped",
                    exception.GetType().Name, (exception as PostgresException)?.SqlState, batch.Count);
                await Task.Delay(TimeSpan.FromSeconds(2), ct);
            }
            batch.Clear();
            var dropped = Interlocked.Exchange(ref _dropped, 0);
            if (dropped != 0) logger.LogWarning("Event log queue was full; {Count} entries skipped", dropped);
        }
    }

    private async Task MaintainAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(1));
        do
        {
            try
            {
                await db.ExecuteAsync("SELECT public.muda_maintain_event_log()", cancellationToken: ct);
            }
            catch (Exception exception) when (!ct.IsCancellationRequested)
            {
                logger.LogWarning("Event log partition maintenance failed ({FailureType}, {SqlState})",
                    exception.GetType().Name, (exception as PostgresException)?.SqlState);
            }
        } while (await timer.WaitForNextTickAsync(ct));
    }

    private static string? Clip(string? value, int size) => value?.Length > size ? value[..size] : value;

    private sealed record Entry(DateTime OccurredAt, string Level, string Source, string Code, string? TraceId,
        string? HttpMethod, string? Route, int? StatusCode, string? ExceptionType, string? FaultSite, string? SqlState);
}

public sealed class EventLogProvider(EventLog events) : ILoggerProvider
{
    public ILogger CreateLogger(string categoryName) => new ServiceLogger(events, categoryName);
    public void Dispose() { }

    private sealed class ServiceLogger(EventLog events, string category) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel level) => level is >= LogLevel.Warning and < LogLevel.None &&
            category != typeof(EventLog).FullName &&
            (category.StartsWith("Muda.Api.", StringComparison.Ordinal) || category == "EventCancellation");

        public void Log<TState>(LogLevel level, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            if (IsEnabled(level) && (level >= LogLevel.Error || exception is not null))
                events.RecordService(level, category, eventId, exception);
        }
    }
}

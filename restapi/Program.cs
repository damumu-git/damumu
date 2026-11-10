using Microsoft.AspNetCore.DataProtection;
using Activity = System.Diagnostics.Activity;
using Muda.Api;
using Muda.Api.Endpoints;
using Muda.Api.Infrastructure;
using Microsoft.Extensions.FileProviders;
using Microsoft.AspNetCore.Routing;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);
if (builder.Environment.IsDevelopment())
{
    // Machine-local settings are never published. Explicit environment/CLI
    // values retain precedence over this optional development-only file.
    builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true)
        .AddEnvironmentVariables().AddCommandLine(args);
}

var connectionString = builder.Configuration.GetConnectionString("Muda")
    ?? throw new InvalidOperationException("ConnectionStrings:Muda is required.");
builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddSingleton<Db>();
builder.Services.AddSingleton<EventLog>();
builder.Services.AddHostedService(services => services.GetRequiredService<EventLog>());
builder.Services.AddSingleton<MediaStorage>();
builder.Services.AddSingleton<AuthService>();
builder.Services.AddSingleton<SocialAccountService>();
// The OAuth callback query and authorization redirect contain one-time credentials.
builder.Logging.AddFilter("Microsoft.AspNetCore.Hosting.Diagnostics", LogLevel.Warning);
builder.Logging.AddFilter("Microsoft.AspNetCore.Http.Result.RedirectResult", LogLevel.Warning);
builder.Services.AddDataProtection();
builder.Services.AddHttpClient(nameof(WebAuthEndpoints), client => client.Timeout = TimeSpan.FromSeconds(10))
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
builder.Services.AddHttpClient<ISocialIdentityVerifier, SocialIdentityVerifier>(client =>
    client.Timeout = TimeSpan.FromSeconds(10))
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
builder.Services.AddSingleton<AccountDeletionService>();
builder.Services.AddSingleton<RealtimeConnectionManager>();
builder.Services.AddSingleton<PushNotificationService>();
builder.Services.AddHostedService<RealtimeRelayService>();
builder.Services.AddHostedService<ConversationLifecycleService>();
builder.Services.AddHostedService<PrivacyRetentionService>();
builder.Services.AddHttpClient(nameof(ActivityTranslationWorker), client => client.Timeout = TimeSpan.FromSeconds(12))
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
builder.Services.AddHostedService<ActivityTranslationWorker>();
builder.Services.AddOpenApi();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

var app = builder.Build();
var eventLog = app.Services.GetRequiredService<EventLog>();
app.Services.GetRequiredService<ILoggerFactory>().AddProvider(new EventLogProvider(eventLog));
var mediaStorage = app.Services.GetRequiredService<MediaStorage>();
mediaStorage.Initialize(Path.Combine(AppContext.BaseDirectory, "preset-avatars"));
mediaStorage.InitializeEmoji(Path.Combine(AppContext.BaseDirectory, "preset-emoji"));

app.Use(async (context, next) =>
{
    var traceId = Activity.Current?.Id ?? context.TraceIdentifier;
    context.Response.Headers["X-Trace-Id"] = traceId;
    try
    {
        await next();
        var status = context.Response.StatusCode;
        if (status >= 500 || (status is >= 400 and < 500 && context.GetEndpoint() is RouteEndpoint &&
            context.Request.Path.StartsWithSegments("/api/v1")))
            eventLog.RecordRequest(context, traceId, status, $"http_{status}");
    }
    catch (ApiException exception)
    {
        eventLog.RecordRequest(context, traceId, exception.StatusCode, exception.Code, exception);
        if (context.Response.HasStarted) throw;
        await WriteError(context, traceId, exception.StatusCode, exception.Code, exception.Message);
    }
    catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
    {
        eventLog.RecordRequest(context, traceId, 409, "conflict", exception);
        if (context.Response.HasStarted) throw;
        await WriteError(context, traceId, 409, "conflict", "数据已存在或发生状态冲突");
    }
    catch (BadHttpRequestException exception)
    {
        eventLog.RecordRequest(context, traceId, exception.StatusCode, "invalid_request", exception);
        if (context.Response.HasStarted) throw;
        await WriteError(context, traceId, exception.StatusCode, "invalid_request", "请求格式无效");
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
    catch (Exception exception)
    {
        eventLog.RecordRequest(context, traceId, 500, "internal_error", exception);
        app.Logger.LogError("Request {TraceId} failed ({FailureType}, {SqlState})",
            traceId, exception.GetType().FullName, (exception as PostgresException)?.SqlState);
        if (context.Response.HasStarted)
        {
            context.Abort();
            return;
        }
        await WriteError(context, traceId, 500, "internal_error", "请求失败，请稍后重试");
    }
});

app.Use(async (context, next) =>
{
    var authorization = context.Request.Headers.Authorization.FirstOrDefault();
    var token = authorization?.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) == true
        ? authorization[7..].Trim()
        : null;
    if (token is not null)
    {
        var auth = context.RequestServices.GetRequiredService<AuthService>();
        if (auth.TryValidateToken(token, out var userId))
        {
            var db = context.RequestServices.GetRequiredService<Db>();
            var active = await db.ScalarAsync<int>(
                """
                SELECT count(*) FROM app_user
                WHERE id=@userId AND status='active' AND deleted_at IS NULL
                """,
                new { userId },
                context.RequestAborted);
            if (active == 0)
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new
                {
                    data = (object?)null,
                    meta = (object?)null,
                    error = new { code = "account_unavailable", message = "账号已注销或不可用" },
                    traceId = Activity.Current?.Id ?? context.TraceIdentifier
                }, context.RequestAborted);
                return;
            }
        }
    }
    await next();
});

app.UseCors();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(20) });
app.UseMiddleware<PrivateMediaMiddleware>();
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(mediaStorage.RootPath),
    RequestPath = "/uploads",
    OnPrepareResponse = context =>
    {
        context.Context.Response.Headers.CacheControl = context.Context.Request.Path.StartsWithSegments(
            "/uploads/messages", StringComparison.OrdinalIgnoreCase) ||
            context.Context.Request.Path.StartsWithSegments("/uploads/events", StringComparison.OrdinalIgnoreCase)
            ? "private,no-store" : "public,max-age=31536000,immutable";
        context.Context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    }
});
app.MapOpenApi();

var api = app.MapGroup("/api/v1");
api.MapGet("/health", async (Db db, PushNotificationService push, CancellationToken ct) =>
{
    var databaseTime = await db.ScalarAsync<DateTime>("SELECT now()", cancellationToken: ct);
    return ApiSupport.Ok(new { status = "healthy", databaseTime, pushConfigured = push.IsConfigured });
});

api.MapCatalogEndpoints();
api.MapEmojiAssetEndpoints();
api.MapUserEndpoints();
api.MapSocialAuthEndpoints();
api.MapWebAuthEndpoints();
api.MapEventEndpoints();
api.MapActivityEndpoints();
api.MapSocialEndpoints();
api.MapSafetyEndpoints();
api.MapGovernanceEndpoints();
api.MapFeedbackEndpoints();
api.MapAdminEndpoints();
api.MapSuggestionEndpoints();
api.MapRealtimeEndpoints();

app.Run();

static async Task WriteError(HttpContext context, string traceId, int status, string code, string message)
{
    context.Response.StatusCode = status;
    await context.Response.WriteAsJsonAsync(new
    {
        data = (object?)null,
        meta = (object?)null,
        error = new { code, message },
        traceId
    }, context.RequestAborted);
}

public partial class Program;

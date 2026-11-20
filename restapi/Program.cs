using Microsoft.AspNetCore.DataProtection;
using System.Globalization;
using System.Threading.RateLimiting;
using Activity = System.Diagnostics.Activity;
using Muda.Api;
using Muda.Api.Endpoints;
using Muda.Api.Infrastructure;
using Microsoft.Extensions.FileProviders;
using Microsoft.AspNetCore.Routing;
using Npgsql;
using Microsoft.AspNetCore.HttpOverrides;
using System.Net;

var bootstrapAdmin = args.FirstOrDefault() == "--create-admin";
var builder = WebApplication.CreateBuilder(bootstrapAdmin ? [] : args);
if (builder.Environment.IsDevelopment())
{
    // Machine-local settings are never published. Explicit environment/CLI
    // values retain precedence over this optional development-only file.
    builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true)
        .AddEnvironmentVariables().AddCommandLine(bootstrapAdmin ? [] : args);
}

var connectionString = builder.Configuration.GetConnectionString("Muda")
    ?? throw new InvalidOperationException("ConnectionStrings:Muda is required.");
if (!builder.Environment.IsDevelopment() && ((builder.Configuration["Auth:TokenKey"]?.Length ?? 0) < 32 ||
    builder.Configuration["Auth:TokenKey"]!.StartsWith("replace-", StringComparison.OrdinalIgnoreCase) ||
    connectionString.Contains("configure-via-user-secrets", StringComparison.Ordinal)))
    throw new InvalidOperationException("Production requires an explicit database connection and a non-placeholder Auth:TokenKey of at least 32 characters.");
builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddSingleton<Db>();
builder.Services.AddSingleton<ContentFilter>();
builder.Services.AddSingleton<EventLog>();
builder.Services.AddHostedService(services => services.GetRequiredService<EventLog>());
builder.Services.AddSingleton<MediaStorage>();
builder.Services.AddSingleton<AuthService>();
builder.Services.AddSingleton<SessionSecurity>();
builder.Services.AddSingleton<AdminSecurity>();
builder.Services.AddSingleton<SocialAccountService>();
// The OAuth callback query and authorization redirect contain one-time credentials.
builder.Logging.AddFilter("Microsoft.AspNetCore.Hosting.Diagnostics", LogLevel.Warning);
builder.Logging.AddFilter("Microsoft.AspNetCore.Http.Result.RedirectResult", LogLevel.Warning);
var keyDirectory = builder.Configuration["Security:KeyDirectory"];
if (!builder.Environment.IsDevelopment() && string.IsNullOrWhiteSpace(keyDirectory))
    throw new InvalidOperationException("Security:KeyDirectory is required in Production.");
var protection = builder.Services.AddDataProtection().SetApplicationName("DAMUMU");
if (!string.IsNullOrWhiteSpace(keyDirectory))
{
    Directory.CreateDirectory(keyDirectory);
    protection.PersistKeysToFileSystem(new DirectoryInfo(keyDirectory));
}
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.ForwardLimit = 1;
    options.KnownProxies.Add(IPAddress.Parse("172.30.0.1"));
});
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 3 * 1024 * 1024;
    options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(15);
    options.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(60);
});
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
builder.Services.AddHostedService<RecurringEventReminderService>();
builder.Services.AddHttpClient(nameof(ActivityTranslationWorker), client => client.Timeout = TimeSpan.FromSeconds(12))
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
builder.Services.AddHostedService<ActivityTranslationWorker>();
builder.Services.AddOpenApi();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.WithOrigins(SessionSecurity.WebOrigin, SessionSecurity.AdminOrigin)
            .AllowAnyHeader().AllowAnyMethod().WithExposedHeaders("Retry-After");
        if (builder.Environment.IsDevelopment())
            policy.WithOrigins("http://localhost:5173", "http://127.0.0.1:5173",
                "http://localhost:3000", "http://127.0.0.1:3000").AllowCredentials();
    });
});
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.CreateChained(NetworkRateLimits.Create(), AccountRateLimits.Create());
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.OnRejected = async (rejection, _) =>
    {
        var context = rejection.HttpContext;
        var seconds = rejection.Lease.TryGetMetadata(MetadataName.RetryAfter, out var delay)
            ? Math.Max(1, Math.Ceiling(delay.TotalSeconds)) : 1;
        context.Response.Headers.RetryAfter = seconds.ToString(CultureInfo.InvariantCulture);
        context.Response.Headers.CacheControl = "no-store";
        await WriteError(context, Activity.Current?.Id ?? context.TraceIdentifier,
            StatusCodes.Status429TooManyRequests, "rate_limited", "操作过于频繁，请稍后再试");
    };
});

var app = builder.Build();
if (bootstrapAdmin)
{
    await app.Services.GetRequiredService<AdminSecurity>().BootstrapAsync(
        args.ElementAtOrDefault(1) ?? "", args.ElementAtOrDefault(2) ?? "owner", CancellationToken.None);
    return;
}
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
        if (status >= 500 || (status is >= 400 and < 500 and not 429 && context.GetEndpoint() is RouteEndpoint &&
            context.Request.Path.StartsWithSegments("/api/v1")))
            eventLog.RecordRequest(context, traceId, status, $"http_{status}");
    }
    catch (ApiException exception)
    {
        eventLog.RecordRequest(context, traceId, exception.StatusCode, exception.Code, exception);
        if (context.Response.HasStarted) throw;
        await WriteError(context, traceId, exception.StatusCode, exception.Code, exception.Message);
    }
    catch (PostgresException exception) when (exception.SqlState is
        PostgresErrorCodes.SerializationFailure or PostgresErrorCodes.DeadlockDetected)
    {
        eventLog.RecordRequest(context, traceId, 409, "state_changed", exception);
        if (context.Response.HasStarted) throw;
        await WriteError(context, traceId, 409, "state_changed", "参与状态已发生变化，请刷新后重试。");
    }
    catch (PostgresException exception) when (exception.ConstraintName == "event_schedule_conflict")
    {
        eventLog.RecordRequest(context, traceId, 409, "schedule_conflict", exception);
        if (context.Response.HasStarted) throw;
        await WriteError(context, traceId, 409, "schedule_conflict", "此时间与你已确定的活动重叠，请先处理已有行程。");
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

app.UseForwardedHeaders();
app.UseRouting();
app.UseCors();
var uploadSlots = new SemaphoreSlim(2);
var loginSlots = new SemaphoreSlim(4);
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    var path = context.Request.Path;
    var authPath = path.StartsWithSegments("/api/v1/auth") || path.StartsWithSegments("/api/v1/admin-auth");
    if (authPath && context.Features.Get<Microsoft.AspNetCore.Http.Features.IHttpMaxRequestBodySizeFeature>() is { IsReadOnly: false } bodyLimit)
        bodyLimit.MaxRequestBodySize = 16 * 1024;
    var adminPath = path.StartsWithSegments("/api/v1/admin") || path.StartsWithSegments("/api/v1/admin-auth");
    var webHost = context.Request.Host.Host == "www.damumu.com";
    if (adminPath && !app.Environment.IsDevelopment() && context.Request.Host.Host != "admin.damumu.com")
        throw new ApiException(404, "not_found", "页面不存在");
    if (context.Request.Method is not ("GET" or "HEAD" or "OPTIONS") &&
        (adminPath || webHost && (context.Request.Cookies.ContainsKey(SessionSecurity.CookieName) ||
                                  path.StartsWithSegments("/api/v1/auth"))))
    {
        var expected = adminPath ? SessionSecurity.AdminOrigin : SessionSecurity.WebOrigin;
        var origin = context.Request.Headers.Origin.ToString();
        var localAdmin = app.Environment.IsDevelopment() && adminPath
            && origin is "http://localhost:5173" or "http://127.0.0.1:5173";
        if ((!localAdmin && origin != expected) || context.Request.Headers["X-Damu-CSRF"] != "1")
            throw new ApiException(403, "invalid_origin", "请求来源无效");
    }
    var token = SessionSecurity.RequestToken(context);
    if (token is not null)
    {
        var sessions = context.RequestServices.GetRequiredService<SessionSecurity>();
        var userId = await sessions.ValidateAsync(token, context.RequestAborted);
        if (!userId.HasValue)
        {
            if (!context.Request.Headers.Authorization.ToString().StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
                )
                context.Response.Cookies.Delete(SessionSecurity.CookieName, SessionSecurity.Cookie());
            else throw new ApiException(401, "session_expired", "登录已失效，请重新登录");
        }
        else
        {
            ApiSupport.SetValidatedUser(context, userId);
            context.Response.Headers.CacheControl = "private,no-store";
        }
    }
    if (path.StartsWithSegments("/api/v1/auth") || adminPath)
        context.Response.Headers.CacheControl = "no-store";
    if (authPath && context.Request.Method == "POST")
    {
        if (!await loginSlots.WaitAsync(0, context.RequestAborted))
            throw new ApiException(429, "login_busy", "登录服务繁忙，请稍后再试");
        try { await next(); }
        finally { loginSlots.Release(); }
    }
    else if (context.Request.ContentType?.StartsWith("multipart/form-data", StringComparison.OrdinalIgnoreCase) == true)
    {
        if (!await uploadSlots.WaitAsync(0, context.RequestAborted))
            throw new ApiException(429, "upload_busy", "图片处理繁忙，请稍后再试");
        try { await next(); }
        finally { uploadSlots.Release(); }
    }
    else await next();
});
app.UseRateLimiter();

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
            context.Context.Request.Path.StartsWithSegments("/uploads/events", StringComparison.OrdinalIgnoreCase) ||
            context.Context.Request.Path.StartsWithSegments("/uploads/groups", StringComparison.OrdinalIgnoreCase)
            ? "private,no-store" : "public,max-age=31536000,immutable";
        context.Context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    }
});
if (app.Environment.IsDevelopment()) app.MapOpenApi();

var api = app.MapGroup("/api/v1");
api.AddEndpointFilter(ContentFilter.Inspect);
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
api.MapWebGuideEndpoints();
api.MapWebMemberEndpoints();
api.MapWebCommunityEndpoints();
api.MapEventEndpoints();
api.MapActivitySeriesEndpoints();
api.MapRecurringEventEndpoints();
api.MapActivityEndpoints();
api.MapSocialEndpoints();
api.MapDirectContactEndpoints();
api.MapFriendEndpoints();
api.MapSessionEndpoints();
api.MapGovernanceEndpoints();
api.MapFeedbackEndpoints();
api.MapAdminEndpoints();
api.MapSuggestionEndpoints();
api.MapContentFilterEndpoints();
api.MapRealtimeEndpoints();

app.Run();

static async Task WriteError(HttpContext context, string traceId, int status, string code, string message)
{
    context.Response.StatusCode = status;
    context.Response.Headers.CacheControl = "no-store";
    if (status == 429 && !context.Response.Headers.ContainsKey("Retry-After"))
        context.Response.Headers.RetryAfter = "4";
    await context.Response.WriteAsJsonAsync(new
    {
        data = (object?)null,
        meta = (object?)null,
        error = new { code, message },
        traceId
    }, context.RequestAborted);
}

public partial class Program;

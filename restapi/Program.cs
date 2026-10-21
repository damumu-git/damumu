using System.Diagnostics;
using Muda.Api;
using Muda.Api.Endpoints;
using Muda.Api.Infrastructure;
using Microsoft.Extensions.FileProviders;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("Muda")
    ?? throw new InvalidOperationException("ConnectionStrings:Muda is required.");
builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddSingleton<Db>();
builder.Services.AddSingleton<MediaStorage>();
builder.Services.AddSingleton<AuthService>();
builder.Services.AddSingleton<AccountDeletionService>();
builder.Services.AddSingleton<RealtimeConnectionManager>();
builder.Services.AddSingleton<PushNotificationService>();
builder.Services.AddHostedService<RealtimeRelayService>();
builder.Services.AddHostedService<ConversationLifecycleService>();
builder.Services.AddHostedService<PrivacyRetentionService>();
builder.Services.AddOpenApi();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

var app = builder.Build();
var mediaStorage = app.Services.GetRequiredService<MediaStorage>();
mediaStorage.Initialize(Path.Combine(AppContext.BaseDirectory, "preset-avatars"));

app.Use(async (context, next) =>
{
    context.Response.Headers["X-Trace-Id"] = Activity.Current?.Id ?? context.TraceIdentifier;
    try
    {
        await next();
    }
    catch (ApiException exception)
    {
        context.Response.StatusCode = exception.StatusCode;
        await context.Response.WriteAsJsonAsync(new
        {
            data = (object?)null,
            meta = (object?)null,
            error = new { code = exception.Code, message = exception.Message },
            traceId = Activity.Current?.Id ?? context.TraceIdentifier
        });
    }
    catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
    {
        context.Response.StatusCode = 409;
        await context.Response.WriteAsJsonAsync(new
        {
            data = (object?)null,
            meta = (object?)null,
            error = new { code = "conflict", message = "数据已存在或发生状态冲突" },
            traceId = Activity.Current?.Id ?? context.TraceIdentifier
        });
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
            "/uploads/messages", StringComparison.OrdinalIgnoreCase)
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
api.MapUserEndpoints();
api.MapEventEndpoints();
api.MapActivityEndpoints();
api.MapSocialEndpoints();
api.MapSafetyEndpoints();
api.MapGovernanceEndpoints();
api.MapFeedbackEndpoints();
api.MapAdminEndpoints();
api.MapRealtimeEndpoints();

app.Run();

public partial class Program;

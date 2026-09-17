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
builder.Services.AddSingleton<AuthService>();
builder.Services.AddOpenApi();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

var app = builder.Build();
var uploadsRoot = Path.Combine(app.Environment.ContentRootPath, "uploads");
Directory.CreateDirectory(Path.Combine(uploadsRoot, "avatars"));

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

app.UseCors();
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(uploadsRoot),
    RequestPath = "/uploads"
});
app.MapOpenApi();

var api = app.MapGroup("/api/v1");
api.MapGet("/health", async (Db db, CancellationToken ct) =>
{
    var databaseTime = await db.ScalarAsync<DateTime>("SELECT now()", cancellationToken: ct);
    return ApiSupport.Ok(new { status = "healthy", databaseTime });
});

api.MapCatalogEndpoints();
api.MapUserEndpoints();
api.MapEventEndpoints();
api.MapActivityEndpoints();
api.MapSocialEndpoints();
api.MapSafetyEndpoints();
api.MapGovernanceEndpoints();
api.MapAdminEndpoints();

app.Run();

public partial class Program;

using System.Diagnostics;
using Muda.Api.Infrastructure;

namespace Muda.Api;

public static class ApiSupport
{
    private static readonly object BearerUserKey = new();

    public static IResult Ok(object? data, object? meta = null) =>
        new MediaJsonResult(new { data, meta, error = (object?)null, traceId = Activity.Current?.Id });

    public static IResult Created(string uri, object? data) =>
        new MediaJsonResult(new { data, meta = (object?)null, error = (object?)null, traceId = Activity.Current?.Id }, uri);

    public static Guid RequireUserId(HttpContext context) => GetOptionalUserId(context)
        ?? throw new ApiException(401, "unauthorized", "登录已失效，请重新登录");

    public static Guid? GetOptionalUserId(HttpContext context)
    {
        var environment = context.RequestServices.GetRequiredService<IWebHostEnvironment>();
        var raw = context.Request.Headers["X-User-Id"].FirstOrDefault();
        if (environment.IsDevelopment() && Guid.TryParse(raw, out var developmentUserId))
            return developmentUserId;

        return GetBearerUserId(context);
    }

    internal static Guid? GetBearerUserId(HttpContext context)
    {
        if (context.Items.TryGetValue(BearerUserKey, out var cached)) return (Guid?)cached;
        var authorization = context.Request.Headers.Authorization.FirstOrDefault();
        var token = authorization?.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) == true
            ? authorization[7..].Trim()
            : null;
        if (token is null) return null;
        var auth = context.RequestServices.GetRequiredService<AuthService>();
        Guid? account = auth.TryValidateToken(token, out var userId) ? userId : null;
        context.Items[BearerUserKey] = account;
        return account;
    }

    public static RouteGroupBuilder RequireAdmin(this RouteGroupBuilder group) =>
        group.AddEndpointFilter(async (invocation, next) =>
        {
            var context = invocation.HttpContext;
            var expected = context.RequestServices.GetRequiredService<IConfiguration>()["Admin:ApiKey"];
            var supplied = context.Request.Headers["X-Admin-Key"].FirstOrDefault();
            if (string.IsNullOrWhiteSpace(expected) || supplied != expected)
                return Results.Json(
                    new { data = (object?)null, meta = (object?)null, error = new { code = "admin_unauthorized", message = "管理员凭证无效" }, traceId = Activity.Current?.Id },
                    statusCode: 401);
            return await next(invocation);
        });
}

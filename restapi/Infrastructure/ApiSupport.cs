using System.Diagnostics;
using Muda.Api.Infrastructure;

namespace Muda.Api;

public static class ApiSupport
{
    public static IResult Ok(object? data, object? meta = null) =>
        Results.Ok(new { data, meta, error = (object?)null, traceId = Activity.Current?.Id });

    public static IResult Created(string uri, object? data) =>
        Results.Created(uri, new { data, meta = (object?)null, error = (object?)null, traceId = Activity.Current?.Id });

    public static Guid RequireUserId(HttpContext context)
    {
        var raw = context.Request.Headers["X-User-Id"].FirstOrDefault();
        if (Guid.TryParse(raw, out var developmentUserId))
            return developmentUserId;

        var authorization = context.Request.Headers.Authorization.FirstOrDefault();
        var token = authorization?.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) == true
            ? authorization[7..].Trim()
            : null;
        var auth = context.RequestServices.GetRequiredService<AuthService>();
        if (token is null || !auth.TryValidateToken(token, out var userId))
            throw new ApiException(401, "unauthorized", "登录已失效，请重新登录");
        return userId;
    }

    public static Guid? GetOptionalUserId(HttpContext context)
    {
        var raw = context.Request.Headers["X-User-Id"].FirstOrDefault();
        if (Guid.TryParse(raw, out var developmentUserId)) return developmentUserId;

        var authorization = context.Request.Headers.Authorization.FirstOrDefault();
        var token = authorization?.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) == true
            ? authorization[7..].Trim()
            : null;
        if (token is null) return null;
        var auth = context.RequestServices.GetRequiredService<AuthService>();
        return auth.TryValidateToken(token, out var userId) ? userId : null;
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

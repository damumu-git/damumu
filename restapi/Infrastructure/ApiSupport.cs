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
        return null;
    }

    internal static void SetValidatedUser(HttpContext context, Guid? userId) => context.Items[BearerUserKey] = userId;

    public static RouteGroupBuilder RequireAdmin(this RouteGroupBuilder group) =>
        group.AddEndpointFilter(async (invocation, next) =>
        {
            var context = invocation.HttpContext;
            var security = context.RequestServices.GetRequiredService<AdminSecurity>();
            var account = await security.CurrentAsync(context, context.RequestAborted)
                ?? throw new ApiException(401, "admin_unauthorized", "请登录管理员账号");
            context.Response.Headers.CacheControl = "private,no-store";
            var role = (string)account["role"]!;
            var write = context.Request.Method is not ("GET" or "HEAD");
            var ownerOnly = context.Request.Path.StartsWithSegments("/api/v1/admin/feature-flags")
                || context.Request.Path.StartsWithSegments("/api/v1/admin/settings")
                || context.Request.Path.StartsWithSegments("/api/v1/admin/categories")
                || context.Request.Path.StartsWithSegments("/api/v1/admin/regions")
                || context.Request.Path.StartsWithSegments("/api/v1/admin/system-avatars")
                || context.Request.Path.StartsWithSegments("/api/v1/admin/emoji-assets")
                || context.Request.Path.StartsWithSegments("/api/v1/admin/activity-series/official-editor")
                || context.Request.Path.StartsWithSegments("/api/v1/admin/announcements");
            if (write && (role == "viewer" || ownerOnly && role != "owner"))
                throw new ApiException(403, "admin_forbidden", "该操作需要更高的管理权限");
            // Historical request records carry an optional app-user actor. It must never be supplied by the browser.
            foreach (var argument in invocation.Arguments)
                argument?.GetType().GetProperty("ActorUserId")?.SetValue(argument, null);
            var db = context.RequestServices.GetRequiredService<Db>();
            await db.ExecuteAsync("""
                INSERT INTO audit_log(admin_account_id,actor_role,action,target_type,trace_id,metadata)
                VALUES(@id,'admin',@action,'admin_api',@traceId,jsonb_build_object('method',@method,'route',@route))
                """, new
                {
                    id = account["id"], action = write ? "admin.write.requested" : "admin.read",
                    traceId = Activity.Current?.Id ?? context.TraceIdentifier,
                    method = context.Request.Method,
                    route = (context.GetEndpoint() as Microsoft.AspNetCore.Routing.RouteEndpoint)?.RoutePattern.RawText
                }, context.RequestAborted);
            return await next(invocation);
        });
}

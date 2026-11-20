using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class SessionEndpoints
{
    public static void MapSessionEndpoints(this RouteGroupBuilder api)
    {
        api.MapPost("/auth/refresh", async (RefreshInput input, SessionSecurity sessions, CancellationToken ct) =>
            ApiSupport.Ok(await sessions.RefreshAsync(input.RefreshToken, ct)));
        api.MapPost("/auth/logout", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("UPDATE auth_session SET revoked_at=now() WHERE token_hash=@hash OR previous_access_hash=@hash",
                new { hash = SessionSecurity.Hash(SessionSecurity.RequestToken(context)!) }, ct);
            context.Response.Cookies.Delete(SessionSecurity.CookieName, SessionSecurity.Cookie());
            return Results.NoContent();
        });
        api.MapPost("/auth/logout-all", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("UPDATE auth_session SET revoked_at=now() WHERE user_id=@userId", new { userId }, ct);
            context.Response.Cookies.Delete(SessionSecurity.CookieName, SessionSecurity.Cookie());
            return Results.NoContent();
        });
        api.MapGet("/me/sessions", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var hash = SessionSecurity.Hash(SessionSecurity.RequestToken(context)!);
            return ApiSupport.Ok(await db.QueryAsync("""
                SELECT id,created_at,expires_at,COALESCE(token_hash=@hash OR previous_access_hash=@hash,false) AS current FROM auth_session
                WHERE user_id=@userId AND revoked_at IS NULL AND expires_at>now() ORDER BY created_at DESC LIMIT 100
                """, new { userId, hash }, ct));
        });
        api.MapDelete("/me/sessions/{id:guid}", async (Guid id, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            await db.ExecuteAsync("UPDATE auth_session SET revoked_at=now() WHERE id=@id AND user_id=@userId",
                new { id, userId }, ct);
            return Results.NoContent();
        });
        var admin = api.MapGroup("/admin-auth");
        admin.MapPost("/login", async (AdminLogin input, HttpContext context, AdminSecurity security, CancellationToken ct) =>
        {
            await security.LoginAsync(context, input.Username, input.Password, input.Code, ct);
            return ApiSupport.Ok(new { signedIn = true });
        });
        admin.MapGet("/session", async (HttpContext context, AdminSecurity security, CancellationToken ct) =>
        {
            var account = await security.CurrentAsync(context, ct)
                ?? throw new ApiException(401, "admin_unauthorized", "请登录管理员账号");
            return ApiSupport.Ok(new { username = account["username"], role = account["role"] });
        });
        admin.MapPost("/logout", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            var token = context.Request.Cookies[SessionSecurity.AdminCookie];
            if (token is not null)
                await db.ExecuteAsync("DELETE FROM admin_session WHERE token_hash=@hash",
                    new { hash = SessionSecurity.Hash(token) }, ct);
            context.Response.Cookies.Delete(SessionSecurity.AdminCookie, SessionSecurity.Cookie());
            return Results.NoContent();
        });
    }

    public sealed record AdminLogin(string? Username, string? Password, string? Code);
    public sealed record RefreshInput(string? RefreshToken);
}

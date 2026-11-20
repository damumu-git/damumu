using System.Threading.RateLimiting;

namespace Muda.Api.Infrastructure;

internal static class NetworkRateLimits
{
    public static PartitionedRateLimiter<HttpContext> Create() =>
        PartitionedRateLimiter.Create<HttpContext, string>(context =>
        {
            var health = context.Request.Path == "/api/v1/health";
            var auth = context.Request.Path.StartsWithSegments("/api/v1/auth") ||
                       context.Request.Path.StartsWithSegments("/api/v1/admin-auth");
            var ip = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
            return RateLimitPartition.GetTokenBucketLimiter((health ? "health:" : auth ? "auth:" : "api:") + ip,
                _ => new TokenBucketRateLimiterOptions
                {
                    TokenLimit = health ? 5 : auth ? 12 : 60, TokensPerPeriod = health || auth ? 1 : 15,
                    ReplenishmentPeriod = health ? TimeSpan.FromSeconds(5) : auth ? TimeSpan.FromSeconds(4) : TimeSpan.FromSeconds(1),
                    QueueLimit = 0
                });
        });
}

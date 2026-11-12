using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Routing;

namespace Muda.Api.Infrastructure;

internal static class AccountRateLimits
{
    private static readonly Policy Writes = new("writes", 40, TimeSpan.FromMilliseconds(500));
    private static readonly Policy Messages = new("messages", 8, TimeSpan.FromSeconds(2));
    private static readonly Policy Publishing = new("publishing", 4, TimeSpan.FromMinutes(3));
    private static readonly Policy Uploads = new("uploads", 8, TimeSpan.FromSeconds(15));
    private static readonly Policy Reports = new("reports", 6, TimeSpan.FromMinutes(1));
    private static readonly Policy ContactRequests = new("contact-requests", 3, TimeSpan.FromMinutes(10));

    public static PartitionedRateLimiter<HttpContext> Create() =>
        PartitionedRateLimiter.CreateChained(CreatePartition(useSpecificPolicy: true), CreatePartition(useSpecificPolicy: false));

    private static PartitionedRateLimiter<HttpContext> CreatePartition(bool useSpecificPolicy) =>
        PartitionedRateLimiter.Create<HttpContext, (Guid Account, string Bucket)>(context =>
        {
            var method = context.Request.Method;
            if (!(HttpMethods.IsPost(method) || HttpMethods.IsPut(method) ||
                  HttpMethods.IsPatch(method) || HttpMethods.IsDelete(method)) ||
                context.GetEndpoint() is not RouteEndpoint endpoint ||
                endpoint.RoutePattern.RawText is not { } route ||
                !route.StartsWith("/api/v1/", StringComparison.Ordinal) ||
                route.StartsWith("/api/v1/admin/", StringComparison.Ordinal) ||
                route.StartsWith("/api/v1/auth/", StringComparison.Ordinal))
                return RateLimitPartition.GetNoLimiter((Guid.Empty, ""));

            var policy = useSpecificPolicy ? SpecificPolicy(route) : Writes;
            if (policy is null || ApiSupport.GetOptionalUserId(context) is not { } account)
                return RateLimitPartition.GetNoLimiter((Guid.Empty, ""));

            return RateLimitPartition.GetTokenBucketLimiter((account, policy.Name), _ => new TokenBucketRateLimiterOptions
            {
                TokenLimit = policy.Burst,
                TokensPerPeriod = 1,
                ReplenishmentPeriod = policy.Interval,
                QueueLimit = 0
            });
        });

    private static Policy? SpecificPolicy(string route) => route switch
    {
        "/api/v1/contact-requests" => ContactRequests,
        "/api/v1/conversations/direct" or "/api/v1/conversations/{id:guid}/messages" or
            "/api/v1/conversations/{id:guid}/messages/{messageId:guid}" => Messages,
        "/api/v1/events" or "/api/v1/events/{id:guid}/publish" or
            "/api/v1/web/intents" or "/api/v1/web/groups" => Publishing,
        "/api/v1/events/covers" or "/api/v1/conversations/{id:guid}/media" or
            "/api/v1/me/avatar" => Uploads,
        "/api/v1/reports" or "/api/v1/me/suggestions" or "/api/v1/feedback" or
            "/api/v1/conversations/{id:guid}/messages/{messageId:guid}/report" => Reports,
        _ => null
    };

    private sealed record Policy(string Name, int Burst, TimeSpan Interval);
}

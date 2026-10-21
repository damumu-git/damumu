using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Muda.Api.Infrastructure;

// Normalize only media URL fields in the response, keeping stored keys portable.
public sealed class MediaJsonResult(object? payload, string? location = null) : IResult
{
    public Task ExecuteAsync(HttpContext context)
    {
        var options = context.RequestServices.GetRequiredService<
            IOptions<Microsoft.AspNetCore.Http.Json.JsonOptions>>().Value.SerializerOptions;
        var node = JsonSerializer.SerializeToNode(payload, options);
        context.RequestServices.GetRequiredService<MediaStorage>().RewriteResponseUrls(node);
        return (location is null ? Results.Ok(node) : Results.Created(location, node)).ExecuteAsync(context);
    }
}

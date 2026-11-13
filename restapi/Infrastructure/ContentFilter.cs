using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Muda.Api.Endpoints;

namespace Muda.Api.Infrastructure;

public sealed partial class ContentFilter(Db db)
{
    private volatile Snapshot? snapshot;

    public static async ValueTask<object?> Inspect(EndpointFilterInvocationContext invocation, EndpointFilterDelegate next)
    {
        var fields = invocation.Arguments.SelectMany(argument => argument switch
        {
            RegisterRequest input => [input.Nickname],
            DevLoginRequest input => [input.Nickname],
            SocialLoginRequest input => [input.Nickname],
            WebSocialRegistration input => [input.Nickname],
            UpdateProfileRequest input => [input.Nickname, input.Bio, input.Occupation],
            WebGuideEndpoints.BioUpdate input => [input.Bio],
            CreateEventRequest input => [input.Title, input.Description, input.CustomSubcategory,
                input.Announcement, input.OrganizerNote, input.Place?.Name, input.Place?.AddressPublic],
            UpdateEventRequest input => [input.Title, input.Description, input.CustomSubcategory],
            JoinEventRequest input => [input.Note],
            RejectApplicationRequest input => [input.Reason],
            CancelEventRequest input => [input.Reason],
            SendMessageRequest input => [input.Body],
            ContactRequestInput input => [input.Body],
            ActivitySeriesEndpoints.SeriesInput input => [input.Title, input.Description],
            ActivitySeriesEndpoints.RecapInput input => [input.Body],
            ActivitySeriesEndpoints.SeriesProposal input => [input.Body],
            EditMessageRequest input => [input.Body],
            CreateReviewRequest input => [input.Comment, ..input.Tags ?? []],
            SuggestionText input => [input.Text],
            SubmitFeedbackRequest input when input.FeedbackType?.Trim().Equals("like", StringComparison.OrdinalIgnoreCase) == true
                => [input.Description, ..input.CustomTags ?? []],
            WebCommunityEndpoints.IntentInput input => [input.Title, input.Description],
            WebCommunityEndpoints.GroupInput input => [input.Title, input.Description],
            _ => Array.Empty<string?>()
        }).Where(field => !string.IsNullOrWhiteSpace(field)).ToArray();
        if (fields.Length > 0)
        {
            var context = invocation.HttpContext;
            var filter = context.RequestServices.GetRequiredService<ContentFilter>();
            await filter.ValidateAsync(fields, context.RequestAborted);
        }
        return await next(invocation);
    }

    private async Task ValidateAsync(string?[] fields, CancellationToken ct)
    {
        var current = snapshot;
        if (current is null || current.Expires <= DateTimeOffset.UtcNow)
        {
            var rows = await db.QueryAsync(
                "SELECT term FROM content_filter_term WHERE is_enabled ORDER BY term",
                cancellationToken: ct);
            var terms = rows.Select(row => (string)row["term"]!).ToArray();
            current = new Snapshot(DateTimeOffset.UtcNow.AddSeconds(30),
                terms.Where(term => !LatinTerm().IsMatch(term)).ToArray(),
                terms.Where(term => LatinTerm().IsMatch(term)).ToArray());
            snapshot = current;
        }
        foreach (var field in fields)
        {
            var text = Normalize(field!);
            if (current.Substrings.Any(term => text.Contains(term, StringComparison.Ordinal)) ||
                current.LatinPhrases.Any(term => ContainsLatinPhrase(text, term)))
                throw new ApiException(400, "blocked_content", "内容含有受限词语，请修改后再提交");
        }
    }

    public void Invalidate() => snapshot = null;

    public static string Normalize(string value)
    {
        var text = new StringBuilder();
        foreach (var rune in value.Normalize(NormalizationForm.FormKC).ToLowerInvariant().EnumerateRunes())
        {
            if (Rune.GetUnicodeCategory(rune) == UnicodeCategory.Format) continue;
            text.Append(Rune.IsWhiteSpace(rune) ? " " : rune.ToString());
        }
        return ExtraSpaces().Replace(text.ToString().Trim(), " ");
    }

    private static bool ContainsLatinPhrase(string text, string term)
    {
        for (var offset = 0; offset <= text.Length - term.Length;)
        {
            var start = text.IndexOf(term, offset, StringComparison.Ordinal);
            if (start < 0) break;
            var end = start + term.Length;
            if ((start == 0 || !char.IsAsciiLetterOrDigit(text[start - 1])) &&
                (end == text.Length || !char.IsAsciiLetterOrDigit(text[end])))
                return true;
            offset = start + 1;
        }
        return false;
    }

    [GeneratedRegex("^[a-z0-9' -]+$")]
    private static partial Regex LatinTerm();
    [GeneratedRegex(" {2,}")]
    private static partial Regex ExtraSpaces();

    private sealed record Snapshot(DateTimeOffset Expires, string[] Substrings, string[] LatinPhrases);
}

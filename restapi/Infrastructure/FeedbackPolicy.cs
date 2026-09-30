namespace Muda.Api.Infrastructure;

public sealed record FeedbackEligibility(
    bool Eligible,
    Guid TargetUserId,
    string? LikeTag,
    string? ReportTag);

public static class FeedbackPolicy
{
    public const int RiskSignalThreshold = 3;

    public static readonly IReadOnlySet<string> ActivityLikeTags = new HashSet<string>(
        ["punctual", "newcomer_friendly", "well_organized", "clear_communication",
         "welcoming", "safe_respectful", "good_value", "would_join_again"],
        StringComparer.Ordinal);

    public static readonly IReadOnlySet<string> UserLikeTags = new HashSet<string>(
        ["punctual", "friendly", "communicative", "respectful", "helpful",
         "positive", "reliable", "would_meet_again"],
        StringComparer.Ordinal);

    public static readonly IReadOnlySet<string> ActivityReportTags = new HashSet<string>(
        ["misleading_information", "organizer_no_show", "unsafe_arrangement",
         "inappropriate_behavior", "unexpected_costs", "privacy_issue",
         "spam_commercial", "discrimination"],
        StringComparer.Ordinal);

    public static readonly IReadOnlySet<string> UserReportTags = new HashSet<string>(
        ["no_show", "harassment", "inappropriate_content", "unsafe_behavior",
         "dishonesty", "spam", "discrimination", "privacy_violation"],
        StringComparer.Ordinal);

    public static void Validate(string targetType, string feedbackType, string tagCode, string? description)
    {
        if (targetType is not ("activity" or "user"))
            throw new ApiException(400, "invalid_feedback_target", "不支持的评价对象");
        if (feedbackType is not ("like" or "report"))
            throw new ApiException(400, "invalid_feedback_type", "不支持的评价类型");
        var tags = (targetType, feedbackType) switch
        {
            ("activity", "like") => ActivityLikeTags,
            ("activity", "report") => ActivityReportTags,
            ("user", "like") => UserLikeTags,
            _ => UserReportTags
        };
        if (!tags.Contains(tagCode))
            throw new ApiException(400, "invalid_feedback_tag", "请选择有效的评价标签");
        if (description?.Trim().Length > 500)
            throw new ApiException(400, "feedback_description_too_long", "补充说明最多 500 字");
    }

    public static async Task<FeedbackEligibility> ResolveAsync(
        Db db,
        Guid eventId,
        Guid viewerId,
        string targetType,
        Guid? requestedTargetUserId,
        CancellationToken cancellationToken)
    {
        if (targetType is not ("activity" or "user"))
            throw new ApiException(400, "invalid_feedback_target", "不支持的评价对象");
        var context = await db.QueryOneAsync(
            """
            SELECT e.organizer_user_id, e.status,
                   COALESCE((
                       SELECT max(s.ends_at)<=now() FROM event_schedule s
                       WHERE s.event_id=e.id
                   ), false) AS ended,
                   EXISTS (
                       SELECT 1 FROM event_member em
                       WHERE em.event_id=e.id AND em.user_id=@viewerId
                         AND em.status IN ('approved','attended') AND em.left_at IS NULL
                   ) AS viewer_participated
            FROM event e
            WHERE e.id=@eventId AND e.deleted_at IS NULL
            """, new { eventId, viewerId }, cancellationToken);
        if (context is null)
            throw new ApiException(404, "event_not_found", "活动不存在");

        var organizerId = (Guid)context["organizer_user_id"]!;
        var targetUserId = targetType == "activity"
            ? organizerId
            : requestedTargetUserId ?? throw new ApiException(
                400, "target_user_required", "请选择要评价的用户");
        var targetParticipated = targetType == "activity" || await db.ScalarAsync<long>(
            """
            SELECT count(*) FROM event_member
            WHERE event_id=@eventId AND user_id=@targetUserId
              AND status IN ('approved','attended') AND left_at IS NULL
            """, new { eventId, targetUserId }, cancellationToken) > 0;
        var eligible = (bool)context["ended"]!
            && !string.Equals(context["status"]?.ToString(), "cancelled", StringComparison.Ordinal)
            && (bool)context["viewer_participated"]!
            && targetParticipated
            && viewerId != targetUserId;

        var targetId = targetType == "activity" ? eventId : targetUserId;
        var likeTag = await db.ScalarAsync<string>(
            """
            SELECT tag_code FROM endorsement
            WHERE context_event_id=@eventId AND from_user_id=@viewerId
              AND target_type=@targetType AND target_id=@targetId
            """, new { eventId, viewerId, targetType, targetId }, cancellationToken);
        var reportTag = await db.ScalarAsync<string>(
            """
            SELECT category_code FROM report
            WHERE context_event_id=@eventId AND reporter_user_id=@viewerId
              AND target_type=@targetType AND target_id=@targetId
            """, new { eventId, viewerId, targetType, targetId }, cancellationToken);
        return new FeedbackEligibility(eligible, targetUserId, likeTag, reportTag);
    }
}

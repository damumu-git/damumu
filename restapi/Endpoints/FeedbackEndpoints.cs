using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class FeedbackEndpoints
{
    public static RouteGroupBuilder MapFeedbackEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/feedback/eligibility", async (
            Guid eventId,
            string targetType,
            Guid? targetUserId,
            HttpContext context,
            Db db,
            CancellationToken ct) =>
        {
            var result = await FeedbackPolicy.ResolveAsync(
                db, eventId, ApiSupport.RequireUserId(context), targetType, targetUserId, ct);
            return ApiSupport.Ok(result);
        });

        api.MapPost("/feedback", async (
            SubmitFeedbackRequest request,
            HttpContext context,
            Db db,
            CancellationToken ct) =>
        {
            var viewerId = ApiSupport.RequireUserId(context);
            var targetType = request.TargetType?.Trim().ToLowerInvariant() ?? "";
            var feedbackType = request.FeedbackType?.Trim().ToLowerInvariant() ?? "";
            var tagCode = request.TagCode?.Trim() ?? "";
            string[]? customTags = null;
            if (request.CustomTags is not null)
            {
                if (targetType != "activity" || feedbackType != "like")
                    throw new ApiException(400, "custom_feedback_not_supported", "仅活动评价支持自定义标签");
                customTags = FeedbackPolicy.ValidateCustomTags(request.CustomTags);
            }
            var customOnly = tagCode.Length == 0 && customTags is { Length: > 0 };
            FeedbackPolicy.Validate(targetType, feedbackType, tagCode, request.Description, customTags is { Length: > 0 });
            var eligibility = await FeedbackPolicy.ResolveAsync(
                db, request.EventId, viewerId, targetType, request.TargetUserId, ct);
            if (!eligibility.Eligible)
                throw new ApiException(403, "feedback_not_allowed",
                    "只有同一已结束活动的参与者可以评价");
            var targetId = targetType == "activity" ? request.EventId : eligibility.TargetUserId;
            if (feedbackType == "like")
            {
                var endorsement = await db.QueryOneAsync(
                    """
                    INSERT INTO endorsement (
                        context_event_id, from_user_id, target_type, target_id,
                        target_user_id, tag_code, custom_tags
                    ) VALUES (
                        @eventId, @viewerId, @targetType, @targetId,
                        @targetUserId, @tagCode, COALESCE(@customTags::text[], '{}')
                    )
                    ON CONFLICT (context_event_id, from_user_id, target_type, target_id)
                    DO UPDATE SET tag_code=EXCLUDED.tag_code,
                        custom_tags=COALESCE(@customTags::text[], endorsement.custom_tags),
                        updated_at=now()
                    WHERE EXCLUDED.target_type='activity'
                    RETURNING id, context_event_id, target_type, target_id, tag_code, custom_tags, updated_at
                    """, new
                    {
                        eventId = request.EventId,
                        viewerId,
                        targetType,
                        targetId,
                        targetUserId = eligibility.TargetUserId,
                        tagCode = customOnly ? null : tagCode,
                        customTags
                    }, ct);
                if (endorsement is null)
                    throw new ApiException(409, "user_feedback_already_submitted", "你已评价过这位用户");
                return ApiSupport.Ok(endorsement);
            }

            var report = await db.QueryOneAsync(
                """
                INSERT INTO report (
                    reporter_user_id, target_type, target_id, reported_user_id,
                    context_event_id, category_code, description, priority
                ) VALUES (
                    @viewerId, @targetType, @targetId, @targetUserId,
                    @eventId, @tagCode, @description, 3
                )
                ON CONFLICT (context_event_id, reporter_user_id, target_type, target_id)
                    WHERE context_event_id IS NOT NULL AND target_type IN ('activity', 'user')
                DO UPDATE SET category_code=EXCLUDED.category_code,
                              description=EXCLUDED.description,
                              status='submitted', resolution_code=NULL, resolved_at=NULL,
                              updated_at=now()
                RETURNING id, context_event_id, target_type, target_id,
                          category_code, status, updated_at
                """, new
                {
                    eventId = request.EventId,
                    viewerId,
                    targetType,
                    targetId,
                    targetUserId = eligibility.TargetUserId,
                    tagCode,
                    description = string.IsNullOrWhiteSpace(request.Description)
                        ? null : request.Description.Trim()
                }, ct);
            return ApiSupport.Ok(report);
        });

        return api;
    }
}

public sealed record SubmitFeedbackRequest(
    Guid EventId,
    string? TargetType,
    Guid? TargetUserId,
    string? FeedbackType,
    string? TagCode,
    string? Description,
    string?[]? CustomTags = null);

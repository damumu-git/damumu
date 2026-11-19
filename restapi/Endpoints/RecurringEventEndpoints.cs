using System.Text.Json;
using Muda.Api.Infrastructure;

namespace Muda.Api.Endpoints;

public static class RecurringEventEndpoints
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    internal static DateTime? Occurrence(DateTime first, string frequency, int index)
    {
        if (frequency == "weekly") return first.AddDays(index * 7);
        if (index == 0) return first;
        var koreanTime = first.AddHours(9);
        var found = 0;
        for (var offset = 1; offset <= 24; offset++)
        {
            var month = koreanTime.AddMonths(offset);
            if (month.Day != koreanTime.Day) continue;
            found++;
            if (found == index) return month.AddHours(-9);
        }
        return null;
    }

    internal static async Task<Guid> CreatePlanAsync(Db db, Guid userId, CreateEventRequest request, CancellationToken ct)
    {
        if (request.RepeatFrequency is not ("weekly" or "monthly") ||
            (request.RepeatCount.HasValue == request.RepeatUntil.HasValue))
            throw new ApiException(400, "recurrence_invalid", "请选择每周或每月，并选择场数或截至日期");
        var count = request.RepeatCount ?? 0;
        if (request.RepeatUntil.HasValue)
        {
            var until = request.RepeatUntil.Value;
            var maximumEnd = request.StartsAt.AddHours(9).Date.AddMonths(6).AddDays(1).AddHours(-9);
            if (until < request.StartsAt || until >= maximumEnd)
                throw new ApiException(400, "recurrence_range_invalid", "计划截至日期须在首场之后，跨度不超过6个月");
            var finalDay = until.AddHours(9).Date;
            if (finalDay > request.StartsAt.AddHours(9).Date.AddMonths(6))
                throw new ApiException(400, "recurrence_range_invalid", "计划跨度不超过6个月");
            var exclusiveEnd = finalDay.AddDays(1).AddHours(-9);
            while (count <= 12)
            {
                var date = Occurrence(request.StartsAt, request.RepeatFrequency, count);
                if (!date.HasValue || date >= exclusiveEnd) break;
                count++;
            }
        }
        if (count is < 2 or > 12)
            throw new ApiException(400, "recurrence_invalid", "计划须包含2至12场，请调整场数或截至日期");
        if (await db.ScalarAsync<int>("SELECT member_level(@userId)", new { userId }, ct) == 3 && count > 4)
            throw new ApiException(400, "recurrence_level_limit", "信赖发起人的每个定期计划最多安排4期。");
        var last = Occurrence(request.StartsAt, request.RepeatFrequency, count-1);
        if (request.StartsAt <= DateTime.UtcNow || last is null ||
            last > request.StartsAt.AddHours(9).AddMonths(6).AddHours(-9))
            throw new ApiException(400, "recurrence_range_invalid", "定期活动须从未来开始，计划跨度不超过6个月");
        if (request.EndsAt - request.StartsAt > TimeSpan.FromDays(7))
            throw new ApiException(400, "recurrence_duration_invalid", "单场定期活动时长不能超过7天");
        var template = JsonSerializer.Serialize(request with { RepeatFrequency = null, RepeatCount = null, RepeatUntil = null, CoverMediaId = null }, JsonOptions);
        return await db.ScalarAsync<Guid>("""
            INSERT INTO event_recurrence(organizer_user_id,frequency,occurrence_count,first_starts_at,first_ends_at,template)
            VALUES(@userId,@frequency,@count,@startsAt,@endsAt,@template::jsonb) RETURNING id
            """, new { userId, frequency = request.RepeatFrequency, count,
                startsAt = request.StartsAt, endsAt = request.EndsAt, template }, ct);
    }

    public static void MapRecurringEventEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/me/recurring-events", async (HttpContext context, Db db, CancellationToken ct) =>
        {
            context.Response.Headers.CacheControl = "private, no-store";
            var userId = ApiSupport.RequireUserId(context);
            var plans = await db.QueryAsync("""
                SELECT id,frequency,occurrence_count,first_starts_at,first_ends_at,paused,
                    template->>'title' AS title
                FROM event_recurrence WHERE organizer_user_id=@userId
                ORDER BY created_at DESC LIMIT 100
                """, new { userId }, ct);
            foreach (var plan in plans)
            {
                var published = await db.QueryAsync("""
                    SELECT id,recurrence_index,status FROM event
                    WHERE recurrence_id=@id ORDER BY recurrence_index
                    """, new { id = plan["id"] }, ct);
                var first = (DateTime)plan["first_starts_at"]!;
                var duration = (DateTime)plan["first_ends_at"]! - first;
                var slots = new List<object>();
                var hasPending = false;
                for (var index = 0; index < Convert.ToInt32(plan["occurrence_count"]); index++)
                {
                    var startsAt = Occurrence(first, (string)plan["frequency"]!, index);
                    if (!startsAt.HasValue) continue;
                    var existing = published.FirstOrDefault(row => Convert.ToInt32(row["recurrence_index"]) == index);
                    if (existing is null && startsAt > DateTime.UtcNow) hasPending = true;
                    slots.Add(new { index, startsAt, endsAt = startsAt + duration, eventId = existing?["id"],
                        status = existing?["status"], canPublish = existing is null && plan["paused"] is false &&
                            startsAt > DateTime.UtcNow && startsAt <= DateTime.UtcNow.AddDays(14) });
                }
                plan["occurrences"] = slots;
                plan["completed"] = !hasPending;
            }
            return ApiSupport.Ok(plans);
        });

        api.MapPost("/recurring-events/{id:guid}/occurrences/{index:int}", (
            Guid id, int index, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            return db.InTransactionAsync(async transaction =>
            {
                var plan = await transaction.QueryOneAsync("""
                    UPDATE event_recurrence SET paused=paused
                    WHERE id=@id AND organizer_user_id=@userId
                    RETURNING frequency,occurrence_count,first_starts_at,first_ends_at,paused,template::text
                    """, new { id, userId }, ct) ?? throw new ApiException(404, "recurrence_not_found", "定期活动计划不存在");
                var existing = await transaction.QueryOneAsync("""
                    SELECT id FROM event WHERE recurrence_id=@id AND recurrence_index=@index
                    """, new { id, index }, ct);
                if (existing is not null) return ApiSupport.Ok(new { id = existing["id"], recurrenceId = id });
                if (plan["paused"] is true)
                    throw new ApiException(409, "recurrence_paused", "计划已暂停，请先恢复");
                if (index < 1 || index >= Convert.ToInt32(plan["occurrence_count"]))
                    throw new ApiException(400, "recurrence_index_invalid", "该场次超出计划范围");
                var first = (DateTime)plan["first_starts_at"]!;
                var startsAt = Occurrence(first, (string)plan["frequency"]!, index);
                if (!startsAt.HasValue)
                    throw new ApiException(400, "recurrence_date_missing", "当月没有对应日期，该场次已跳过");
                if (startsAt <= DateTime.UtcNow || startsAt > DateTime.UtcNow.AddDays(14))
                    throw new ApiException(409, "recurrence_not_due", "请在本场开始前14天内确认发布");
                var template = JsonSerializer.Deserialize<CreateEventRequest>((string)plan["template"]!, JsonOptions)
                    ?? throw new ApiException(409, "recurrence_template_invalid", "活动计划暂时不可用");
                await new ContentFilter(transaction).ValidateEventAsync(template, ct);
                var duration = (DateTime)plan["first_ends_at"]! - first;
                return await EventEndpoints.CreateEventAsync(userId,
                    template with { StartsAt = startsAt.Value, EndsAt = startsAt.Value + duration },
                    transaction, ct, id, index);
            }, ct);
        });

        api.MapPatch("/recurring-events/{id:guid}", async (
            Guid id, RecurrenceState request, HttpContext context, Db db, CancellationToken ct) =>
        {
            var userId = ApiSupport.RequireUserId(context);
            var count = await db.ExecuteAsync("""
                UPDATE event_recurrence SET paused=@paused WHERE id=@id AND organizer_user_id=@userId
                """, new { id, userId, request.Paused }, ct);
            if (count == 0) throw new ApiException(404, "recurrence_not_found", "定期活动计划不存在");
            return ApiSupport.Ok(request);
        });
    }

    public sealed record RecurrenceState(bool Paused);
}

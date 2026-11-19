namespace Muda.Api.Infrastructure;

public static class MemberPrivileges
{
    public static async Task RequireCommunityCreatorAsync(Db db, Guid userId, CancellationToken ct)
    {
        if (await db.ScalarAsync<int>("SELECT member_level(@userId)", new { userId }, ct) < 3)
            throw new ApiException(403, "member_level_required", "达到优搭主或金牌搭主后可创建活动系列和小组。");
    }

    public static async Task CheckPublicationAsync(Db db, Guid userId, bool recurring, CancellationToken ct)
    {
        var level = await db.ScalarAsync<int>("SELECT member_level(@userId)", new { userId }, ct);
        if (recurring && level < 3)
            throw new ApiException(403, "member_level_required", "达到优搭主或金牌搭主后可发布定期活动。");
        var limits = level switch
        {
            4 => (Open: 10, Monthly: 30),
            3 => (Open: 5, Monthly: 10),
            2 => (Open: 3, Monthly: 6),
            _ => (Open: 2, Monthly: 4)
        };
        var counts = await db.QueryOneAsync("""
            SELECT count(*) FILTER (
                WHERE e.deleted_at IS NULL AND e.status IN ('published','full') AND EXISTS (
                    SELECT 1 FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled' AND s.ends_at>now()
                )) AS open_count,
                count(*) FILTER (WHERE e.published_at > now()-interval '30 days') AS recent_count
            FROM event e WHERE e.organizer_user_id=@userId
            """, new { userId }, ct);
        if ((long)counts!["open_count"]! >= limits.Open)
            throw new ApiException(409, "active_activity_limit", $"你的等级最多可同时开放 {limits.Open} 场活动。");
        if ((long)counts["recent_count"]! >= limits.Monthly)
            throw new ApiException(409, "publication_limit", $"你的等级每 30 天最多可发布 {limits.Monthly} 场活动。");
    }
}

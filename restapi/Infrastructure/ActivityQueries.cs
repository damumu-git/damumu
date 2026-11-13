namespace Muda.Api.Infrastructure;

public static class ActivityQueries
{
    public const string ValidRegion = """
                SELECT count(*) FROM administrative_region district
                LEFT JOIN administrative_region municipality ON district.level=3
                    AND municipality.code=district.parent_code AND municipality.level=2 AND municipality.is_active
                JOIN administrative_region city ON city.code=CASE
                    WHEN district.level=3 THEN municipality.parent_code ELSE district.parent_code END
                WHERE city.code=@cityCode AND city.level=1 AND city.is_active
                  AND district.code=@districtCode AND district.level IN (2, 3) AND district.is_active
                """;

    // Publishing and moderation are independent. A rejection removes both URLs
    // and direct file access while preserving the original review history.
    internal const string PublicCoverEvent = """
        e.deleted_at IS NULL AND e.visibility='public'
        AND e.status IN ('published','full','completed','cancelled')
        AND e.cover_review_status IN ('pending','approved')
        """;

    internal const string CoverMediaJoin = $"""
        LEFT JOIN media_asset cover ON cover.id=e.cover_media_id
            AND cover.deleted_at IS NULL AND cover.status='ready' AND {PublicCoverEvent}
        """;

    internal const string CoverThumbnail = """
        CASE WHEN cover.id IS NOT NULL THEN '/uploads/' || COALESCE(cover.thumbnail_storage_key, cover.storage_key) END AS cover_url
        """;

    internal const string CoverCategoryCodes = """
        COALESCE(grandparent_category.code, parent_category.code, c.code) AS cover_category_code,
        c.code AS cover_subcategory_code
        """;

    internal const string CoverCategoryJoins = """
        LEFT JOIN category parent_category ON parent_category.id=c.parent_id
        LEFT JOIN category grandparent_category ON grandparent_category.id=parent_category.parent_id
        """;

    private const string Matching = $"""
                WITH matching AS (
                SELECT count(*) OVER () AS total_count, e.id, e.created_at, e.title, e.description, e.status, e.visibility, e.approval_mode,
                       e.min_participants, e.capacity, e.approved_count, e.waitlist_count,
                       e.price_min, e.price_max, e.price_amount,
                       e.price_currency, e.city_code, e.district_code, e.language_codes,
                       e.cover_media_id,
                       {CoverThumbnail},
                       e.published_at,
                       c.id AS category_id,
                       {CoverCategoryCodes},
                       COALESCE(e.custom_subcategory, c.name_zh_cn) AS category_name,
                       c.icon AS category_icon, (SELECT ea.image_url FROM emoji_asset ea WHERE ea.is_active AND (ea.key=c.icon_key OR ea.emoji=replace(replace(c.icon,'️',''),'︎','')) ORDER BY (ea.key=c.icon_key) DESC NULLS LAST LIMIT 1) AS category_icon_url,
                       city_region.name_zh_cn AS city_name,
                       city_region.name_ko_kr AS city_name_ko_kr,
                       city_region.name_en_us AS city_name_en_us,
                       district_region.name_zh_cn AS district_name,
                       district_region.name_ko_kr AS district_name_ko_kr,
                       district_region.name_en_us AS district_name_en_us,
                       municipality.code AS municipality_code,
                       municipality.name_zh_cn AS municipality_name,
                       municipality.name_ko_kr AS municipality_name_ko_kr,
                       municipality.name_en_us AS municipality_name_en_us,
                       NULL::text AS place_name, NULL::text AS address_public,
                       s.starts_at, s.ends_at,
                       u.id AS organizer_user_id, up.nickname AS organizer_name,
                       COALESCE(organizer_avatar.image_url, CASE
                           WHEN up.avatar_url LIKE '/uploads/%' THEN up.avatar_url
                           ELSE NULL
                       END) AS organizer_avatar,
                       COALESCE(ts.score, 0) AS organizer_score,
                       organizer_risk.category_code AS organizer_risk_tag,
                       e.beginner_friendly_claimed,
                       beginner_feedback.verified AS beginner_friendly_verified,
                       (e.beginner_friendly_claimed OR
                        beginner_feedback.verified) AS beginner_friendly,
                       CASE WHEN @hasGeo AND p.public_geo IS NOT NULL
                            THEN ST_Distance(p.public_geo, ST_Point(@longitude, @latitude, 4326)::geography)
                            ELSE NULL END AS distance_meters
                FROM event e
                JOIN category c ON c.id=e.category_id
                {CoverCategoryJoins}
                {CoverMediaJoin}
                JOIN app_user u ON u.id=e.organizer_user_id
                LEFT JOIN user_profile up ON up.user_id=u.id
                LEFT JOIN system_avatar organizer_avatar
                  ON up.avatar_url='system:'||organizer_avatar.id::text
                LEFT JOIN trust_snapshot ts ON ts.user_id=u.id
                LEFT JOIN LATERAL (
                    SELECT count(DISTINCT beginner_endorsement.from_user_id)
                               >= @beginnerFriendlyThreshold AS verified
                    FROM endorsement beginner_endorsement
                    WHERE beginner_endorsement.target_user_id=e.organizer_user_id
                      AND beginner_endorsement.target_type='activity'
                      AND beginner_endorsement.tag_code='newcomer_friendly'
                ) beginner_feedback ON true
                LEFT JOIN LATERAL (
                    SELECT r.category_code
                    FROM report r
                    WHERE r.reported_user_id=e.organizer_user_id
                      AND r.context_event_id IS NOT NULL
                      AND r.target_type='activity' AND r.status<>'dismissed'
                    GROUP BY r.category_code
                    HAVING count(DISTINCT r.reporter_user_id)>=3
                    ORDER BY count(DISTINCT r.reporter_user_id) DESC, r.category_code
                    LIMIT 1
                ) organizer_risk ON true
                LEFT JOIN place p ON p.id=e.place_id
                LEFT JOIN administrative_region city_region ON city_region.code=e.city_code
                LEFT JOIN administrative_region district_region ON district_region.code=e.district_code
                LEFT JOIN administrative_region municipality ON district_region.level=3 AND municipality.code=district_region.parent_code
                LEFT JOIN LATERAL (
                    SELECT starts_at, ends_at
                    FROM event_schedule
                    WHERE event_id=e.id AND status='scheduled'
                    ORDER BY (ends_at > now()) DESC, starts_at LIMIT 1
                ) s ON true
                WHERE e.deleted_at IS NULL
                  AND e.visibility='public'
                  AND e.status IN ('published', 'full')
                  AND (s.ends_at IS NULL OR s.ends_at > now())
                  AND (@followingUserId::uuid IS NULL OR (
                    EXISTS (SELECT 1 FROM web_follow f WHERE f.user_id=@followingUserId AND f.target_id=e.organizer_user_id)
                    AND direct_contact_visible(@followingUserId,e.organizer_user_id)
                  ))
                  AND (@city IS NULL OR e.city_code=@city)
                  AND (@district IS NULL OR e.district_code=@district OR municipality.code=@district)
                  AND (@categoryId IS NULL OR e.category_id=@categoryId OR c.parent_id=@categoryId)
                  AND (@maxPrice IS NULL OR COALESCE(e.price_amount,e.price_max)<=@maxPrice)
                  AND (@q IS NULL OR e.title ILIKE '%' || @q || '%' OR e.description ILIKE '%' || @q || '%')
                  AND (@from IS NULL OR s.starts_at >= @from)
                  AND (@to IS NULL OR s.starts_at <= @to)
                  AND (NOT @hasGeo OR p.public_geo IS NULL OR ST_DWithin(
                        p.public_geo, ST_Point(@longitude, @latitude, 4326)::geography, @radius))
                )
                """;

    public const string List = Matching + """

                SELECT * FROM matching
                WHERE NOT @hasCursor OR created_at < @cursorCreatedAt
                   OR (created_at = @cursorCreatedAt AND id < @cursorActivityId)
                ORDER BY created_at DESC, id DESC
                LIMIT @limit
                """;

    public const string Recommended = Matching + """

                SELECT * FROM matching
                WHERE NOT @hasCursor OR
                    (COALESCE(distance_meters, 'Infinity'::double precision),
                     COALESCE(starts_at, 'infinity'::timestamptz), id) >
                    (COALESCE(@cursorDistance, 'Infinity'::double precision),
                     COALESCE(@cursorStart, 'infinity'::timestamptz), @cursorActivityId)
                ORDER BY distance_meters ASC NULLS LAST, starts_at ASC NULLS LAST, id
                LIMIT @limit
                """;

}

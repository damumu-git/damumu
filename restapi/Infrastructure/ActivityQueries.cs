namespace Muda.Api.Infrastructure;

public static class ActivityQueries
{
    public const string List = """
                SELECT e.id, e.created_at, e.title, e.description, e.status, e.visibility, e.approval_mode,
                       e.min_participants, e.capacity, e.approved_count, e.waitlist_count,
                       e.price_min, e.price_max, e.price_amount,
                       e.price_currency, e.city_code, e.district_code, e.language_codes,
                       e.cover_media_id,
                       CASE WHEN cover.id IS NOT NULL THEN '/uploads/' || COALESCE(cover.thumbnail_storage_key, cover.storage_key) END AS cover_url,
                       e.published_at,
                       c.id AS category_id,
                       COALESCE(e.custom_subcategory, c.name_zh_cn) AS category_name,
                       c.icon AS category_icon, (SELECT ea.image_url FROM emoji_asset ea WHERE ea.is_active AND (ea.key=c.icon_key OR ea.emoji=replace(replace(c.icon,'️',''),'︎','')) ORDER BY (ea.key=c.icon_key) DESC NULLS LAST LIMIT 1) AS category_icon_url,
                       city_region.name_zh_cn AS city_name,
                       city_region.name_ko_kr AS city_name_ko_kr,
                       city_region.name_en_us AS city_name_en_us,
                       district_region.name_zh_cn AS district_name,
                       district_region.name_ko_kr AS district_name_ko_kr,
                       district_region.name_en_us AS district_name_en_us,
                       NULL::text AS place_name, NULL::text AS address_public,
                       s.starts_at, s.ends_at,
                       u.id AS organizer_user_id, up.nickname AS organizer_name,
                       up.avatar_url AS organizer_avatar,
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
                LEFT JOIN media_asset cover ON cover.id=e.cover_media_id AND cover.deleted_at IS NULL
                JOIN app_user u ON u.id=e.organizer_user_id
                LEFT JOIN user_profile up ON up.user_id=u.id
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
                LEFT JOIN LATERAL (
                    SELECT starts_at, ends_at
                    FROM event_schedule
                    WHERE event_id=e.id AND status='scheduled'
                    ORDER BY starts_at LIMIT 1
                ) s ON true
                WHERE e.deleted_at IS NULL
                  AND e.visibility='public'
                  AND (NOT @hasCursor OR e.created_at < @cursorCreatedAt
                       OR (e.created_at = @cursorCreatedAt AND e.id < @cursorActivityId))
                  AND e.status IN ('published', 'full')
                  AND (@city IS NULL OR e.city_code=@city)
                  AND (@district IS NULL OR e.district_code=@district)
                  AND (@categoryId IS NULL OR e.category_id=@categoryId)
                  AND (@q IS NULL OR e.title ILIKE '%' || @q || '%' OR e.description ILIKE '%' || @q || '%')
                  AND (@from IS NULL OR s.starts_at >= @from)
                  AND (@to IS NULL OR s.starts_at <= @to)
                  AND (NOT @hasGeo OR p.public_geo IS NULL OR ST_DWithin(
                        p.public_geo, ST_Point(@longitude, @latitude, 4326)::geography, @radius))
                ORDER BY e.created_at DESC, e.id DESC
                LIMIT @limit
                """;
}

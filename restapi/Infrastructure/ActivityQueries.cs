namespace Muda.Api.Infrastructure;

public static class ActivityQueries
{
    public const string List = """
                SELECT e.id, e.created_at, e.title, e.description, e.status, e.visibility, e.approval_mode,
                       e.min_participants, e.capacity, e.approved_count, e.waitlist_count,
                       e.price_min, e.price_max, e.price_amount,
                       e.price_currency, e.city_code, e.district_code, e.language_codes,
                       e.cover_media_id, CASE WHEN cover.id IS NOT NULL THEN '/uploads/' || cover.storage_key END AS cover_url, e.published_at,
                       c.id AS category_id,
                       COALESCE(e.custom_subcategory, c.name_zh_cn) AS category_name,
                       c.icon AS category_icon,
                       city_region.name_zh_cn AS city_name,
                       district_region.name_zh_cn AS district_name,
                       NULL::text AS place_name, NULL::text AS address_public,
                       s.starts_at, s.ends_at,
                       u.id AS organizer_user_id, up.nickname AS organizer_name,
                       COALESCE(ts.score, 0) AS organizer_score,
                       (e.title ILIKE '%新手%' OR e.description ILIKE '%新手%'
                        OR EXISTS (
                            SELECT 1
                            FROM event_tag beginner_tag
                            JOIN interest beginner_interest
                              ON beginner_interest.id=beginner_tag.interest_id
                            WHERE beginner_tag.event_id=e.id
                              AND (
                                  beginner_interest.code ILIKE '%beginner%'
                                  OR beginner_interest.name_zh_cn ILIKE '%新手%'
                                  OR beginner_interest.name_ko_kr ILIKE '%초보%'
                              )
                        )) AS beginner_friendly,
                       CASE WHEN @hasGeo AND p.public_geo IS NOT NULL
                            THEN ST_Distance(p.public_geo, ST_Point(@longitude, @latitude, 4326)::geography)
                            ELSE NULL END AS distance_meters
                FROM event e
                JOIN category c ON c.id=e.category_id
                LEFT JOIN media_asset cover ON cover.id=e.cover_media_id AND cover.deleted_at IS NULL
                JOIN app_user u ON u.id=e.organizer_user_id
                LEFT JOIN user_profile up ON up.user_id=u.id
                LEFT JOIN trust_snapshot ts ON ts.user_id=u.id
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

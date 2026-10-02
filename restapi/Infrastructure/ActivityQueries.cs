namespace Muda.Api.Infrastructure;

public static class ActivityQueries
{
    public const string List = """
        WITH origin AS (
            SELECT r.code, r.representative_geo
            FROM administrative_region r
            WHERE r.is_active AND r.representative_geo IS NOT NULL AND (
                (@cursorOrigin IS NOT NULL AND r.code=@cursorOrigin) OR
                (@cursorOrigin IS NULL AND @requestedRegion IS NOT NULL AND r.code=@requestedRegion) OR
                (@cursorOrigin IS NULL AND @requestedRegion IS NULL AND @hasGeo
                 AND (ST_Covers(r.boundary::geometry,ST_SetSRID(ST_Point(@longitude,@latitude),4326))
                      OR ST_DWithin(r.boundary,ST_Point(@longitude,@latitude,4326)::geography,30000)))
            )
            ORDER BY CASE WHEN r.code=@cursorOrigin THEN 0 WHEN r.code=@requestedRegion THEN 1
                          WHEN ST_Covers(r.boundary::geometry,ST_SetSRID(ST_Point(@longitude,@latitude),4326)) THEN 2 ELSE 3 END,
                     CASE WHEN @hasGeo THEN ST_Distance(r.boundary,ST_Point(@longitude,@latitude,4326)::geography) ELSE 0 END,
                     r.level DESC
            LIMIT 1
        ), base AS (
            SELECT e.*, s.starts_at, s.ends_at,
                   COALESCE(rp.ring_level, 32767)::integer AS region_ring,
                   COALESCE(rp.approximate_distance_meters, 2147483647)::integer AS approximate_distance_meters,
                   COALESCE(interest_match.match_count,0)::integer AS interest_matches,
                   COALESCE(ts.score,0)::numeric AS trust_score,
                   COALESCE(s.starts_at, TIMESTAMPTZ '9999-12-31 00:00:00+00') AS sort_starts_at
            FROM event e
            LEFT JOIN LATERAL (SELECT starts_at,ends_at FROM event_schedule WHERE event_id=e.id AND status='scheduled' ORDER BY starts_at LIMIT 1)s ON true
            LEFT JOIN administrative_region target_region ON target_region.code=COALESCE(e.district_code,e.city_code)
            LEFT JOIN origin o ON true
            LEFT JOIN region_proximity rp ON rp.origin_region_code=o.code AND rp.target_region_code=target_region.code
            LEFT JOIN trust_snapshot ts ON ts.user_id=e.organizer_user_id
            LEFT JOIN LATERAL (
                SELECT count(*)::integer match_count FROM event_tag et
                JOIN user_interest ui ON ui.interest_id=et.interest_id AND ui.user_id=@viewerUserId
                WHERE et.event_id=e.id
            ) interest_match ON @viewerUserId IS NOT NULL
            WHERE e.deleted_at IS NULL AND e.visibility='public' AND e.status IN('published','full')
              AND e.created_at<=@anchorAt
              AND (@city IS NULL OR e.city_code=@city) AND (@district IS NULL OR e.district_code=@district)
              AND (@categoryId IS NULL OR e.category_id=@categoryId)
              AND (@q IS NULL OR e.title ILIKE '%'||@q||'%' OR e.description ILIKE '%'||@q||'%')
              AND (@from IS NULL OR s.starts_at>=@from) AND (@to IS NULL OR s.starts_at<=@to)
              AND (o.code IS NULL OR (target_region.representative_geo IS NOT NULL AND
                   ST_DWithin(o.representative_geo,target_region.representative_geo,@radius)))
        ), ranked AS (
            SELECT base.*,
              LEAST(1000,GREATEST(0,round(
                LEAST(interest_matches,3)/3.0*350
                + CASE WHEN region_ring=32767 THEN 0 ELSE 300.0/(1+region_ring) END
                + CASE WHEN starts_at IS NULL OR starts_at<@anchorAt THEN 0 ELSE 200.0/(1+GREATEST(0,EXTRACT(EPOCH FROM (starts_at-@anchorAt))/86400)/14) END
                + LEAST(5,GREATEST(0,trust_score))/5.0*150
              )))::integer score_key
            FROM base
        )
        SELECT r.id,r.created_at,r.title,r.description,r.status,r.visibility,r.approval_mode,
               r.min_participants,r.capacity,r.approved_count,r.waitlist_count,r.price_min,r.price_max,r.price_amount,
               r.price_currency,r.city_code,r.district_code,r.language_codes,r.cover_media_id,
               CASE WHEN cover.id IS NOT NULL THEN '/uploads/'||COALESCE(cover.thumbnail_storage_key,cover.storage_key) END cover_url,
               r.published_at,c.id category_id,COALESCE(r.custom_subcategory,c.name_zh_cn) category_name,c.icon category_icon,
               city_region.name_zh_cn city_name,district_region.name_zh_cn district_name,
               NULL::text place_name,NULL::text address_public,r.starts_at,r.ends_at,
               u.id organizer_user_id,up.nickname organizer_name,up.avatar_url organizer_avatar,
               r.trust_score organizer_score,organizer_risk.category_code organizer_risk_tag,
               (r.title ILIKE '%新手%' OR r.description ILIKE '%新手%' OR EXISTS(SELECT 1 FROM event_tag bt JOIN interest bi ON bi.id=bt.interest_id WHERE bt.event_id=r.id AND (bi.code ILIKE '%beginner%' OR bi.name_zh_cn ILIKE '%新手%' OR bi.name_ko_kr ILIKE '%초보%'))) beginner_friendly,
               CASE WHEN r.region_ring=0 THEN 'same_region' WHEN r.region_ring=1 THEN 'neighboring_region' WHEN r.region_ring<=3 THEN 'nearby_region' ELSE 'wider_region' END proximity_level,
               NULL::double precision distance_meters,r.score_key,(r.score_key/1000.0)::numeric recommendation_score,
               r.region_ring,r.sort_starts_at,(SELECT code FROM origin) origin_region_code
        FROM ranked r JOIN category c ON c.id=r.category_id
        LEFT JOIN media_asset cover ON cover.id=r.cover_media_id AND cover.deleted_at IS NULL
        JOIN app_user u ON u.id=r.organizer_user_id LEFT JOIN user_profile up ON up.user_id=u.id
        LEFT JOIN administrative_region city_region ON city_region.code=r.city_code
        LEFT JOIN administrative_region district_region ON district_region.code=r.district_code
        LEFT JOIN LATERAL (SELECT report.category_code FROM report WHERE report.reported_user_id=r.organizer_user_id AND report.context_event_id IS NOT NULL AND report.target_type='activity' AND report.status<>'dismissed' GROUP BY report.category_code HAVING count(DISTINCT report.reporter_user_id)>=3 ORDER BY count(DISTINCT report.reporter_user_id) DESC,report.category_code LIMIT 1)organizer_risk ON true
        WHERE NOT @hasCursor OR r.score_key<@cursorScore
           OR (r.score_key=@cursorScore AND r.region_ring>@cursorRing)
           OR (r.score_key=@cursorScore AND r.region_ring=@cursorRing AND r.sort_starts_at>@cursorStartsAt)
           OR (r.score_key=@cursorScore AND r.region_ring=@cursorRing AND r.sort_starts_at=@cursorStartsAt AND r.created_at<@cursorCreatedAt)
           OR (r.score_key=@cursorScore AND r.region_ring=@cursorRing AND r.sort_starts_at=@cursorStartsAt AND r.created_at=@cursorCreatedAt AND r.id<@cursorActivityId)
        ORDER BY r.score_key DESC,r.region_ring ASC,r.sort_starts_at ASC,r.created_at DESC,r.id DESC
        LIMIT @limit
        """;
}

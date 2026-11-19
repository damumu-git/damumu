BEGIN;

CREATE OR REPLACE FUNCTION member_level(account_id uuid)
RETURNS integer LANGUAGE sql STABLE STRICT AS $$
    WITH successful AS MATERIALIZED (
        SELECT e.id FROM event e
        WHERE e.organizer_user_id=account_id AND e.deleted_at IS NULL
          AND e.status IN ('published','full','completed')
          AND EXISTS (SELECT 1 FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled')
          AND NOT EXISTS (SELECT 1 FROM event_schedule s
                          WHERE s.event_id=e.id AND s.status='scheduled' AND s.ends_at>now())
          AND EXISTS (SELECT 1 FROM event_member m JOIN app_user attendee ON attendee.id=m.user_id
                      WHERE m.event_id=e.id AND m.user_id<>account_id AND m.status='attended'
                        AND m.left_at IS NULL AND attendee.deleted_at IS NULL AND attendee.status='active')
    ), progress AS (
        SELECT (SELECT count(*) FROM successful) AS successful_count,
               EXISTS (SELECT 1 FROM member_identity_verification v
                       WHERE v.user_id=account_id AND v.revoked_at IS NULL) AS verified
    ), reputation AS (
        SELECT successful_count,verified,CASE WHEN successful_count >= 10 THEN (
            SELECT count(*) FROM endorsement en JOIN successful s ON s.id=en.context_event_id
            JOIN app_user reviewer ON reviewer.id=en.from_user_id
            WHERE en.target_user_id=account_id AND en.target_type='activity'
              AND reviewer.status='active' AND reviewer.deleted_at IS NULL
        )>50 ELSE false END AS reputable
        FROM progress
    )
    SELECT CASE WHEN reputable AND verified THEN 4 WHEN reputable OR verified THEN 3
                WHEN successful_count >= 3 THEN 2 ELSE 1 END FROM reputation
$$;

COMMIT;

-- Count the organizer as the first approved person in every activity.
-- Safe to run repeatedly.
BEGIN;

INSERT INTO event_member (
    event_id, user_id, member_role, status, party_size, joined_at
)
SELECT
    e.id,
    e.organizer_user_id,
    'organizer',
    'approved',
    1,
    COALESCE(e.published_at, e.created_at)
FROM event e
WHERE e.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM event_member em
      WHERE em.event_id = e.id
        AND em.user_id = e.organizer_user_id
  )
ON CONFLICT (event_id, user_id) DO NOTHING;

WITH active_people AS (
    SELECT
        e.id AS event_id,
        COALESCE(SUM(em.party_size) FILTER (
            WHERE em.status IN ('approved', 'attended')
        ), 0)::smallint AS people_count
    FROM event e
    LEFT JOIN event_member em ON em.event_id = e.id
    WHERE e.deleted_at IS NULL
    GROUP BY e.id
)
UPDATE event e
SET approved_count = active_people.people_count,
    status = CASE
        WHEN e.status IN ('published', 'full')
             AND active_people.people_count >= e.capacity THEN 'full'
        WHEN e.status = 'full'
             AND active_people.people_count < e.capacity THEN 'published'
        ELSE e.status
    END
FROM active_people
WHERE e.id = active_people.event_id
  AND (
      e.approved_count IS DISTINCT FROM active_people.people_count
      OR (
          e.status IN ('published', 'full')
          AND (e.status = 'full') IS DISTINCT FROM
              (active_people.people_count >= e.capacity)
      )
  );

COMMIT;

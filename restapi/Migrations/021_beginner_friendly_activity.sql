BEGIN;

ALTER TABLE event
    ADD COLUMN IF NOT EXISTS beginner_friendly_claimed boolean NOT NULL DEFAULT false;

-- Preserve the organizer's existing intent for activities that already describe
-- themselves as suitable for beginners. New activities use the explicit field.
UPDATE event
SET beginner_friendly_claimed = true
WHERE NOT beginner_friendly_claimed
  AND (
      title ILIKE '%新手%'
      OR description ILIKE '%新手%'
      OR title ILIKE '%초보%'
      OR description ILIKE '%초보%'
      OR title ILIKE '%beginner%'
      OR description ILIKE '%beginner%'
      OR EXISTS (
          SELECT 1
          FROM event_tag et
          JOIN interest i ON i.id = et.interest_id
          WHERE et.event_id = event.id
            AND (
                i.code ILIKE '%beginner%'
                OR i.name_zh_cn ILIKE '%新手%'
                OR i.name_ko_kr ILIKE '%초보%'
            )
      )
  );

COMMENT ON COLUMN event.beginner_friendly_claimed IS
    'Organizer declaration that the activity is suitable for first-time participants.';

COMMIT;

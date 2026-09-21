-- Durable event group chats and membership synchronization.
BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS uq_conversation_event
    ON conversation (event_id) WHERE conversation_type='event' AND event_id IS NOT NULL;

INSERT INTO conversation (conversation_type, event_id, title)
SELECT 'event', e.id, e.title
FROM event e
WHERE e.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM conversation c
      WHERE c.conversation_type='event' AND c.event_id=e.id
  );

UPDATE conversation c
SET title=e.title
FROM event e
WHERE c.conversation_type='event' AND c.event_id=e.id AND c.title IS DISTINCT FROM e.title;

INSERT INTO conversation_member (conversation_id, user_id, last_read_at)
SELECT c.id, em.user_id, now()
FROM event_member em
JOIN conversation c ON c.event_id=em.event_id AND c.conversation_type='event'
WHERE em.status IN ('approved', 'attended') AND em.left_at IS NULL
ON CONFLICT (conversation_id, user_id)
DO UPDATE SET left_at=NULL;

CREATE OR REPLACE FUNCTION muda_create_event_conversation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO conversation (conversation_type, event_id, title)
    VALUES ('event', NEW.id, NEW.title)
    ON CONFLICT (event_id) WHERE conversation_type='event' AND event_id IS NOT NULL
    DO UPDATE SET title=EXCLUDED.title, status='active', updated_at=now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_create_conversation ON event;
CREATE TRIGGER trg_event_create_conversation
AFTER INSERT OR UPDATE OF title ON event
FOR EACH ROW EXECUTE FUNCTION muda_create_event_conversation();

CREATE OR REPLACE FUNCTION muda_sync_event_conversation_member()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE event_conversation_id uuid;
BEGIN
    SELECT id INTO event_conversation_id
    FROM conversation
    WHERE conversation_type='event' AND event_id=NEW.event_id;

    IF event_conversation_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.status IN ('approved', 'attended') AND NEW.left_at IS NULL THEN
        INSERT INTO conversation_member (
            conversation_id, user_id, last_read_at, joined_at, left_at
        ) VALUES (
            event_conversation_id, NEW.user_id, now(), now(), NULL
        )
        ON CONFLICT (conversation_id, user_id)
        DO UPDATE SET left_at=NULL, joined_at=now(), last_read_at=now();
    ELSE
        UPDATE conversation_member
        SET left_at=COALESCE(left_at, now())
        WHERE conversation_id=event_conversation_id AND user_id=NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_member_sync_conversation ON event_member;
CREATE TRIGGER trg_event_member_sync_conversation
AFTER INSERT OR UPDATE OF status, left_at ON event_member
FOR EACH ROW EXECUTE FUNCTION muda_sync_event_conversation_member();

CREATE INDEX IF NOT EXISTS ix_notification_user_unread
    ON notification (user_id, created_at DESC) WHERE read_at IS NULL;

COMMIT;

-- Ensure the organizer joins the event conversation in the same trigger that
-- creates it. The event and organizer event_member are inserted by one SQL
-- statement, whose later trigger cannot see the conversation created earlier.
BEGIN;

CREATE OR REPLACE FUNCTION muda_create_event_conversation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE event_conversation_id uuid;
BEGIN
    INSERT INTO conversation (conversation_type, event_id, title)
    VALUES ('event', NEW.id, NEW.title)
    ON CONFLICT (event_id) WHERE conversation_type='event' AND event_id IS NOT NULL
    DO UPDATE SET title=EXCLUDED.title, status='active', updated_at=now()
    RETURNING id INTO event_conversation_id;

    INSERT INTO conversation_member (
        conversation_id, user_id, last_read_at, joined_at, left_at
    ) VALUES (
        event_conversation_id, NEW.organizer_user_id, now(), now(), NULL
    )
    ON CONFLICT (conversation_id, user_id)
    DO UPDATE SET left_at=NULL;

    RETURN NEW;
END;
$$;

INSERT INTO conversation_member (conversation_id, user_id, last_read_at)
SELECT c.id, e.organizer_user_id, now()
FROM event e
JOIN conversation c ON c.event_id=e.id AND c.conversation_type='event'
WHERE e.deleted_at IS NULL
ON CONFLICT (conversation_id, user_id)
DO UPDATE SET left_at=NULL;

COMMIT;

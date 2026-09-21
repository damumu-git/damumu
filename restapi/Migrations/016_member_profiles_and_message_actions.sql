BEGIN;

ALTER TABLE conversation_member
    ADD COLUMN IF NOT EXISTS hidden_at timestamptz,
    ADD COLUMN IF NOT EXISTS left_voluntarily_at timestamptz;

ALTER TABLE notification
    ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

CREATE INDEX IF NOT EXISTS ix_notification_user_visible
    ON notification (user_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION muda_sync_event_conversation_member()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE event_conversation_id uuid;
BEGIN
    SELECT id INTO event_conversation_id
    FROM conversation
    WHERE conversation_type='event' AND event_id=NEW.event_id;

    IF event_conversation_id IS NULL THEN RETURN NEW; END IF;

    IF NEW.status IN ('approved', 'attended') AND NEW.left_at IS NULL THEN
        INSERT INTO conversation_member (
            conversation_id, user_id, last_read_at, joined_at, left_at
        ) VALUES (
            event_conversation_id, NEW.user_id, now(), now(), NULL
        )
        ON CONFLICT (conversation_id, user_id)
        DO UPDATE SET
            left_at=CASE
                WHEN conversation_member.left_voluntarily_at IS NULL THEN NULL
                ELSE conversation_member.left_at
            END,
            hidden_at=NULL,
            joined_at=CASE
                WHEN conversation_member.left_voluntarily_at IS NULL THEN now()
                ELSE conversation_member.joined_at
            END,
            last_read_at=CASE
                WHEN conversation_member.left_voluntarily_at IS NULL THEN now()
                ELSE conversation_member.last_read_at
            END;
    ELSE
        UPDATE conversation_member
        SET left_at=COALESCE(left_at, now())
        WHERE conversation_id=event_conversation_id AND user_id=NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;

COMMIT;

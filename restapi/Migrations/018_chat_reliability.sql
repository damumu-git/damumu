BEGIN;

ALTER TABLE conversation
    ADD COLUMN IF NOT EXISTS read_only_at timestamptz,
    ADD COLUMN IF NOT EXISTS archived_at timestamptz;

CREATE INDEX IF NOT EXISTS ix_message_conversation_cursor
    ON message (conversation_id, created_at DESC, id DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_conversation_event_lifecycle
    ON conversation (event_id, status)
    WHERE conversation_type='event' AND event_id IS NOT NULL;

-- Event groups stay writable for seven days after the final schedule, remain
-- readable for 180 days, then leave the normal conversation list as archived.
CREATE OR REPLACE FUNCTION muda_refresh_conversation_lifecycle()
RETURNS TABLE(read_only_count bigint, archived_count bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    changed_read_only bigint;
    changed_archived bigint;
BEGIN
    WITH final_schedule AS (
        SELECT c.id,
               COALESCE(MAX(es.ends_at), e.cancelled_at, e.updated_at) AS ended_at,
               e.status AS event_status
        FROM conversation c
        JOIN event e ON e.id=c.event_id
        LEFT JOIN event_schedule es ON es.event_id=e.id
        WHERE c.conversation_type='event' AND c.status='active'
        GROUP BY c.id, e.status, e.cancelled_at, e.updated_at
    )
    UPDATE conversation c
    SET status='read_only', read_only_at=now(), updated_at=now()
    FROM final_schedule f
    WHERE c.id=f.id
      AND ((f.event_status='cancelled')
           OR (f.ended_at IS NOT NULL AND f.ended_at <= now() - interval '7 days'));
    GET DIAGNOSTICS changed_read_only = ROW_COUNT;

    UPDATE conversation
    SET status='archived', archived_at=now(), updated_at=now()
    WHERE conversation_type='event' AND status='read_only'
      AND read_only_at <= now() - interval '173 days';
    GET DIAGNOSTICS changed_archived = ROW_COUNT;

    RETURN QUERY SELECT changed_read_only, changed_archived;
END;
$$;

SELECT * FROM muda_refresh_conversation_lifecycle();

COMMIT;

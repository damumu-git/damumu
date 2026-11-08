-- Admin message moderation uses bounded time windows, cursor pagination and
-- keyword lookup without changing the three-month privacy retention policy.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS ix_message_admin_cursor
    ON message (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS ix_message_admin_sender_cursor
    ON message (sender_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS ix_message_admin_body_trgm
    ON message USING gin (body gin_trgm_ops)
    WHERE body IS NOT NULL;

COMMIT;

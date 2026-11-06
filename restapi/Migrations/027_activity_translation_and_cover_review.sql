BEGIN;

ALTER TABLE event ADD COLUMN IF NOT EXISTS cover_review_status text NOT NULL DEFAULT 'pending'
    CHECK (cover_review_status IN ('pending', 'approved', 'rejected'));
CREATE INDEX IF NOT EXISTS ix_event_pending_cover_review ON event (created_at, id)
    WHERE cover_media_id IS NOT NULL AND deleted_at IS NULL AND cover_review_status='pending';
CREATE INDEX IF NOT EXISTS ix_media_asset_thumbnail_key ON media_asset(thumbnail_storage_key)
    WHERE thumbnail_storage_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_event_cover_asset ON event(cover_media_id)
    WHERE cover_media_id IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS activity_translation (
    event_id uuid NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    language text NOT NULL CHECK (language IN ('zh', 'en', 'ko')),
    source_hash text NOT NULL,
    title text,
    description text,
    custom_subcategory text,
    retry_after timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, language)
);

CREATE TABLE IF NOT EXISTS user_suggestion (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
    created_at timestamptz NOT NULL DEFAULT now(),
    reply text CHECK (char_length(reply) BETWEEN 1 AND 1000),
    replied_at timestamptz,
    CHECK ((reply IS NULL) = (replied_at IS NULL))
);
CREATE INDEX IF NOT EXISTS ix_user_suggestion_owner ON user_suggestion(user_id, created_at DESC, id);
CREATE INDEX IF NOT EXISTS ix_user_suggestion_pending ON user_suggestion(created_at, id) WHERE reply IS NULL;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT, INSERT, UPDATE ON activity_translation TO damumu_app;
        GRANT SELECT, INSERT, UPDATE, DELETE ON user_suggestion TO damumu_app;
    END IF;
END $$;

COMMIT;

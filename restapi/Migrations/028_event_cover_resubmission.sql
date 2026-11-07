BEGIN;

ALTER TABLE event ADD COLUMN IF NOT EXISTS cover_review_reason text;
UPDATE event SET cover_review_reason='历史审核未记录原因'
WHERE cover_review_status='rejected' AND cover_review_reason IS NULL;

CREATE TABLE IF NOT EXISTS event_cover_review (
    media_asset_id uuid PRIMARY KEY REFERENCES media_asset(id) ON DELETE RESTRICT,
    event_id uuid NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    reason text,
    submitted_at timestamptz NOT NULL DEFAULT now(),
    reviewed_at timestamptz,
    CHECK ((status='pending') = (reviewed_at IS NULL)),
    CHECK (status<>'rejected' OR reason IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS ix_event_cover_review_history
    ON event_cover_review(event_id, submitted_at DESC);

INSERT INTO event_cover_review (
    media_asset_id, event_id, status, reason, submitted_at, reviewed_at)
SELECT e.cover_media_id, e.id, e.cover_review_status, e.cover_review_reason,
       COALESCE(e.updated_at, e.created_at),
       CASE WHEN e.cover_review_status='pending' THEN NULL
            ELSE COALESCE(e.updated_at, e.created_at) END
FROM event e
WHERE e.cover_media_id IS NOT NULL
ON CONFLICT (media_asset_id) DO NOTHING;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT, INSERT, UPDATE ON event_cover_review TO damumu_app;
    END IF;
END $$;

COMMIT;

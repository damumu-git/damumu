-- Verified post-event likes and participant-scoped reports.
BEGIN;

CREATE TABLE IF NOT EXISTS endorsement (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    context_event_id uuid NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    from_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    target_type varchar(16) NOT NULL CHECK (target_type IN ('activity', 'user')),
    target_id uuid NOT NULL,
    target_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    tag_code varchar(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (from_user_id <> target_user_id),
    UNIQUE (context_event_id, from_user_id, target_type, target_id)
);

ALTER TABLE report ADD COLUMN IF NOT EXISTS context_event_id uuid;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname='fk_report_context_event'
    ) THEN
        ALTER TABLE report
            ADD CONSTRAINT fk_report_context_event
            FOREIGN KEY (context_event_id) REFERENCES event(id) ON DELETE CASCADE;
    END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_report_participant_feedback
    ON report (context_event_id, reporter_user_id, target_type, target_id)
    WHERE context_event_id IS NOT NULL AND target_type IN ('activity', 'user');

CREATE INDEX IF NOT EXISTS ix_endorsement_target_user
    ON endorsement (target_user_id, tag_code, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_report_feedback_target_user
    ON report (reported_user_id, target_type, category_code, reporter_user_id)
    WHERE context_event_id IS NOT NULL AND status <> 'dismissed';

COMMIT;

BEGIN;

ALTER TABLE app_user
    ADD COLUMN IF NOT EXISTS minimum_age_confirmed_at timestamptz,
    ADD COLUMN IF NOT EXISTS privacy_notice_version varchar(32),
    ADD COLUMN IF NOT EXISTS privacy_notice_acknowledged_at timestamptz;
CREATE SEQUENCE IF NOT EXISTS muda_deleted_user_number;
ALTER TABLE event ALTER COLUMN min_age SET DEFAULT 14;

CREATE TABLE IF NOT EXISTS media_deletion_queue (
    storage_key text PRIMARY KEY,
    queued_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE media_deletion_queue ADD COLUMN IF NOT EXISTS is_directory boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS ix_message_retention ON message(created_at);
CREATE INDEX IF NOT EXISTS ix_report_retention ON report(created_at);

CREATE OR REPLACE FUNCTION muda_purge_expired_personal_data()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    -- Serialize cleanup across instances without blocking business requests.
    IF NOT pg_try_advisory_xact_lock(2220261021::bigint) THEN RETURN; END IF;

    DELETE FROM report WHERE created_at <= now()-interval '3 months';
    DELETE FROM moderation_action WHERE created_at <= now()-interval '3 months';
    DELETE FROM message WHERE created_at <= now()-interval '3 months';
    DELETE FROM notification WHERE created_at <= now()-interval '3 months';
    -- Retain minimal security audit facts for a year, removing user references
    -- and free-form snapshots after the normal content retention period.
    DELETE FROM audit_log WHERE created_at <= now()-interval '1 year';
    UPDATE audit_log SET actor_user_id=NULL, target_id=NULL, trace_id=NULL, metadata='{}'::jsonb
      WHERE created_at <= now()-interval '3 months'
        AND (actor_user_id IS NOT NULL OR target_id IS NOT NULL OR trace_id IS NOT NULL OR metadata<>'{}'::jsonb);

    CREATE TEMP TABLE IF NOT EXISTS privacy_expired_event(id uuid PRIMARY KEY) ON COMMIT DROP;
    TRUNCATE privacy_expired_event;
    INSERT INTO privacy_expired_event
    SELECT e.id FROM event e
    WHERE COALESCE(e.cancelled_at,
        (SELECT max(es.ends_at) FROM event_schedule es WHERE es.event_id=e.id),
        e.deleted_at, e.created_at) <= now()-interval '3 months';

    DELETE FROM notification WHERE data->>'eventId' IN (SELECT id::text FROM privacy_expired_event);
    DELETE FROM conversation WHERE event_id IN (SELECT id FROM privacy_expired_event);
    DELETE FROM event WHERE id IN (SELECT id FROM privacy_expired_event);
    DELETE FROM place p WHERE NOT EXISTS (SELECT 1 FROM event e WHERE e.place_id=p.id)
        AND p.created_at <= now()-interval '3 months';
    DELETE FROM conversation c WHERE c.updated_at <= now()-interval '3 months'
        AND c.event_id IS NULL AND NOT EXISTS (SELECT 1 FROM message m WHERE m.conversation_id=c.id);
    DELETE FROM safety_session WHERE COALESCE(ended_at, ends_at, started_at) <= now()-interval '3 months';

    -- A report's evidence has its own three-month clock, so do not remove media
    -- still needed by a newer report even when its original message has expired.
    WITH expired_media AS (
      DELETE FROM media_asset ma
      WHERE (ma.deleted_at IS NOT NULL OR ma.created_at <= now()-interval '1 day')
        AND NOT EXISTS (SELECT 1 FROM event e WHERE e.cover_media_id=ma.id)
        AND NOT EXISTS (SELECT 1 FROM message m WHERE m.media_asset_id=ma.id)
        AND NOT EXISTS (SELECT 1 FROM report_evidence re WHERE re.media_asset_id=ma.id)
      RETURNING storage_key, thumbnail_storage_key
    )
    INSERT INTO media_deletion_queue(storage_key)
    SELECT storage_key FROM expired_media
    UNION SELECT thumbnail_storage_key FROM expired_media WHERE thumbnail_storage_key IS NOT NULL
    ON CONFLICT DO NOTHING;

    -- These are technical tombstones, not a claim of irreversible anonymization.
    DELETE FROM app_user u WHERE u.status='deleted' AND u.deleted_at <= now()-interval '3 months'
        AND NOT EXISTS (SELECT 1 FROM event e WHERE e.organizer_user_id=u.id)
        AND NOT EXISTS (SELECT 1 FROM report r WHERE r.reporter_user_id=u.id);
END;
$$;

-- The documented Lightsail API role needs only the new queue and sequence
-- privileges; existing business-table DML grants remain unchanged.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON media_deletion_queue TO damumu_app;
        GRANT USAGE, SELECT ON SEQUENCE muda_deleted_user_number TO damumu_app;
        GRANT EXECUTE ON FUNCTION muda_purge_expired_personal_data() TO damumu_app;
    END IF;
END;
$$;

COMMIT;

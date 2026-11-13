BEGIN;
CREATE TABLE IF NOT EXISTS activity_series (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug text UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    owner_id uuid REFERENCES app_user(id) ON DELETE CASCADE,
    editor_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    title varchar(100) NOT NULL,
    description varchar(1000) NOT NULL,
    region_code varchar(32) REFERENCES administrative_region(code),
    guide_slug varchar(80) REFERENCES web_guide(slug) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS activity_series_event (
    event_id uuid PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE,
    series_id uuid NOT NULL REFERENCES activity_series(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS ix_activity_series_event_series ON activity_series_event(series_id);
CREATE TABLE IF NOT EXISTS activity_series_member (
    series_id uuid REFERENCES activity_series(id) ON DELETE CASCADE,
    user_id uuid REFERENCES app_user(id) ON DELETE CASCADE,
    subscribed boolean NOT NULL DEFAULT false,
    interest_slot text CHECK (interest_slot IN ('saturday','sunday','either')),
    PRIMARY KEY (series_id,user_id)
);
CREATE INDEX IF NOT EXISTS ix_activity_series_member_user ON activity_series_member(user_id);
CREATE TABLE IF NOT EXISTS activity_series_notice (
    event_id uuid PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS activity_recap (
    event_id uuid PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE,
    body varchar(2000) NOT NULL,
    show_cover boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now(),
    photo_ids uuid[] NOT NULL DEFAULT '{}' CHECK (cardinality(photo_ids)<=3)
);
CREATE INDEX IF NOT EXISTS ix_activity_recap_photos ON activity_recap USING gin(photo_ids);
CREATE OR REPLACE FUNCTION activity_recap_uses_media(media_id uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM activity_recap WHERE ARRAY[media_id] <@ photo_ids);
$$;
CREATE TABLE IF NOT EXISTS activity_series_proposal (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('organizer','venue')),
    region_code varchar(32) NOT NULL REFERENCES administrative_region(code),
    body varchar(1000) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO activity_series (slug,title,description,guide_slug)
VALUES ('damu-weekend','搭慕周末','一起散步、喝咖啡，认识同一个生活圈的人。可以先看路线指南，或留下你方便的周末时段。','river-walk')
ON CONFLICT (slug) DO NOTHING;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT,INSERT,UPDATE,DELETE ON activity_series,activity_series_event,
            activity_series_member,activity_series_notice,activity_recap,activity_series_proposal TO damumu_app;
    END IF;
END $$;
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
        AND NOT activity_recap_uses_media(ma.id)
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
COMMIT;

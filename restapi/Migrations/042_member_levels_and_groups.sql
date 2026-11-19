BEGIN;
CREATE TABLE IF NOT EXISTS member_identity_verification (
    user_id uuid PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
    provider text NOT NULL,
    verification_reference text NOT NULL,
    verified_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    UNIQUE(provider,verification_reference)
);
CREATE INDEX IF NOT EXISTS ix_event_member_reputation ON event(organizer_user_id)
    WHERE deleted_at IS NULL AND status IN ('published','full','completed');
CREATE OR REPLACE FUNCTION member_level(account_id uuid)
RETURNS integer LANGUAGE sql STABLE STRICT AS $$
    WITH successful AS MATERIALIZED (
        SELECT e.id FROM event e
        WHERE e.organizer_user_id=account_id AND e.deleted_at IS NULL
          AND e.status IN ('published','full','completed')
          AND EXISTS (SELECT 1 FROM event_schedule s WHERE s.event_id=e.id AND s.status='scheduled')
          AND NOT EXISTS (SELECT 1 FROM event_schedule s
                          WHERE s.event_id=e.id AND s.status='scheduled' AND s.ends_at>now())
          AND EXISTS (SELECT 1 FROM event_member m JOIN app_user attendee ON attendee.id=m.user_id
                      WHERE m.event_id=e.id AND m.user_id<>account_id AND m.status='attended'
                        AND m.left_at IS NULL AND attendee.deleted_at IS NULL AND attendee.status='active')
    ), progress AS (
        SELECT (SELECT count(*) FROM successful)>5 AS experienced,
               EXISTS (SELECT 1 FROM member_identity_verification v
                       WHERE v.user_id=account_id AND v.revoked_at IS NULL) AS verified
    ), reputation AS (
        SELECT experienced,verified,CASE WHEN experienced THEN (
            SELECT count(*) FROM endorsement en JOIN successful s ON s.id=en.context_event_id
            JOIN app_user reviewer ON reviewer.id=en.from_user_id
            WHERE en.target_user_id=account_id AND en.target_type='activity'
              AND reviewer.status='active' AND reviewer.deleted_at IS NULL
        )>50 ELSE false END AS reputable
        FROM progress
    )
    SELECT CASE WHEN reputable AND verified THEN 4 WHEN reputable OR verified THEN 3
                WHEN experienced THEN 2 ELSE 1 END FROM reputation
$$;

ALTER TABLE web_group ADD COLUMN IF NOT EXISTS capacity integer CHECK (capacity BETWEEN 2 AND 500);
ALTER TABLE web_group ADD COLUMN IF NOT EXISTS min_age smallint CHECK (min_age BETWEEN 14 AND 120);
ALTER TABLE web_group ADD COLUMN IF NOT EXISTS max_age smallint CHECK (max_age BETWEEN 14 AND 120 AND (min_age IS NULL OR max_age>=min_age));
ALTER TABLE web_group ADD COLUMN IF NOT EXISTS join_mode text NOT NULL DEFAULT 'open' CHECK (join_mode IN ('open','approval'));
ALTER TABLE web_group ADD COLUMN IF NOT EXISTS region_code varchar(32) REFERENCES administrative_region(code);
ALTER TABLE web_group ADD COLUMN IF NOT EXISTS category_ids uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE web_group ADD COLUMN IF NOT EXISTS cover_category_id uuid REFERENCES category(id) ON DELETE SET NULL;
ALTER TABLE web_group ADD COLUMN IF NOT EXISTS cover_storage_key text;
ALTER TABLE conversation ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES web_group(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX IF NOT EXISTS ix_conversation_group ON conversation(group_id) WHERE group_id IS NOT NULL;
CREATE TABLE IF NOT EXISTS web_group_application (
    group_id uuid REFERENCES web_group(id) ON DELETE CASCADE,
    user_id uuid REFERENCES app_user(id) ON DELETE CASCADE,
    requested_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(group_id,user_id)
);
CREATE TABLE IF NOT EXISTS web_group_announcement (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id uuid NOT NULL REFERENCES web_group(id) ON DELETE CASCADE,
    body varchar(500) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_web_group_announcement_latest ON web_group_announcement(group_id,created_at DESC,id DESC);
INSERT INTO conversation(conversation_type,group_id,title)
SELECT 'group',id,title FROM web_group ON CONFLICT DO NOTHING;
INSERT INTO conversation_member(conversation_id,user_id)
SELECT c.id,m.user_id FROM web_group_member m JOIN conversation c ON c.group_id=m.group_id
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION clear_revoked_member_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL OR NEW.status='deleted' THEN
        DELETE FROM member_identity_verification WHERE user_id=NEW.id;
        DELETE FROM web_group_application WHERE user_id=NEW.id;
        DELETE FROM web_group_member WHERE user_id=NEW.id;
        UPDATE conversation SET status='archived' WHERE group_id IN (
            SELECT id FROM web_group WHERE owner_id=NEW.id
        );
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_clear_revoked_member_identity ON app_user;
CREATE TRIGGER trg_clear_revoked_member_identity AFTER UPDATE OF status,deleted_at ON app_user
FOR EACH ROW EXECUTE FUNCTION clear_revoked_member_identity();
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT,INSERT,UPDATE,DELETE ON member_identity_verification,web_group_application,web_group_announcement TO damumu_app;
    END IF;
END $$;
COMMIT;

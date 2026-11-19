BEGIN;

CREATE TABLE IF NOT EXISTS event_recurrence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organizer_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    frequency text NOT NULL CHECK (frequency IN ('weekly','monthly')),
    occurrence_count smallint NOT NULL CHECK (occurrence_count BETWEEN 2 AND 12),
    first_starts_at timestamptz NOT NULL,
    first_ends_at timestamptz NOT NULL CHECK (first_ends_at > first_starts_at),
    template jsonb NOT NULL,
    paused boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_event_recurrence_owner ON event_recurrence(organizer_user_id);
ALTER TABLE event ADD COLUMN IF NOT EXISTS recurrence_id uuid REFERENCES event_recurrence(id) ON DELETE SET NULL;
ALTER TABLE event ADD COLUMN IF NOT EXISTS recurrence_index smallint;
CREATE UNIQUE INDEX IF NOT EXISTS uq_event_recurrence_occurrence
    ON event(recurrence_id,recurrence_index) WHERE recurrence_id IS NOT NULL;
ALTER TABLE event_member ADD COLUMN IF NOT EXISTS withdrawal_reason varchar(64);
CREATE INDEX IF NOT EXISTS ix_event_member_schedule_check ON event_member(user_id,event_id)
    WHERE status IN ('approved','attended','applied','waitlisted');

-- One guard row per user serializes admission decisions without modifying
-- profile/account version counters. Serializable callers retry on contention.
CREATE TABLE IF NOT EXISTS user_schedule_guard (
    user_id uuid PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
    version bigint NOT NULL DEFAULT 0
);
CREATE OR REPLACE FUNCTION lock_event_user(target_user uuid)
RETURNS void LANGUAGE sql VOLATILE AS $$
    INSERT INTO user_schedule_guard(user_id) VALUES(target_user)
    ON CONFLICT(user_id) DO UPDATE SET version=user_schedule_guard.version+1;
$$;

CREATE OR REPLACE FUNCTION enforce_event_user_schedule(target_event uuid, target_user uuid, confirmed boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE withdrawn record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM event WHERE id=target_event AND deleted_at IS NULL
        AND status IN ('published','full')) THEN RETURN; END IF;
    PERFORM lock_event_user(target_user);
    IF EXISTS (
        SELECT 1
        FROM event_schedule proposed
        JOIN event current_event ON current_event.id=proposed.event_id
        JOIN event_member existing_member ON existing_member.user_id=target_user
            AND existing_member.event_id<>target_event AND existing_member.status IN ('approved','attended')
        JOIN event existing_event ON existing_event.id=existing_member.event_id
        JOIN event_schedule existing_schedule ON existing_schedule.event_id=existing_event.id
        WHERE proposed.event_id=target_event AND proposed.status='scheduled'
          AND current_event.deleted_at IS NULL AND current_event.status IN ('published','full')
          AND existing_event.deleted_at IS NULL AND existing_event.status IN ('published','full')
          AND existing_schedule.status='scheduled'
          AND proposed.starts_at < existing_schedule.ends_at
          AND existing_schedule.starts_at < proposed.ends_at
    ) THEN
        RAISE EXCEPTION USING ERRCODE='23P01', CONSTRAINT='event_schedule_conflict',
            MESSAGE='event_schedule_conflict';
    END IF;
    IF NOT confirmed THEN RETURN; END IF;
    FOR withdrawn IN
        WITH candidates AS MATERIALIZED (
            SELECT m.id,m.event_id,m.status
            FROM event_member m JOIN event e ON e.id=m.event_id
            WHERE m.user_id=target_user AND m.event_id<>target_event
              AND m.status IN ('applied','waitlisted') AND e.deleted_at IS NULL
              AND e.status IN ('published','full')
              AND EXISTS (
                  SELECT 1 FROM event_schedule a JOIN event_schedule b
                    ON a.starts_at < b.ends_at AND b.starts_at < a.ends_at
                  WHERE a.event_id=target_event AND b.event_id=m.event_id
                    AND a.status='scheduled' AND b.status='scheduled'
              )
        )
        UPDATE event_member m SET status='withdrawn',left_at=now(),
            waitlist_position=NULL,withdrawal_reason='schedule_conflict'
        FROM candidates c WHERE m.id=c.id AND m.status IN ('applied','waitlisted')
        RETURNING m.event_id,c.status AS previous_status
    LOOP
        UPDATE event SET waitlist_count=greatest(0,waitlist_count-
            CASE WHEN withdrawn.previous_status='waitlisted' THEN 1 ELSE 0 END)
        WHERE id=withdrawn.event_id;
        INSERT INTO notification(user_id,notification_type,title,body,data)
        VALUES(target_user,'schedule_conflict_withdrawn','冲突申请已撤回',
            '另一场活动已确认加入，系统已撤回此次时间重叠的申请。',
            jsonb_build_object('eventId',withdrawn.event_id));
        INSERT INTO notification(user_id,notification_type,title,body,data)
        SELECT organizer_user_id,'schedule_conflict_withdrawn','参与申请已撤回',
            '一位参与者因行程冲突撤回了申请。',
            jsonb_build_object('eventId',id)
        FROM event WHERE id=withdrawn.event_id;
        -- Reuse the existing relay. PostgreSQL delivers NOTIFY only on commit.
        PERFORM pg_notify('muda_realtime', jsonb_build_object(
            'Origin','00000000-0000-0000-0000-000000000000',
            'UserIds',jsonb_build_array(target_user,
                (SELECT organizer_user_id FROM event WHERE id=withdrawn.event_id)),
            'Type','notification.created',
            'Data',jsonb_build_object('notificationType','schedule_conflict_withdrawn')
        )::text);
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION check_member_schedule()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status NOT IN ('applied','waitlisted','approved','attended') THEN RETURN NEW; END IF;
    IF TG_OP='UPDATE' THEN
        IF NEW.status=OLD.status AND NEW.event_id=OLD.event_id AND NEW.user_id=OLD.user_id THEN RETURN NEW; END IF;
    END IF;
    PERFORM enforce_event_user_schedule(NEW.event_id,NEW.user_id,NEW.status IN ('approved','attended'));
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_member_schedule ON event_member;
CREATE TRIGGER trg_member_schedule AFTER INSERT OR UPDATE OF status,event_id,user_id ON event_member
FOR EACH ROW EXECUTE FUNCTION check_member_schedule();

CREATE OR REPLACE FUNCTION check_event_schedule_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE member_row record;
BEGIN
    IF NEW.status<>'scheduled' THEN RETURN NEW; END IF;
    IF TG_OP='UPDATE' THEN
        IF NEW.starts_at=OLD.starts_at AND NEW.ends_at=OLD.ends_at AND NEW.status=OLD.status THEN RETURN NEW; END IF;
    END IF;
    FOR member_row IN SELECT user_id FROM event_member
        WHERE event_id=NEW.event_id AND status IN ('approved','attended') ORDER BY user_id
    LOOP
        PERFORM enforce_event_user_schedule(NEW.event_id,member_row.user_id,true);
    END LOOP;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_schedule_conflict ON event_schedule;
CREATE TRIGGER trg_schedule_conflict AFTER INSERT OR UPDATE OF starts_at,ends_at,status ON event_schedule
FOR EACH ROW EXECUTE FUNCTION check_event_schedule_change();

CREATE OR REPLACE FUNCTION check_event_reopened_schedule()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE member_row record;
BEGIN
    IF NEW.deleted_at IS NULL AND NEW.status IN ('published','full')
       AND (OLD.status NOT IN ('published','full') OR OLD.deleted_at IS NOT NULL) THEN
        FOR member_row IN SELECT user_id FROM event_member
            WHERE event_id=NEW.id AND status IN ('approved','attended') ORDER BY user_id
        LOOP
            PERFORM enforce_event_user_schedule(NEW.id,member_row.user_id,true);
        END LOOP;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_event_reopened_schedule ON event;
CREATE TRIGGER trg_event_reopened_schedule AFTER UPDATE OF status,deleted_at ON event
FOR EACH ROW EXECUTE FUNCTION check_event_reopened_schedule();

CREATE TABLE IF NOT EXISTS event_recurrence_reminder (
    recurrence_id uuid NOT NULL REFERENCES event_recurrence(id) ON DELETE CASCADE,
    occurrence_index smallint NOT NULL,
    PRIMARY KEY(recurrence_id,occurrence_index)
);
CREATE OR REPLACE FUNCTION clear_deleted_user_recurrences()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL OR NEW.status='deleted' THEN
        DELETE FROM event_recurrence WHERE organizer_user_id=NEW.id;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_clear_user_recurrences ON app_user;
CREATE TRIGGER trg_clear_user_recurrences AFTER UPDATE OF status,deleted_at ON app_user
FOR EACH ROW EXECUTE FUNCTION clear_deleted_user_recurrences();
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT,INSERT,UPDATE,DELETE ON event_recurrence,event_recurrence_reminder,user_schedule_guard TO damumu_app;
    END IF;
END $$;
COMMIT;

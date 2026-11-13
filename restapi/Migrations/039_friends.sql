BEGIN;

ALTER TABLE direct_contact_preference ADD COLUMN IF NOT EXISTS allow_friend_requests boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS friendship (
    first_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    second_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    PRIMARY KEY (first_id, second_id),
    CHECK (first_id < second_id)
);
CREATE INDEX IF NOT EXISTS ix_friendship_second ON friendship(second_id, first_id);

CREATE TABLE IF NOT EXISTS friend_request (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    recipient_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    body text CHECK (char_length(body) BETWEEN 1 AND 200),
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','accepted','declined','ignored','withdrawn','closed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    responded_at timestamptz,
    CHECK (sender_id <> recipient_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_friend_request_pending
    ON friend_request(least(sender_id,recipient_id),greatest(sender_id,recipient_id)) WHERE status='pending';
CREATE INDEX IF NOT EXISTS ix_friend_request_sender ON friend_request(sender_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ix_friend_request_recipient ON friend_request(recipient_id,created_at DESC);

CREATE OR REPLACE FUNCTION lock_friend_pair(sender uuid, recipient uuid)
RETURNS void LANGUAGE sql AS $$
    SELECT pg_advisory_xact_lock(hashtextextended('friend-pair:' || least(sender,recipient)::text || ':' ||
                                                greatest(sender,recipient)::text,0));
$$;

CREATE OR REPLACE FUNCTION friend_request_eligible(sender uuid, recipient uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT direct_contact_visible(sender,recipient)
        AND COALESCE((SELECT allow_friend_requests FROM direct_contact_preference WHERE user_id=recipient),true)
        AND NOT EXISTS (SELECT 1 FROM friendship WHERE first_id=least(sender,recipient) AND second_id=greatest(sender,recipient))
        AND NOT EXISTS (SELECT 1 FROM friend_request r WHERE r.sender_id=sender AND r.recipient_id=recipient
                        AND r.status IN ('declined','ignored','closed') AND r.responded_at>now()-interval '7 days')
        AND (
            (EXISTS (SELECT 1 FROM web_follow WHERE user_id=sender AND target_id=recipient)
             AND EXISTS (SELECT 1 FROM web_follow WHERE user_id=recipient AND target_id=sender))
            OR EXISTS (
                SELECT 1 FROM event_member a JOIN event_member b ON b.event_id=a.event_id
                JOIN event e ON e.id=a.event_id
                WHERE a.user_id=sender AND b.user_id=recipient AND a.status='attended' AND b.status='attended'
                  AND a.left_at IS NULL AND b.left_at IS NULL AND e.deleted_at IS NULL AND e.status<>'cancelled'
            )
        );
$$;

CREATE OR REPLACE FUNCTION direct_chat_allowed(sender uuid, recipient uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT direct_contact_visible(sender,recipient) AND (
        EXISTS (SELECT 1 FROM friendship WHERE first_id=least(sender,recipient) AND second_id=greatest(sender,recipient))
        OR EXISTS (
            SELECT 1 FROM direct_contact_request
            WHERE status='accepted' AND conversation_id IS NOT NULL
              AND ((sender_id=sender AND recipient_id=recipient)
                OR (sender_id=recipient AND recipient_id=sender))
        ) OR (
            EXISTS (SELECT 1 FROM web_follow WHERE user_id=sender AND target_id=recipient)
            AND EXISTS (SELECT 1 FROM web_follow WHERE user_id=recipient AND target_id=sender)
        )
    );
$$;

CREATE OR REPLACE FUNCTION respond_friend_request(request_id uuid, viewer uuid, decision text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pending friend_request%ROWTYPE;
BEGIN
    SELECT * INTO pending FROM friend_request WHERE id=request_id;
    IF NOT FOUND OR decision NOT IN ('accepted','declined','ignored','withdrawn') OR
        viewer <> (CASE WHEN decision='withdrawn' THEN pending.sender_id ELSE pending.recipient_id END)
    THEN RETURN NULL; END IF;
    PERFORM lock_friend_pair(pending.sender_id,pending.recipient_id);
    IF NOT direct_contact_visible(pending.sender_id,pending.recipient_id) THEN RETURN NULL; END IF;
    UPDATE friend_request SET status=decision,responded_at=now() WHERE id=request_id AND status='pending';
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF decision='accepted' THEN
        INSERT INTO friendship(first_id,second_id)
        VALUES (least(pending.sender_id,pending.recipient_id),greatest(pending.sender_id,pending.recipient_id))
        ON CONFLICT DO NOTHING;
        INSERT INTO notification(user_id,notification_type,title,body,data)
        VALUES (pending.sender_id,'friend_accepted','好友申请已通过','可以在好友列表中开始聊天。',
                jsonb_build_object('userId',pending.recipient_id));
    END IF;
    UPDATE notification SET read_at=COALESCE(read_at,now())
    WHERE user_id=pending.recipient_id AND notification_type='friend_request' AND data->>'requestId'=request_id::text;
    RETURN CASE WHEN decision='withdrawn' THEN pending.recipient_id ELSE pending.sender_id END;
END $$;

CREATE OR REPLACE FUNCTION send_friend_request(sender uuid, recipient uuid, note text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE pending friend_request%ROWTYPE;
DECLARE new_id uuid;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('friend-quota:' || sender::text,0));
    PERFORM lock_friend_pair(sender,recipient);
    SELECT * INTO pending FROM friend_request
    WHERE least(sender_id,recipient_id)=least(sender,recipient)
      AND greatest(sender_id,recipient_id)=greatest(sender,recipient) AND status='pending';
    IF FOUND AND direct_contact_visible(sender,recipient) THEN
        IF pending.sender_id=sender THEN RETURN 'pending'; END IF;
        IF respond_friend_request(pending.id,sender,'accepted') IS NOT NULL THEN RETURN 'accepted'; END IF;
    END IF;
    IF NOT friend_request_eligible(sender,recipient) THEN RETURN 'unavailable'; END IF;
    IF (SELECT count(*) FROM friend_request WHERE sender_id=sender AND created_at>now()-interval '24 hours')>=10
    THEN RETURN 'limited'; END IF;
    INSERT INTO friend_request(sender_id,recipient_id,body) VALUES (sender,recipient,note) RETURNING id INTO new_id;
    INSERT INTO notification(user_id,notification_type,title,body,data)
    VALUES (recipient,'friend_request','收到好友申请','可在消息中处理好友申请。',jsonb_build_object('requestId',new_id));
    RETURN 'created';
END $$;

CREATE OR REPLACE FUNCTION remove_friend(viewer uuid, peer uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM lock_friend_pair(viewer,peer);
    DELETE FROM friendship WHERE first_id=least(viewer,peer) AND second_id=greatest(viewer,peer);
END $$;

CREATE OR REPLACE FUNCTION close_blocked_friend_requests()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM lock_friend_pair(NEW.blocker_user_id,NEW.blocked_user_id);
    WITH closed AS (
        UPDATE friend_request SET status='closed',responded_at=now()
        WHERE least(sender_id,recipient_id)=least(NEW.blocker_user_id,NEW.blocked_user_id)
          AND greatest(sender_id,recipient_id)=greatest(NEW.blocker_user_id,NEW.blocked_user_id)
          AND status='pending'
        RETURNING id,recipient_id
    )
    UPDATE notification n SET read_at=COALESCE(n.read_at,now()) FROM closed r
    WHERE n.user_id=r.recipient_id AND n.notification_type='friend_request' AND n.data->>'requestId'=r.id::text;
    PERFORM remove_friend(NEW.blocker_user_id,NEW.blocked_user_id);
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS close_friend_requests_after_block ON user_block;
CREATE TRIGGER close_friend_requests_after_block AFTER INSERT OR UPDATE ON user_block
FOR EACH ROW EXECUTE FUNCTION close_blocked_friend_requests();

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON friendship, friend_request TO damumu_app;
    END IF;
END $$;

COMMIT;

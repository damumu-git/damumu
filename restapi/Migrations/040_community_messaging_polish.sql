BEGIN;

ALTER TABLE event ADD COLUMN IF NOT EXISTS confirmed_at timestamptz;

CREATE TABLE IF NOT EXISTS ended_friendship (
    first_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    second_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    ended_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (first_id, second_id),
    CHECK (first_id < second_id)
);

CREATE OR REPLACE FUNCTION direct_chat_allowed(sender uuid, recipient uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT direct_contact_visible(sender,recipient)
      AND NOT EXISTS (
          SELECT 1 FROM ended_friendship
          WHERE first_id=least(sender,recipient) AND second_id=greatest(sender,recipient)
      )
      AND (
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
        DELETE FROM ended_friendship
        WHERE first_id=least(pending.sender_id,pending.recipient_id)
          AND second_id=greatest(pending.sender_id,pending.recipient_id);
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

CREATE OR REPLACE FUNCTION remove_friend(viewer uuid, peer uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE direct_conversation uuid;
DECLARE removed boolean;
BEGIN
    PERFORM lock_friend_pair(viewer,peer);
    WITH deleted AS (
        DELETE FROM friendship
        WHERE first_id=least(viewer,peer) AND second_id=greatest(viewer,peer)
        RETURNING 1
    ) SELECT EXISTS(SELECT 1 FROM deleted) INTO removed;
    IF NOT removed THEN RETURN; END IF;

    INSERT INTO ended_friendship(first_id,second_id,ended_at)
    VALUES (least(viewer,peer),greatest(viewer,peer),now())
    ON CONFLICT (first_id,second_id) DO UPDATE SET ended_at=EXCLUDED.ended_at;

    SELECT c.id INTO direct_conversation
    FROM conversation c
    JOIN conversation_member a ON a.conversation_id=c.id AND a.user_id=viewer AND a.left_at IS NULL
    JOIN conversation_member b ON b.conversation_id=c.id AND b.user_id=peer AND b.left_at IS NULL
    WHERE c.conversation_type='direct'
    ORDER BY c.created_at DESC LIMIT 1;
    IF direct_conversation IS NOT NULL THEN
        INSERT INTO message(conversation_id,sender_user_id,message_type,body)
        VALUES (direct_conversation,NULL,'system','对方不是好友，私信已变为只读');
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON ended_friendship TO damumu_app;
    END IF;
END $$;

COMMIT;

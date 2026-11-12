BEGIN;

CREATE TABLE IF NOT EXISTS direct_contact_preference (
    user_id uuid PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
    allow_attended_requests boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS direct_contact_request (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    recipient_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    event_id uuid REFERENCES event(id) ON DELETE SET NULL,
    kind text NOT NULL CHECK (kind IN ('inquiry','attended')),
    body text CHECK (char_length(body) BETWEEN 1 AND 500),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')),
    conversation_id uuid REFERENCES conversation(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    responded_at timestamptz,
    UNIQUE (sender_id, recipient_id, event_id, kind),
    CHECK (sender_id <> recipient_id),
    CHECK (body IS NOT NULL OR status <> 'pending')
);
CREATE INDEX IF NOT EXISTS ix_direct_contact_recipient
    ON direct_contact_request(recipient_id, status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_direct_contact_pending_attended
    ON direct_contact_request(sender_id, recipient_id) WHERE status='pending' AND kind='attended';

CREATE OR REPLACE FUNCTION direct_contact_visible(sender uuid, recipient uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT sender <> recipient
        AND (SELECT count(*) FROM app_user WHERE id IN (sender,recipient) AND status='active' AND deleted_at IS NULL)=2
        AND NOT EXISTS (
            SELECT 1 FROM user_block
            WHERE (blocker_user_id=sender AND blocked_user_id=recipient)
               OR (blocker_user_id=recipient AND blocked_user_id=sender)
        );
$$;

CREATE OR REPLACE FUNCTION direct_chat_allowed(sender uuid, recipient uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT direct_contact_visible(sender,recipient) AND (
        EXISTS (
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

CREATE OR REPLACE FUNCTION open_direct_contact(sender uuid, recipient uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE thread uuid;
BEGIN
    INSERT INTO conversation (conversation_type, direct_key)
    VALUES ('direct', replace(least(sender,recipient)::text,'-','') || ':' ||
                      replace(greatest(sender,recipient)::text,'-',''))
    ON CONFLICT (direct_key) WHERE conversation_type='direct'
    DO UPDATE SET updated_at=now()
    RETURNING id INTO thread;

    INSERT INTO conversation_member (conversation_id,user_id)
    VALUES (thread,sender),(thread,recipient)
    ON CONFLICT (conversation_id,user_id)
    DO UPDATE SET left_at=NULL, hidden_at=CASE WHEN conversation_member.user_id=sender
                    THEN NULL ELSE conversation_member.hidden_at END;
    RETURN thread;
END $$;

CREATE OR REPLACE FUNCTION respond_direct_contact(request_id uuid, viewer uuid, accept_request boolean)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE contact direct_contact_request%ROWTYPE;
DECLARE thread uuid;
BEGIN
    SELECT * INTO contact FROM direct_contact_request
    WHERE id=request_id AND recipient_id=viewer FOR UPDATE;
    IF NOT FOUND THEN RETURN false; END IF;
    IF contact.status <> 'pending' THEN
        RETURN contact.status = CASE WHEN accept_request THEN 'accepted' ELSE 'declined' END;
    END IF;
    IF accept_request THEN
        IF NOT direct_contact_visible(contact.sender_id,viewer) THEN RETURN false; END IF;
        thread := open_direct_contact(contact.sender_id,viewer);
        INSERT INTO message (conversation_id,sender_user_id,message_type,body)
        VALUES (thread,contact.sender_id,'text',contact.body);
        UPDATE conversation_member SET hidden_at=NULL WHERE conversation_id=thread AND left_at IS NULL;
        INSERT INTO notification (user_id,notification_type,title,body,data)
        VALUES (contact.sender_id,'contact_accepted','联系请求已接受','可以在私信中继续沟通。',
                jsonb_build_object('conversationId',thread));
    END IF;
    UPDATE direct_contact_request SET status=CASE WHEN accept_request THEN 'accepted' ELSE 'declined' END,
        conversation_id=thread, responded_at=now()
    WHERE id=request_id;
    UPDATE notification SET read_at=COALESCE(read_at,now())
    WHERE user_id=viewer AND notification_type='contact_request' AND data->>'requestId'=request_id::text;
    RETURN true;
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON direct_contact_preference, direct_contact_request TO damumu_app;
    END IF;
END $$;

COMMIT;

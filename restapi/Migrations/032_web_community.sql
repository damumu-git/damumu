BEGIN;

CREATE TABLE IF NOT EXISTS web_intent (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    title varchar(100) NOT NULL,
    description varchar(1000) NOT NULL,
    region_code varchar(32) NOT NULL REFERENCES administrative_region(code),
    event_id uuid REFERENCES event(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS web_intent_vote (
    intent_id uuid NOT NULL REFERENCES web_intent(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    slot varchar(16) NOT NULL CHECK (slot IN ('saturday','sunday','either')),
    PRIMARY KEY (intent_id,user_id)
);

CREATE TABLE IF NOT EXISTS web_group (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    title varchar(100) NOT NULL,
    description varchar(1000) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS web_group_member (
    group_id uuid NOT NULL REFERENCES web_group(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    PRIMARY KEY (group_id,user_id)
);

CREATE TABLE IF NOT EXISTS web_group_event (
    group_id uuid NOT NULL REFERENCES web_group(id) ON DELETE CASCADE,
    event_id uuid NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    PRIMARY KEY (group_id,event_id)
);

CREATE TABLE IF NOT EXISTS web_follow (
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    target_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id,target_id),
    CHECK (user_id<>target_id)
);

CREATE INDEX IF NOT EXISTS ix_web_intent_vote_user ON web_intent_vote(user_id);
CREATE INDEX IF NOT EXISTS ix_web_group_member_user ON web_group_member(user_id);
CREATE INDEX IF NOT EXISTS ix_web_group_event_event ON web_group_event(event_id);
CREATE INDEX IF NOT EXISTS ix_web_follow_target ON web_follow(target_id);

COMMIT;

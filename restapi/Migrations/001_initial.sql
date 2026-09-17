-- DAMUMU base schema. Safe to run repeatedly on an empty or partially initialized database.
-- Requires PostgreSQL with PostGIS (for place.public_geo) and pgcrypto.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE OR REPLACE FUNCTION muda_touch_row()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    IF TG_ARGV[0] = 'versioned' THEN
        NEW.row_version := OLD.row_version + 1;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS app_user (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    status varchar(32) NOT NULL DEFAULT 'active',
    role varchar(32) NOT NULL DEFAULT 'user',
    locale varchar(16) NOT NULL DEFAULT 'zh-CN',
    timezone varchar(64) NOT NULL DEFAULT 'Asia/Seoul',
    adult_confirmed_at timestamptz,
    last_login_at timestamptz,
    deletion_requested_at timestamptz,
    deleted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_profile (
    user_id uuid PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
    nickname varchar(80) NOT NULL,
    avatar_url text,
    bio varchar(1000),
    city_code varchar(32),
    district_code varchar(64),
    languages varchar(16)[] NOT NULL DEFAULT ARRAY[]::varchar[],
    gender varchar(32),
    occupation varchar(120),
    arrival_year smallint,
    profile_completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS category (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(64) NOT NULL UNIQUE,
    name_zh_cn varchar(80) NOT NULL,
    name_ko_kr varchar(80),
    icon varchar(32),
    sort_order integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS interest (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(64) NOT NULL UNIQUE,
    name_zh_cn varchar(80) NOT NULL,
    name_ko_kr varchar(80),
    icon varchar(32),
    sort_order integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_interest (
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    interest_id uuid NOT NULL REFERENCES interest(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, interest_id)
);

CREATE TABLE IF NOT EXISTS trust_snapshot (
    user_id uuid PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
    score numeric(5,2) NOT NULL DEFAULT 0,
    review_count integer NOT NULL DEFAULT 0,
    attended_count integer NOT NULL DEFAULT 0,
    no_show_count integer NOT NULL DEFAULT 0,
    organized_count integer NOT NULL DEFAULT 0,
    tag_counts jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS media_asset (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    storage_key text NOT NULL,
    mime_type varchar(120) NOT NULL,
    byte_size bigint,
    width integer,
    height integer,
    status varchar(32) NOT NULL DEFAULT 'ready',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS place (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider varchar(32) NOT NULL DEFAULT 'manual',
    provider_place_id text,
    name varchar(200) NOT NULL,
    city_code varchar(32) NOT NULL,
    district_code varchar(64),
    address_public text,
    public_geo geography(Point, 4326),
    created_by_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS event (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organizer_user_id uuid NOT NULL REFERENCES app_user(id),
    category_id uuid NOT NULL REFERENCES category(id),
    place_id uuid REFERENCES place(id) ON DELETE SET NULL,
    cover_media_id uuid REFERENCES media_asset(id) ON DELETE SET NULL,
    title varchar(160) NOT NULL,
    description text NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'draft',
    visibility varchar(32) NOT NULL DEFAULT 'public',
    approval_mode varchar(32) NOT NULL DEFAULT 'manual',
    capacity smallint NOT NULL CHECK (capacity > 0),
    approved_count smallint NOT NULL DEFAULT 0 CHECK (approved_count >= 0),
    waitlist_count smallint NOT NULL DEFAULT 0 CHECK (waitlist_count >= 0),
    min_age smallint NOT NULL DEFAULT 18,
    max_age smallint,
    price_amount numeric(12,2) NOT NULL DEFAULT 0,
    price_currency varchar(3) NOT NULL DEFAULT 'KRW',
    city_code varchar(32) NOT NULL,
    district_code varchar(64),
    language_codes varchar(16)[] NOT NULL DEFAULT ARRAY['zh-CN']::varchar[],
    published_at timestamptz,
    cancelled_at timestamptz,
    cancellation_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CHECK (max_age IS NULL OR max_age >= min_age)
);

CREATE TABLE IF NOT EXISTS event_schedule (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    check_in_opens_at timestamptz,
    check_in_closes_at timestamptz,
    timezone varchar(64) NOT NULL DEFAULT 'Asia/Seoul',
    status varchar(32) NOT NULL DEFAULT 'scheduled',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS event_tag (
    event_id uuid NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    interest_id uuid NOT NULL REFERENCES interest(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, interest_id)
);

CREATE TABLE IF NOT EXISTS event_member (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    member_role varchar(32) NOT NULL DEFAULT 'participant',
    status varchar(32) NOT NULL DEFAULT 'applied',
    waitlist_position integer,
    application_note text,
    reviewed_by_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    reviewed_at timestamptz,
    joined_at timestamptz,
    checked_in_at timestamptz,
    check_in_method varchar(32),
    left_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (event_id, user_id)
);

CREATE TABLE IF NOT EXISTS conversation (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_type varchar(32) NOT NULL,
    direct_key varchar(80),
    event_id uuid REFERENCES event(id) ON DELETE SET NULL,
    title varchar(160),
    status varchar(32) NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_conversation_direct_key
    ON conversation (direct_key) WHERE conversation_type='direct';

CREATE TABLE IF NOT EXISTS message (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
    sender_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    message_type varchar(32) NOT NULL DEFAULT 'text',
    body text,
    media_asset_id uuid REFERENCES media_asset(id) ON DELETE SET NULL,
    reply_to_message_id uuid REFERENCES message(id) ON DELETE SET NULL,
    client_message_id uuid,
    edited_at timestamptz,
    recalled_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (sender_user_id, client_message_id)
);

CREATE TABLE IF NOT EXISTS conversation_member (
    conversation_id uuid NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    last_read_message_id uuid REFERENCES message(id) ON DELETE SET NULL,
    last_read_at timestamptz,
    muted_until timestamptz,
    joined_at timestamptz NOT NULL DEFAULT now(),
    left_at timestamptz,
    PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS review (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    from_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    to_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    tags varchar(64)[] NOT NULL DEFAULT ARRAY[]::varchar[],
    comment text,
    visibility varchar(32) NOT NULL DEFAULT 'aggregate',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (event_id, from_user_id, to_user_id),
    CHECK (from_user_id <> to_user_id)
);

CREATE TABLE IF NOT EXISTS emergency_contact (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    name_ciphertext bytea NOT NULL,
    phone_ciphertext bytea NOT NULL,
    phone_hash bytea NOT NULL,
    relationship_ciphertext bytea,
    is_primary boolean NOT NULL DEFAULT false,
    verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS safety_session (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    event_id uuid REFERENCES event(id) ON DELETE SET NULL,
    emergency_contact_id uuid REFERENCES emergency_contact(id) ON DELETE SET NULL,
    status varchar(32) NOT NULL DEFAULT 'active',
    check_in_interval_minutes smallint NOT NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    next_due_at timestamptz NOT NULL,
    ends_at timestamptz,
    ended_at timestamptz,
    location_consent_at timestamptz,
    latest_location_ciphertext bytea,
    location_expires_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS safety_checkin (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    safety_session_id uuid NOT NULL REFERENCES safety_session(id) ON DELETE CASCADE,
    status varchar(32) NOT NULL,
    note_ciphertext bytea,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS safety_alert (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    safety_session_id uuid NOT NULL REFERENCES safety_session(id) ON DELETE CASCADE,
    alert_type varchar(64) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'open',
    contact_notified_at timestamptz,
    resolved_at timestamptz,
    resolution_note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS report (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_user_id uuid NOT NULL REFERENCES app_user(id),
    target_type varchar(32) NOT NULL,
    target_id uuid NOT NULL,
    reported_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    category_code varchar(64) NOT NULL,
    description text,
    priority smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
    status varchar(32) NOT NULL DEFAULT 'submitted',
    assigned_to_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    resolution_code varchar(64),
    resolved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS report_evidence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id uuid NOT NULL REFERENCES report(id) ON DELETE CASCADE,
    evidence_type varchar(32) NOT NULL,
    media_asset_id uuid REFERENCES media_asset(id) ON DELETE SET NULL,
    snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    retention_until timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS moderation_action (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id uuid REFERENCES report(id) ON DELETE SET NULL,
    moderator_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    target_type varchar(32) NOT NULL,
    target_id uuid NOT NULL,
    action_type varchar(64) NOT NULL,
    reason_code varchar(64),
    reason_note text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notification (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    notification_type varchar(64) NOT NULL,
    title varchar(160) NOT NULL,
    body text NOT NULL,
    data jsonb NOT NULL DEFAULT '{}'::jsonb,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_block (
    blocker_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    blocked_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    reason_code varchar(64),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_user_id, blocked_user_id),
    CHECK (blocker_user_id <> blocked_user_id)
);

CREATE TABLE IF NOT EXISTS app_config (
    key varchar(120) PRIMARY KEY,
    value jsonb NOT NULL,
    is_public boolean NOT NULL DEFAULT false,
    version bigint NOT NULL DEFAULT 1,
    updated_by_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS feature_flag (
    key varchar(120) PRIMARY KEY,
    description text,
    enabled boolean NOT NULL DEFAULT false,
    rules jsonb NOT NULL DEFAULT '{}'::jsonb,
    version bigint NOT NULL DEFAULT 1,
    updated_by_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
    actor_role varchar(32) NOT NULL,
    action varchar(160) NOT NULL,
    target_type varchar(64),
    target_id uuid,
    trace_id text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_place_public_geo ON place USING gist (public_geo);
CREATE INDEX IF NOT EXISTS ix_event_discovery ON event (status, visibility, city_code, category_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_event_schedule_event_starts ON event_schedule (event_id, starts_at);
CREATE INDEX IF NOT EXISTS ix_event_member_user_created ON event_member (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_message_conversation_created ON message (conversation_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_report_queue ON report (status, priority, created_at);
CREATE INDEX IF NOT EXISTS ix_notification_user_created ON notification (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_safety_session_user_status ON safety_session (user_id, status, created_at DESC);

DROP TRIGGER IF EXISTS trg_app_user_touch ON app_user;
CREATE TRIGGER trg_app_user_touch BEFORE UPDATE ON app_user
FOR EACH ROW EXECUTE FUNCTION muda_touch_row('versioned');
DROP TRIGGER IF EXISTS trg_user_profile_touch ON user_profile;
CREATE TRIGGER trg_user_profile_touch BEFORE UPDATE ON user_profile
FOR EACH ROW EXECUTE FUNCTION muda_touch_row('versioned');
DROP TRIGGER IF EXISTS trg_event_touch ON event;
CREATE TRIGGER trg_event_touch BEFORE UPDATE ON event
FOR EACH ROW EXECUTE FUNCTION muda_touch_row('versioned');
DROP TRIGGER IF EXISTS trg_report_touch ON report;
CREATE TRIGGER trg_report_touch BEFORE UPDATE ON report
FOR EACH ROW EXECUTE FUNCTION muda_touch_row('versioned');
DROP TRIGGER IF EXISTS trg_safety_session_touch ON safety_session;
CREATE TRIGGER trg_safety_session_touch BEFORE UPDATE ON safety_session
FOR EACH ROW EXECUTE FUNCTION muda_touch_row('versioned');
DROP TRIGGER IF EXISTS trg_safety_alert_touch ON safety_alert;
CREATE TRIGGER trg_safety_alert_touch BEFORE UPDATE ON safety_alert
FOR EACH ROW EXECUTE FUNCTION muda_touch_row();
DROP TRIGGER IF EXISTS trg_event_member_touch ON event_member;
CREATE TRIGGER trg_event_member_touch BEFORE UPDATE ON event_member
FOR EACH ROW EXECUTE FUNCTION muda_touch_row();
DROP TRIGGER IF EXISTS trg_feature_flag_touch ON feature_flag;
CREATE TRIGGER trg_feature_flag_touch BEFORE UPDATE ON feature_flag
FOR EACH ROW EXECUTE FUNCTION muda_touch_row();

INSERT INTO category (code, name_zh_cn, name_ko_kr, icon, sort_order) VALUES
    ('food', '美食探店', '맛집 탐방', '🍜', 10),
    ('sports', '运动健身', '운동', '🏃', 20),
    ('culture', '文化艺术', '문화 예술', '🎭', 30),
    ('outdoors', '户外旅行', '야외 여행', '🏕️', 40),
    ('study', '学习交流', '스터디', '📚', 50),
    ('social', '轻松社交', '소셜 모임', '✨', 60)
ON CONFLICT (code) DO NOTHING;

INSERT INTO interest (code, name_zh_cn, name_ko_kr, icon, sort_order) VALUES
    ('coffee', '咖啡', '커피', '☕', 10),
    ('food', '美食', '맛집', '🍚', 20),
    ('hiking', '徒步', '등산', '🥾', 30),
    ('fitness', '健身', '운동', '🏋️', 40),
    ('movies', '电影', '영화', '🎬', 50),
    ('language', '语言交换', '언어 교환', '💬', 60),
    ('photography', '摄影', '사진', '📷', 70),
    ('games', '桌游', '보드게임', '🎲', 80)
ON CONFLICT (code) DO NOTHING;

INSERT INTO app_config (key, value, is_public) VALUES
    ('support', '{"email":"support@example.com"}'::jsonb, true),
    ('event_limits', '{"maxCapacity":100,"maxInterests":10}'::jsonb, true)
ON CONFLICT (key) DO NOTHING;

INSERT INTO feature_flag (key, description, enabled) VALUES
    ('event_creation', '允许用户发布活动', true),
    ('direct_messages', '允许用户发起私信', true),
    ('safety_checkin', '安全会面签到功能', true)
ON CONFLICT (key) DO NOTHING;

COMMIT;

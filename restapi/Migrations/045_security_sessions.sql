BEGIN;

CREATE TABLE IF NOT EXISTS auth_session (
    token_hash text PRIMARY KEY,
    id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    access_expires_at timestamptz NOT NULL,
    previous_access_hash text,
    previous_access_expires_at timestamptz,
    refresh_hash text UNIQUE,
    previous_refresh_hash text,
    rotated_at timestamptz,
    revoked_at timestamptz
);
CREATE INDEX IF NOT EXISTS ix_auth_session_user ON auth_session(user_id,expires_at);
ALTER TABLE auth_session ADD COLUMN IF NOT EXISTS previous_access_hash text;
ALTER TABLE auth_session ADD COLUMN IF NOT EXISTS previous_access_expires_at timestamptz;
CREATE INDEX IF NOT EXISTS ix_auth_session_previous_refresh ON auth_session(previous_refresh_hash);
CREATE INDEX IF NOT EXISTS ix_auth_session_previous_access ON auth_session(previous_access_hash);
CREATE TABLE IF NOT EXISTS admin_account (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    username text NOT NULL UNIQUE,
    password_hash text NOT NULL,
    totp_secret text NOT NULL,
    last_totp_step bigint NOT NULL DEFAULT -1,
    role text NOT NULL CHECK(role IN ('owner','moderator','viewer')),
    enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS admin_session (
    token_hash text PRIMARY KEY,
    admin_id uuid NOT NULL REFERENCES admin_account(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS admin_account_id uuid REFERENCES admin_account(id);
CREATE OR REPLACE FUNCTION revoke_disabled_account_sessions()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status<>'active' OR NEW.deleted_at IS NOT NULL THEN
        UPDATE auth_session SET revoked_at=now() WHERE user_id=NEW.id AND revoked_at IS NULL;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS revoke_sessions_after_account_change ON app_user;
CREATE TRIGGER revoke_sessions_after_account_change AFTER UPDATE OF status,deleted_at ON app_user
FOR EACH ROW EXECUTE FUNCTION revoke_disabled_account_sessions();
CREATE TABLE IF NOT EXISTS auth_attempt (
    bucket text PRIMARY KEY,
    failures integer NOT NULL DEFAULT 0,
    window_started_at timestamptz NOT NULL DEFAULT now(),
    blocked_until timestamptz
);

-- Retain empty legacy tables for the existing retention function and old backup restores.
DELETE FROM safety_session;
DELETE FROM emergency_contact;
DELETE FROM feature_flag WHERE key IN ('safety_checkin','safety_sessions','emergency_contacts');
DO $$
BEGIN
    IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT,INSERT,UPDATE,DELETE ON auth_session,admin_account,admin_session,auth_attempt TO damumu_app;
    END IF;
END $$;
COMMIT;

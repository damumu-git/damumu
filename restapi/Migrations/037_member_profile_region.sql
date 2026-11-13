BEGIN;

ALTER TABLE user_profile
    ADD COLUMN IF NOT EXISTS home_region_code varchar(32) REFERENCES administrative_region(code) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS show_home_region boolean NOT NULL DEFAULT false;

ALTER TABLE web_follow ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS ix_web_follow_user_recent ON web_follow(user_id,created_at DESC,target_id);

COMMIT;

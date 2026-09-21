CREATE TABLE IF NOT EXISTS push_device (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    provider varchar(20) NOT NULL DEFAULT 'fcm' CHECK (provider IN ('fcm')),
    platform varchar(20) NOT NULL CHECK (platform IN ('android', 'ios', 'web', 'macos')),
    registration_token text NOT NULL,
    enabled boolean NOT NULL DEFAULT true,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (registration_token)
);

CREATE INDEX IF NOT EXISTS ix_push_device_user_enabled
    ON push_device (user_id, enabled)
    WHERE enabled=true;

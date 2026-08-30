-- 正式用户认证。可重复执行。
CREATE TABLE IF NOT EXISTS user_credential (
    user_id uuid PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
    email varchar(254) NOT NULL,
    password_hash text NOT NULL,
    email_verified_at timestamptz,
    last_login_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_credential_email_normalized
    ON user_credential (lower(email));

COMMENT ON COLUMN user_profile.avatar_url IS
    'system:<key> 或服务端生成的 /uploads/avatars/<user>/<file>.jpg';

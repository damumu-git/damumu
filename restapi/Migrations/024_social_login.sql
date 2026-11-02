-- Google / Kakao stable provider identities. No provider tokens or email copies.
CREATE TABLE IF NOT EXISTS user_external_identity (
    provider varchar(16) NOT NULL CHECK (provider IN ('google', 'kakao')),
    subject varchar(255) NOT NULL CHECK (length(subject) > 0),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_login_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, subject),
    UNIQUE (user_id, provider)
);
COMMENT ON TABLE user_external_identity IS
    'Verified provider subject, never client-supplied profile IDs; removed on account deletion. No email-based auto-linking.';

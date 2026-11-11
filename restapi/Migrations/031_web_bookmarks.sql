BEGIN;

CREATE TABLE IF NOT EXISTS web_bookmark (
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    kind varchar(10) NOT NULL CHECK (kind IN ('activity','guide')),
    target varchar(80) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, kind, target)
);

COMMIT;

BEGIN;

CREATE TABLE IF NOT EXISTS content_filter_term (
    term text PRIMARY KEY CHECK (char_length(term) BETWEEN 2 AND 40),
    is_enabled boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO content_filter_term (term) VALUES
    ('操你妈'), ('草泥马'), ('傻逼'), ('肏你媽'), ('賣淫招嫖'),
    ('씨발'), ('개새끼'), ('좆같'), ('보이스피싱 알바'),
    ('motherfucker'), ('fuck you'), ('kill yourself')
ON CONFLICT DO NOTHING;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'damumu_app') THEN
        GRANT SELECT, INSERT, UPDATE ON content_filter_term TO damumu_app;
    END IF;
END
$$;

COMMIT;

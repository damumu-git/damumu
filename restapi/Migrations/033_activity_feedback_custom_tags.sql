BEGIN;

ALTER TABLE endorsement ADD COLUMN IF NOT EXISTS custom_tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE endorsement ALTER COLUMN tag_code DROP NOT NULL;
ALTER TABLE endorsement DROP CONSTRAINT IF EXISTS ck_endorsement_tags;
ALTER TABLE endorsement ADD CONSTRAINT ck_endorsement_tags CHECK (
    cardinality(custom_tags) <= 2
    AND (target_type = 'activity' OR cardinality(custom_tags) = 0)
    AND (tag_code IS NOT NULL OR cardinality(custom_tags) > 0)
);

COMMIT;

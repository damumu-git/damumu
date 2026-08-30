-- MVP user profile, two-level taxonomy, event application and moderation fields.
BEGIN;

ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS contact_type varchar(24);
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS contact_value varchar(160);

ALTER TABLE event ADD COLUMN IF NOT EXISTS min_participants smallint NOT NULL DEFAULT 2;
ALTER TABLE event ADD COLUMN IF NOT EXISTS price_min numeric(12,2) NOT NULL DEFAULT 0;
ALTER TABLE event ADD COLUMN IF NOT EXISTS price_max numeric(12,2) NOT NULL DEFAULT 0;
ALTER TABLE event ADD COLUMN IF NOT EXISTS announcement text;
ALTER TABLE event ADD COLUMN IF NOT EXISTS organizer_note text;
ALTER TABLE event ADD COLUMN IF NOT EXISTS review_status varchar(24) NOT NULL DEFAULT 'not_required';
ALTER TABLE event ADD COLUMN IF NOT EXISTS review_reason text;
ALTER TABLE event ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;
ALTER TABLE event ADD COLUMN IF NOT EXISTS reviewed_by_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL;

UPDATE event SET price_min=price_amount, price_max=price_amount WHERE price_min=0 AND price_max=0;

ALTER TABLE event_member ADD COLUMN IF NOT EXISTS party_size smallint NOT NULL DEFAULT 1;
ALTER TABLE event_member ADD COLUMN IF NOT EXISTS share_contact boolean NOT NULL DEFAULT false;
ALTER TABLE event_member ADD COLUMN IF NOT EXISTS rejection_reason text;

-- Collapse the existing three-level taxonomy to major -> leaf. Former middle
-- categories remain as disabled historical nodes so existing IDs are retained.
WITH leaf_parent AS (
    SELECT leaf.id, middle.parent_id AS major_id
    FROM category leaf JOIN category middle ON middle.id=leaf.parent_id
    WHERE leaf.level=3 AND middle.level=2
)
UPDATE category leaf SET parent_id=leaf_parent.major_id, level=2
FROM leaf_parent WHERE leaf.id=leaf_parent.id;

UPDATE category SET is_active=false WHERE code IN (
    'food_dining','food_cafe','food_cooking','sports_ball','sports_fitness','sports_mindbody',
    'culture_show','culture_read','culture_make','outdoors_nature','outdoors_city','outdoors_trip',
    'study_language','study_career','study_skill','social_casual','social_hobby','social_life'
);

CREATE OR REPLACE FUNCTION muda_validate_category_hierarchy()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE parent_level smallint;
BEGIN
    IF NEW.parent_id IS NULL THEN NEW.level := 1; RETURN NEW; END IF;
    IF NEW.parent_id = NEW.id THEN RAISE EXCEPTION 'category cannot be its own parent'; END IF;
    SELECT level INTO parent_level FROM category WHERE id=NEW.parent_id;
    IF parent_level IS NULL THEN RAISE EXCEPTION 'parent category does not exist'; END IF;
    IF parent_level >= 2 THEN RAISE EXCEPTION 'category hierarchy supports at most two levels'; END IF;
    NEW.level := 2;
    RETURN NEW;
END;
$$;

CREATE INDEX IF NOT EXISTS ix_event_review_status ON event (review_status, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_event_member_application ON event_member (event_id, status, created_at);

COMMIT;

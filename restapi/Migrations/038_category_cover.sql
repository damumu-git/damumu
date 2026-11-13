BEGIN;

ALTER TABLE category ADD COLUMN IF NOT EXISTS cover_image_url text;

COMMIT;

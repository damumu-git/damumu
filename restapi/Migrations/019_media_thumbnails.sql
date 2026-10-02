BEGIN;

ALTER TABLE media_asset
    ADD COLUMN IF NOT EXISTS thumbnail_storage_key text,
    ADD COLUMN IF NOT EXISTS thumbnail_mime_type varchar(120),
    ADD COLUMN IF NOT EXISTS thumbnail_byte_size bigint,
    ADD COLUMN IF NOT EXISTS thumbnail_width integer,
    ADD COLUMN IF NOT EXISTS thumbnail_height integer;

ALTER TABLE media_asset
    DROP CONSTRAINT IF EXISTS ck_media_asset_thumbnail_metadata;

ALTER TABLE media_asset
    ADD CONSTRAINT ck_media_asset_thumbnail_metadata CHECK (
        (
            thumbnail_storage_key IS NULL
            AND thumbnail_mime_type IS NULL
            AND thumbnail_byte_size IS NULL
            AND thumbnail_width IS NULL
            AND thumbnail_height IS NULL
        ) OR (
            thumbnail_storage_key IS NOT NULL
            AND thumbnail_mime_type='image/webp'
            AND thumbnail_byte_size > 0
            AND thumbnail_width > 0
            AND thumbnail_height > 0
        )
    );

COMMIT;

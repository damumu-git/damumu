BEGIN;

ALTER TABLE category ADD COLUMN IF NOT EXISTS icon_key varchar(64);
ALTER TABLE category ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false;
ALTER TABLE event ADD COLUMN IF NOT EXISTS custom_subcategory varchar(60);

UPDATE category SET icon_key=code, is_featured=true
WHERE code IN ('food', 'sports', 'culture', 'outdoors', 'study', 'social');

INSERT INTO category (code, name_zh_cn, name_en_us, name_ko_kr, icon,
                      icon_key, color, sort_order, is_featured)
VALUES ('other', '其它', 'Other', '기타', '✨', 'other', '#AC81BC', 70, false)
ON CONFLICT (code) DO UPDATE SET icon_key='other';

INSERT INTO category (code, name_zh_cn, name_en_us, name_ko_kr, icon,
                      parent_id, sort_order, color)
VALUES ('other_custom', '自定义', 'Custom', '직접 입력', '✨',
        (SELECT id FROM category WHERE code='other'), 10, '#AC81BC')
ON CONFLICT (code) DO UPDATE SET parent_id=EXCLUDED.parent_id;

ALTER TABLE event DROP CONSTRAINT IF EXISTS event_custom_subcategory_length;
ALTER TABLE event ADD CONSTRAINT event_custom_subcategory_length
    CHECK (custom_subcategory IS NULL OR
           (char_length(btrim(custom_subcategory)) BETWEEN 1 AND 15));

COMMIT;

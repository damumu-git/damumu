BEGIN;

ALTER TABLE category ADD COLUMN IF NOT EXISTS requires_custom_label boolean NOT NULL DEFAULT false;

UPDATE category SET requires_custom_label=true WHERE code='other_custom';

INSERT INTO category (code, name_zh_cn, name_en_us, name_ko_kr, icon,
                      parent_id, sort_order, requires_custom_label)
SELECT 'custom_' || replace(id::text, '-', ''), '其它', 'Other', '기타', '✏️',
       id, 999, true
FROM category
WHERE parent_id IS NULL AND code <> 'other'
ON CONFLICT (code) DO UPDATE SET parent_id=EXCLUDED.parent_id,
    requires_custom_label=true;

CREATE OR REPLACE FUNCTION muda_ensure_custom_category_leaf()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.parent_id IS NULL AND NEW.code <> 'other' THEN
        INSERT INTO category (code, name_zh_cn, name_en_us, name_ko_kr, icon,
                              parent_id, sort_order, requires_custom_label)
        VALUES ('custom_' || replace(NEW.id::text, '-', ''), '其它', 'Other', '기타',
                '✏️', NEW.id, 999, true)
        ON CONFLICT (code) DO UPDATE SET parent_id=EXCLUDED.parent_id,
            requires_custom_label=true;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_category_custom_leaf ON category;
CREATE TRIGGER trg_category_custom_leaf
AFTER INSERT OR UPDATE OF parent_id ON category
FOR EACH ROW EXECUTE FUNCTION muda_ensure_custom_category_leaf();

COMMIT;

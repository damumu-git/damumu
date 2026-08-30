-- 可由运营后台管理的系统头像资产目录。
CREATE TABLE IF NOT EXISTS system_avatar (
    id uuid PRIMARY KEY,
    code varchar(64) NOT NULL UNIQUE,
    name_zh_cn varchar(80) NOT NULL,
    name_en_us varchar(80) NOT NULL,
    name_ko_kr varchar(80) NOT NULL,
    image_url text NOT NULL,
    mime_type varchar(40) NOT NULL DEFAULT 'image/jpeg',
    byte_size integer NOT NULL CHECK (byte_size > 0 AND byte_size <= 1048576),
    width smallint NOT NULL DEFAULT 512 CHECK (width = 512),
    height smallint NOT NULL DEFAULT 512 CHECK (height = 512),
    sort_order integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_system_avatar_active_sort
    ON system_avatar (is_active, sort_order, created_at);

COMMENT ON TABLE system_avatar IS
    'AI 生成或设计师制作的系统头像目录；图片统一为 512x512 JPEG，最大 1MB';

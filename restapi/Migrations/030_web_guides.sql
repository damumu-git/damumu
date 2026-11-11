BEGIN;

ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS web_public_bio varchar(300);

CREATE TABLE IF NOT EXISTS web_guide (
    slug varchar(80) PRIMARY KEY CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    title varchar(120) NOT NULL,
    summary varchar(300) NOT NULL,
    body text NOT NULL,
    cover_category varchar(24) NOT NULL DEFAULT 'other',
    source_url text,
    region_code varchar(32) REFERENCES administrative_region(code) ON DELETE SET NULL,
    category_id uuid REFERENCES category(id) ON DELETE SET NULL,
    published boolean NOT NULL DEFAULT false,
    featured boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO web_guide (slug,title,summary,body,cover_category,published,featured)
VALUES
    ('river-walk','把周末留一段给散步','不赶时间的散步，适合一个人出门，也适合和新朋友见面。',
     E'选一个双方都熟悉的公共入口，约定出发时间。\n先走一小段，走累了就休息，不必把路线排满。\n出发前核对天气和交通，遇到大雨就改约室内。','outdoors',true,true),
    ('coffee-meet','第一次咖啡局，怎么开场','从一杯咖啡和一个简单话题开始。',
     E'约定各自消费，提前说明预算和聚会时长。\n选公共场所，提前考虑无障碍需求。\n准备一个轻松话题，例如最近想去的地方。','food',true,true),
    ('photo-walk','在熟悉的街区做一次观察练习','给自己定一个小主题，带着手机在附近走走。',
     E'从颜色、店招或街角光影里选一个主题。\n拍摄人物前先征得同意。\n回家选三张照片，写下你为什么停下来。','culture',true,true)
ON CONFLICT (slug) DO NOTHING;

COMMIT;

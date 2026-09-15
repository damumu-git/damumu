BEGIN;

INSERT INTO app_user (id, status, role, locale, timezone, adult_confirmed_at)
VALUES ('00000000-0000-0000-0000-000000000101', 'active', 'user', 'zh-CN', 'Asia/Seoul', now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_profile (user_id, nickname, city_code, district_code, languages, profile_completed_at)
VALUES (
    '00000000-0000-0000-0000-000000000101',
    '本地测试用户',
    'KR-11',
    'KR-11680',
    ARRAY['zh-CN']::varchar[],
    now()
)
ON CONFLICT (user_id) DO UPDATE SET nickname=EXCLUDED.nickname;

INSERT INTO category (id, code, name_zh_cn, name_en_us, name_ko_kr, icon, sort_order, is_active)
VALUES (
    '00000000-0000-0000-0000-000000000201',
    'local_test',
    '本地测试',
    'Local test',
    '로컬 테스트',
    '🧪',
    999,
    true
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO event (
    id, organizer_user_id, category_id, title, description, status,
    visibility, approval_mode, capacity, approved_count, city_code,
    district_code, published_at, created_at
)
SELECT
    ('00000000-0000-0000-0000-' || lpad(sequence::text, 12, '0'))::uuid,
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000201',
    '本地分页活动 ' || sequence,
    '仅用于本地 PostgreSQL Cursor 分页测试',
    'published',
    'public',
    'automatic',
    8,
    1,
    'KR-11',
    'KR-11680',
    timestamp with time zone '2026-09-15 10:00:00+09' - sequence * interval '1 minute',
    timestamp with time zone '2026-09-15 10:00:00+09' - sequence * interval '1 minute'
FROM generate_series(301, 325) AS sequence
ON CONFLICT (id) DO NOTHING;

INSERT INTO event_schedule (event_id, starts_at, ends_at)
SELECT
    event.id,
    event.created_at + interval '7 days',
    event.created_at + interval '7 days 2 hours'
FROM event
WHERE event.id::text LIKE '00000000-0000-0000-0000-0000000003%'
  AND NOT EXISTS (
      SELECT 1 FROM event_schedule WHERE event_schedule.event_id=event.id
  );

COMMIT;

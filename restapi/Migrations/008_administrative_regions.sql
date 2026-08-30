-- Editable administrative region catalog used by event publishing and discovery.
BEGIN;

-- Manual meeting points may be saved before map coordinates are selected.
ALTER TABLE place ALTER COLUMN public_geo DROP NOT NULL;

CREATE TABLE IF NOT EXISTS administrative_region (
    code varchar(32) PRIMARY KEY,
    parent_code varchar(32) REFERENCES administrative_region(code) ON UPDATE CASCADE ON DELETE RESTRICT,
    level smallint NOT NULL CHECK (level IN (1, 2)),
    name_zh_cn varchar(100) NOT NULL,
    name_ko_kr varchar(100) NOT NULL,
    name_en_us varchar(100) NOT NULL,
    sort_order integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((level = 1 AND parent_code IS NULL) OR (level = 2 AND parent_code IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS ix_administrative_region_parent
    ON administrative_region(parent_code, sort_order, code);

INSERT INTO administrative_region
    (code, parent_code, level, name_zh_cn, name_ko_kr, name_en_us, sort_order)
VALUES
    ('KR-11', NULL, 1, '首尔', '서울특별시', 'Seoul', 10),
    ('KR-26', NULL, 1, '釜山', '부산광역시', 'Busan', 20),
    ('KR-28', NULL, 1, '仁川', '인천광역시', 'Incheon', 30),
    ('KR-41', NULL, 1, '京畿道', '경기도', 'Gyeonggi-do', 40),
    ('KR-11440', 'KR-11', 2, '麻浦区', '마포구', 'Mapo-gu', 10),
    ('KR-11680', 'KR-11', 2, '江南区', '강남구', 'Gangnam-gu', 20),
    ('KR-11110', 'KR-11', 2, '钟路区', '종로구', 'Jongno-gu', 30),
    ('KR-11170', 'KR-11', 2, '龙山区', '용산구', 'Yongsan-gu', 40),
    ('KR-11710', 'KR-11', 2, '松坡区', '송파구', 'Songpa-gu', 50),
    ('KR-11560', 'KR-11', 2, '永登浦区', '영등포구', 'Yeongdeungpo-gu', 60),
    ('KR-26350', 'KR-26', 2, '海云台区', '해운대구', 'Haeundae-gu', 10),
    ('KR-26500', 'KR-26', 2, '水营区', '수영구', 'Suyeong-gu', 20),
    ('KR-26230', 'KR-26', 2, '釜山镇区', '부산진구', 'Busanjin-gu', 30),
    ('KR-26260', 'KR-26', 2, '东莱区', '동래구', 'Dongnae-gu', 40),
    ('KR-26110', 'KR-26', 2, '中区', '중구', 'Jung-gu', 50),
    ('KR-28185', 'KR-28', 2, '延寿区', '연수구', 'Yeonsu-gu', 10),
    ('KR-28200', 'KR-28', 2, '南洞区', '남동구', 'Namdong-gu', 20),
    ('KR-28237', 'KR-28', 2, '富平区', '부평구', 'Bupyeong-gu', 30),
    ('KR-28110', 'KR-28', 2, '中区', '중구', 'Jung-gu', 40),
    ('KR-41110', 'KR-41', 2, '水原市', '수원시', 'Suwon-si', 10),
    ('KR-41130', 'KR-41', 2, '城南市', '성남시', 'Seongnam-si', 20),
    ('KR-41280', 'KR-41', 2, '高阳市', '고양시', 'Goyang-si', 30),
    ('KR-41460', 'KR-41', 2, '龙仁市', '용인시', 'Yongin-si', 40),
    ('KR-41190', 'KR-41', 2, '富川市', '부천시', 'Bucheon-si', 50)
ON CONFLICT (code) DO NOTHING;

COMMIT;

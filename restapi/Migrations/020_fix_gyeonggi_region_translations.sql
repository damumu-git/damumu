-- Correct Gyeonggi-do rows whose Korean label was previously copied into
-- name_zh_cn. The update is idempotent and preserves region identity/references.
BEGIN;

UPDATE administrative_region AS region
SET name_zh_cn = correction.name_zh_cn,
    name_ko_kr = correction.name_ko_kr,
    name_en_us = correction.name_en_us,
    updated_at = now()
FROM (VALUES
    ('KR-41150', '议政府市', '의정부시', 'Uijeongbu-si'),
    ('KR-41170', '安养市', '안양시', 'Anyang-si'),
    ('KR-41210', '光明市', '광명시', 'Gwangmyeong-si'),
    ('KR-41220', '平泽市', '평택시', 'Pyeongtaek-si'),
    ('KR-41250', '东豆川市', '동두천시', 'Dongducheon-si'),
    ('KR-41270', '安山市', '안산시', 'Ansan-si'),
    ('KR-41290', '果川市', '과천시', 'Gwacheon-si'),
    ('KR-41310', '九里市', '구리시', 'Guri-si'),
    ('KR-41360', '南杨州市', '남양주시', 'Namyangju-si'),
    ('KR-41370', '乌山市', '오산시', 'Osan-si'),
    ('KR-41390', '始兴市', '시흥시', 'Siheung-si'),
    ('KR-41410', '军浦市', '군포시', 'Gunpo-si'),
    ('KR-41430', '义王市', '의왕시', 'Uiwang-si'),
    ('KR-41450', '河南市', '하남시', 'Hanam-si'),
    ('KR-41480', '坡州市', '파주시', 'Paju-si'),
    ('KR-41500', '利川市', '이천시', 'Icheon-si'),
    ('KR-41550', '安城市', '안성시', 'Anseong-si'),
    ('KR-41570', '金浦市', '김포시', 'Gimpo-si'),
    ('KR-41590', '华城市', '화성시', 'Hwaseong-si'),
    ('KR-41610', '广州市', '광주시', 'Gwangju-si'),
    ('KR-41630', '杨州市', '양주시', 'Yangju-si'),
    ('KR-41650', '抱川市', '포천시', 'Pocheon-si'),
    ('KR-41670', '骊州市', '여주시', 'Yeoju-si'),
    ('KR-41800', '涟川郡', '연천군', 'Yeoncheon-gun'),
    ('KR-41820', '加平郡', '가평군', 'Gapyeong-gun'),
    ('KR-41830', '杨平郡', '양평군', 'Yangpyeong-gun')
) AS correction(code, name_zh_cn, name_ko_kr, name_en_us)
WHERE region.code = correction.code;

COMMIT;

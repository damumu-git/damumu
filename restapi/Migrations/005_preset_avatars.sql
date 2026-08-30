-- Built-in preset avatars. Image files live in uploads/system-avatars/.
INSERT INTO system_avatar
    (id, code, name_zh_cn, name_en_us, name_ko_kr, image_url, mime_type,
     byte_size, width, height, sort_order, is_active)
VALUES
    ('a0000000-0000-4000-8000-000000000001','warm_fox','暖暖狐','Warm Fox','따뜻한 여우','/uploads/system-avatars/warm-fox.jpg','image/jpeg',46070,512,512,10,true),
    ('a0000000-0000-4000-8000-000000000002','green_sprout','小芽','Green Sprout','초록 새싹','/uploads/system-avatars/green-sprout.jpg','image/jpeg',47772,512,512,20,true),
    ('a0000000-0000-4000-8000-000000000003','blue_bear','蓝蓝熊','Blue Bear','파란 곰','/uploads/system-avatars/blue-bear.jpg','image/jpeg',65368,512,512,30,true),
    ('a0000000-0000-4000-8000-000000000004','moon_rabbit','月亮兔','Moon Rabbit','달 토끼','/uploads/system-avatars/moon-rabbit.jpg','image/jpeg',49008,512,512,40,true)
ON CONFLICT (code) DO UPDATE SET
    name_zh_cn=EXCLUDED.name_zh_cn, name_en_us=EXCLUDED.name_en_us,
    name_ko_kr=EXCLUDED.name_ko_kr, image_url=EXCLUDED.image_url,
    byte_size=EXCLUDED.byte_size, sort_order=EXCLUDED.sort_order,
    is_active=true, updated_at=now();

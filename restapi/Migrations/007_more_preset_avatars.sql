-- Expand the preset avatar library to 20 choices.
INSERT INTO system_avatar
    (id,code,name_zh_cn,name_en_us,name_ko_kr,image_url,mime_type,byte_size,width,height,sort_order,is_active)
VALUES
('a0000000-0000-4000-8000-000000000005','red_panda','小熊猫','Red Panda','레서판다','/uploads/system-avatars/red-panda.jpg','image/jpeg',43219,512,512,50,true),
('a0000000-0000-4000-8000-000000000006','cream_cat','奶油猫','Cream Cat','크림 고양이','/uploads/system-avatars/cream-cat.jpg','image/jpeg',50281,512,512,60,true),
('a0000000-0000-4000-8000-000000000007','golden_dog','金毛犬','Golden Dog','골든 강아지','/uploads/system-avatars/golden-dog.jpg','image/jpeg',57261,512,512,70,true),
('a0000000-0000-4000-8000-000000000008','white_seal','白海豹','White Seal','하얀 물범','/uploads/system-avatars/white-seal.jpg','image/jpeg',40631,512,512,80,true),
('a0000000-0000-4000-8000-000000000009','yellow_chick','小黄鸡','Yellow Chick','노란 병아리','/uploads/system-avatars/yellow-chick.jpg','image/jpeg',41016,512,512,90,true),
('a0000000-0000-4000-8000-000000000010','mint_dino','薄荷龙','Mint Dino','민트 공룡','/uploads/system-avatars/mint-dino.jpg','image/jpeg',42677,512,512,100,true),
('a0000000-0000-4000-8000-000000000011','teal_whale','青鲸','Teal Whale','청록 고래','/uploads/system-avatars/teal-whale.jpg','image/jpeg',46837,512,512,110,true),
('a0000000-0000-4000-8000-000000000012','navy_penguin','深蓝企鹅','Navy Penguin','남색 펭귄','/uploads/system-avatars/navy-penguin.jpg','image/jpeg',51432,512,512,120,true),
('a0000000-0000-4000-8000-000000000013','lavender_koala','薰衣草考拉','Lavender Koala','라벤더 코알라','/uploads/system-avatars/lavender-koala.jpg','image/jpeg',50643,512,512,130,true),
('a0000000-0000-4000-8000-000000000014','pink_axolotl','粉色六角龙','Pink Axolotl','분홍 우파루파','/uploads/system-avatars/pink-axolotl.jpg','image/jpeg',43547,512,512,140,true),
('a0000000-0000-4000-8000-000000000015','coral_deer','珊瑚鹿','Coral Deer','코랄 사슴','/uploads/system-avatars/coral-deer.jpg','image/jpeg',57858,512,512,150,true),
('a0000000-0000-4000-8000-000000000016','brown_capybara','水豚','Capybara','카피바라','/uploads/system-avatars/brown-capybara.jpg','image/jpeg',55042,512,512,160,true),
('a0000000-0000-4000-8000-000000000017','sky_owl','天空猫头鹰','Sky Owl','하늘 부엉이','/uploads/system-avatars/sky-owl.jpg','image/jpeg',54462,512,512,170,true),
('a0000000-0000-4000-8000-000000000018','peach_hamster','蜜桃仓鼠','Peach Hamster','복숭아 햄스터','/uploads/system-avatars/peach-hamster.jpg','image/jpeg',50740,512,512,180,true),
('a0000000-0000-4000-8000-000000000019','turquoise_otter','绿松石水獭','Turquoise Otter','터키석 수달','/uploads/system-avatars/turquoise-otter.jpg','image/jpeg',54479,512,512,190,true),
('a0000000-0000-4000-8000-000000000020','gray_raccoon','灰浣熊','Gray Raccoon','회색 라쿤','/uploads/system-avatars/gray-raccoon.jpg','image/jpeg',63804,512,512,200,true)
ON CONFLICT (code) DO UPDATE SET name_zh_cn=EXCLUDED.name_zh_cn,
 name_en_us=EXCLUDED.name_en_us,name_ko_kr=EXCLUDED.name_ko_kr,
 image_url=EXCLUDED.image_url,byte_size=EXCLUDED.byte_size,sort_order=EXCLUDED.sort_order,
 is_active=true,updated_at=now();

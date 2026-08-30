-- Three-level activity taxonomy: level 1 (major), level 2 (group), level 3 (leaf).
-- Events should normally reference a level-3 category.

BEGIN;

ALTER TABLE category ADD COLUMN IF NOT EXISTS parent_id uuid REFERENCES category(id) ON DELETE RESTRICT;
ALTER TABLE category ADD COLUMN IF NOT EXISTS level smallint NOT NULL DEFAULT 1;
ALTER TABLE category ADD COLUMN IF NOT EXISTS name_en_us varchar(80);
ALTER TABLE category ADD COLUMN IF NOT EXISTS description_zh_cn text;
ALTER TABLE category ADD COLUMN IF NOT EXISTS description_en_us text;
ALTER TABLE category ADD COLUMN IF NOT EXISTS description_ko_kr text;
ALTER TABLE category ADD COLUMN IF NOT EXISTS color varchar(16);

CREATE INDEX IF NOT EXISTS ix_category_parent_sort ON category (parent_id, sort_order, name_zh_cn);
CREATE INDEX IF NOT EXISTS ix_category_level_active ON category (level, is_active, sort_order);

CREATE OR REPLACE FUNCTION muda_validate_category_hierarchy()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    parent_level smallint;
BEGIN
    IF NEW.parent_id IS NULL THEN
        NEW.level := 1;
        RETURN NEW;
    END IF;
    IF NEW.parent_id = NEW.id THEN
        RAISE EXCEPTION 'category cannot be its own parent';
    END IF;
    SELECT level INTO parent_level FROM category WHERE id=NEW.parent_id;
    IF parent_level IS NULL THEN
        RAISE EXCEPTION 'parent category does not exist';
    END IF;
    IF parent_level >= 3 THEN
        RAISE EXCEPTION 'category hierarchy supports at most three levels';
    END IF;
    NEW.level := parent_level + 1;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_category_hierarchy ON category;
CREATE TRIGGER trg_category_hierarchy
BEFORE INSERT OR UPDATE OF parent_id ON category
FOR EACH ROW EXECUTE FUNCTION muda_validate_category_hierarchy();

-- Normalize the original major categories.
UPDATE category SET parent_id=NULL, level=1,
    name_en_us='Food & Drink', name_ko_kr='맛집·음료', color='#F08A5D',
    description_zh_cn='餐厅、咖啡、烹饪与饮品主题活动',
    description_en_us='Restaurants, cafés, cooking and drinks',
    description_ko_kr='맛집, 카페, 요리 및 음료 모임'
WHERE code='food';
UPDATE category SET parent_id=NULL, level=1,
    name_en_us='Sports & Wellness', name_ko_kr='운동·웰니스', color='#3A9D71',
    description_zh_cn='球类、健身、跑步和身心健康',
    description_en_us='Sports, fitness, running and wellness',
    description_ko_kr='스포츠, 피트니스, 러닝 및 웰니스'
WHERE code='sports';
UPDATE category SET parent_id=NULL, level=1,
    name_en_us='Culture & Arts', name_ko_kr='문화·예술', color='#8B6FC0',
    description_zh_cn='展览、演出、阅读和创作体验',
    description_en_us='Exhibitions, performances, reading and making',
    description_ko_kr='전시, 공연, 독서 및 창작 체험'
WHERE code='culture';
UPDATE category SET parent_id=NULL, level=1,
    name_en_us='Outdoors & Travel', name_ko_kr='아웃도어·여행', color='#4F8DB7',
    description_zh_cn='徒步、露营、城市漫步与结伴旅行',
    description_en_us='Hiking, camping, city walks and travel',
    description_ko_kr='등산, 캠핑, 도시 산책 및 여행'
WHERE code='outdoors';
UPDATE category SET parent_id=NULL, level=1,
    name_en_us='Learning & Growth', name_ko_kr='학습·성장', color='#D49A3A',
    description_zh_cn='语言、职业、技能和知识交流',
    description_en_us='Languages, careers, skills and knowledge',
    description_ko_kr='언어, 커리어, 기술 및 지식 교류'
WHERE code='study';
UPDATE category SET parent_id=NULL, level=1,
    name_en_us='Social & Lifestyle', name_ko_kr='소셜·라이프', color='#D66A8B',
    description_zh_cn='轻社交、兴趣局、宠物与生活方式',
    description_en_us='Casual social, hobbies, pets and lifestyle',
    description_ko_kr='가벼운 소셜, 취미, 반려동물 및 라이프스타일'
WHERE code='social';

-- Level-2 groups.
INSERT INTO category (code,name_zh_cn,name_en_us,name_ko_kr,icon,parent_id,sort_order,color) VALUES
('food_dining','聚餐探店','Dining Out','맛집 탐방','🍽️',(SELECT id FROM category WHERE code='food'),10,'#F08A5D'),
('food_cafe','咖啡甜品','Cafés & Desserts','카페·디저트','☕',(SELECT id FROM category WHERE code='food'),20,'#C98752'),
('food_cooking','烹饪饮品','Cooking & Drinks','요리·음료','🧑‍🍳',(SELECT id FROM category WHERE code='food'),30,'#E0A33A'),
('sports_ball','球类运动','Ball Sports','구기 운동','⚽',(SELECT id FROM category WHERE code='sports'),10,'#3A9D71'),
('sports_fitness','健身训练','Fitness Training','피트니스','🏋️',(SELECT id FROM category WHERE code='sports'),20,'#2F8A68'),
('sports_mindbody','身心健康','Mind & Body','마인드·바디','🧘',(SELECT id FROM category WHERE code='sports'),30,'#68A87D'),
('culture_show','展览演出','Arts & Shows','전시·공연','🎭',(SELECT id FROM category WHERE code='culture'),10,'#8B6FC0'),
('culture_read','阅读影视','Books & Film','독서·영화','📚',(SELECT id FROM category WHERE code='culture'),20,'#7356A8'),
('culture_make','手作创作','Creative Making','창작·공예','🎨',(SELECT id FROM category WHERE code='culture'),30,'#A56FB2'),
('outdoors_nature','自然户外','Nature Outdoors','자연 아웃도어','🥾',(SELECT id FROM category WHERE code='outdoors'),10,'#4F8DB7'),
('outdoors_city','城市探索','City Exploration','도시 탐방','🚶',(SELECT id FROM category WHERE code='outdoors'),20,'#4A82A3'),
('outdoors_trip','结伴旅行','Group Travel','동행 여행','🧳',(SELECT id FROM category WHERE code='outdoors'),30,'#68A2C4'),
('study_language','语言交流','Language Exchange','언어 교환','💬',(SELECT id FROM category WHERE code='study'),10,'#D49A3A'),
('study_career','职业成长','Career Growth','커리어 성장','💼',(SELECT id FROM category WHERE code='study'),20,'#C58B2D'),
('study_skill','技能学习','Skills & Knowledge','기술·지식','🧠',(SELECT id FROM category WHERE code='study'),30,'#D7AA55'),
('social_casual','轻松社交','Casual Social','가벼운 소셜','✨',(SELECT id FROM category WHERE code='social'),10,'#D66A8B'),
('social_hobby','兴趣娱乐','Hobbies & Games','취미·게임','🎲',(SELECT id FROM category WHERE code='social'),20,'#C55D7E'),
('social_life','生活伙伴','Lifestyle Buddies','라이프 동행','🐾',(SELECT id FROM category WHERE code='social'),30,'#E28AA4')
ON CONFLICT (code) DO UPDATE SET parent_id=EXCLUDED.parent_id, name_zh_cn=EXCLUDED.name_zh_cn,
 name_en_us=EXCLUDED.name_en_us, name_ko_kr=EXCLUDED.name_ko_kr, icon=EXCLUDED.icon,
 sort_order=EXCLUDED.sort_order, color=EXCLUDED.color;

-- Fold legacy one-level categories into the new tree while preserving their IDs
-- and any events that already reference them.
UPDATE category SET parent_id=(SELECT id FROM category WHERE code='outdoors_nature'),
    name_zh_cn='其他户外', name_en_us='Other Outdoors', name_ko_kr='기타 아웃도어', sort_order=90
WHERE code='outdoor';
UPDATE category SET parent_id=(SELECT id FROM category WHERE code='study_language'),
    name_zh_cn='其他语言交流', name_en_us='Other Language Exchange', name_ko_kr='기타 언어 교환', sort_order=90
WHERE code='language';
UPDATE category SET parent_id=(SELECT id FROM category WHERE code='social_hobby'),
    name_zh_cn='其他桌游', name_en_us='Other Board Games', name_ko_kr='기타 보드게임', sort_order=90
WHERE code='board_game';
UPDATE category SET parent_id=(SELECT id FROM category WHERE code='social_life'),
    name_zh_cn='其他活动', name_en_us='Other Activities', name_ko_kr='기타 활동', sort_order=99
WHERE code='other';

-- Level-3 selectable categories.
INSERT INTO category (code,name_zh_cn,name_en_us,name_ko_kr,icon,parent_id,sort_order) VALUES
('restaurant_meetup','餐厅聚餐','Restaurant Meetup','식사 모임','🍜',(SELECT id FROM category WHERE code='food_dining'),10),
('street_food','街头美食','Street Food','길거리 음식','🥟',(SELECT id FROM category WHERE code='food_dining'),20),
('brunch','早午餐','Brunch','브런치','🥐',(SELECT id FROM category WHERE code='food_dining'),30),
('cafe_hopping','咖啡探店','Café Hopping','카페 투어','☕',(SELECT id FROM category WHERE code='food_cafe'),10),
('dessert','甜品烘焙','Desserts & Baking','디저트·베이킹','🍰',(SELECT id FROM category WHERE code='food_cafe'),20),
('home_cooking','一起做饭','Cook Together','함께 요리','🍳',(SELECT id FROM category WHERE code='food_cooking'),10),
('wine_cocktail','葡萄酒与调酒','Wine & Cocktails','와인·칵테일','🍷',(SELECT id FROM category WHERE code='food_cooking'),20),
('football','足球','Football','축구','⚽',(SELECT id FROM category WHERE code='sports_ball'),10),
('basketball','篮球','Basketball','농구','🏀',(SELECT id FROM category WHERE code='sports_ball'),20),
('badminton','羽毛球','Badminton','배드민턴','🏸',(SELECT id FROM category WHERE code='sports_ball'),30),
('running','跑步','Running','러닝','🏃',(SELECT id FROM category WHERE code='sports_fitness'),10),
('gym_workout','健身房训练','Gym Workout','헬스','🏋️',(SELECT id FROM category WHERE code='sports_fitness'),20),
('cycling','骑行','Cycling','자전거','🚴',(SELECT id FROM category WHERE code='sports_fitness'),30),
('yoga','瑜伽','Yoga','요가','🧘',(SELECT id FROM category WHERE code='sports_mindbody'),10),
('meditation','冥想疗愈','Meditation','명상','🌿',(SELECT id FROM category WHERE code='sports_mindbody'),20),
('exhibition','展览看展','Exhibitions','전시 관람','🖼️',(SELECT id FROM category WHERE code='culture_show'),10),
('concert','音乐演出','Concerts','공연','🎵',(SELECT id FROM category WHERE code='culture_show'),20),
('theatre','戏剧舞台','Theatre','연극','🎭',(SELECT id FROM category WHERE code='culture_show'),30),
('book_club','读书会','Book Club','독서 모임','📖',(SELECT id FROM category WHERE code='culture_read'),10),
('movie_club','电影放映','Film Club','영화 모임','🎬',(SELECT id FROM category WHERE code='culture_read'),20),
('photography','摄影','Photography','사진','📷',(SELECT id FROM category WHERE code='culture_make'),10),
('craft','手工体验','Crafts','공예','🧶',(SELECT id FROM category WHERE code='culture_make'),20),
('drawing','绘画','Drawing','드로잉','🎨',(SELECT id FROM category WHERE code='culture_make'),30),
('hiking','登山徒步','Hiking','등산','🥾',(SELECT id FROM category WHERE code='outdoors_nature'),10),
('camping','露营','Camping','캠핑','🏕️',(SELECT id FROM category WHERE code='outdoors_nature'),20),
('picnic','野餐','Picnic','피크닉','🧺',(SELECT id FROM category WHERE code='outdoors_nature'),30),
('city_walk','城市漫步','City Walk','도시 산책','🚶',(SELECT id FROM category WHERE code='outdoors_city'),10),
('local_tour','街区探索','Local Tour','동네 탐방','🗺️',(SELECT id FROM category WHERE code='outdoors_city'),20),
('day_trip','周边一日游','Day Trip','당일치기','🚆',(SELECT id FROM category WHERE code='outdoors_trip'),10),
('overseas_trip','海外结伴','Overseas Travel','해외 동행','✈️',(SELECT id FROM category WHERE code='outdoors_trip'),20),
('korean_exchange','韩语交流','Korean Exchange','한국어 교환','🇰🇷',(SELECT id FROM category WHERE code='study_language'),10),
('chinese_exchange','中文交流','Chinese Exchange','중국어 교환','🀄',(SELECT id FROM category WHERE code='study_language'),20),
('english_exchange','英语交流','English Exchange','영어 교환','🔤',(SELECT id FROM category WHERE code='study_language'),30),
('networking','行业交流','Professional Networking','직무 네트워킹','🤝',(SELECT id FROM category WHERE code='study_career'),10),
('job_search','求职互助','Job Search','취업 준비','📄',(SELECT id FROM category WHERE code='study_career'),20),
('coding','编程学习','Coding','코딩','💻',(SELECT id FROM category WHERE code='study_skill'),10),
('finance','理财学习','Personal Finance','재테크','📈',(SELECT id FROM category WHERE code='study_skill'),20),
('newcomer','新人欢迎','Newcomer Social','신입 환영','👋',(SELECT id FROM category WHERE code='social_casual'),10),
('after_work','下班搭子','After-work Social','퇴근 모임','🌙',(SELECT id FROM category WHERE code='social_casual'),20),
('board_games','桌游','Board Games','보드게임','🎲',(SELECT id FROM category WHERE code='social_hobby'),10),
('gaming','电子游戏','Video Games','게임','🎮',(SELECT id FROM category WHERE code='social_hobby'),20),
('karaoke','唱歌','Karaoke','노래방','🎤',(SELECT id FROM category WHERE code='social_hobby'),30),
('pet_walk','宠物散步','Pet Walk','반려동물 산책','🐕',(SELECT id FROM category WHERE code='social_life'),10),
('study_buddy','自习搭子','Study Buddy','공부 친구','📝',(SELECT id FROM category WHERE code='social_life'),20),
('shopping_buddy','购物搭子','Shopping Buddy','쇼핑 친구','🛍️',(SELECT id FROM category WHERE code='social_life'),30)
ON CONFLICT (code) DO UPDATE SET parent_id=EXCLUDED.parent_id, name_zh_cn=EXCLUDED.name_zh_cn,
 name_en_us=EXCLUDED.name_en_us, name_ko_kr=EXCLUDED.name_ko_kr, icon=EXCLUDED.icon,
 sort_order=EXCLUDED.sort_order;

COMMIT;

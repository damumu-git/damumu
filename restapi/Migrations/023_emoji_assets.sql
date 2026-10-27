BEGIN;

-- Artwork mapping only: category/interest identifiers and legacy Emoji are preserved.
CREATE TABLE IF NOT EXISTS emoji_asset (
    key text PRIMARY KEY CHECK (key ~ '^[a-z][a-z0-9-]{0,63}$'),
    emoji text NOT NULL UNIQUE CHECK (length(emoji) BETWEEN 1 AND 32),
    name text NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
    image_url text NOT NULL CHECK (image_url LIKE '/uploads/emoji/%.png'),
    byte_size integer NOT NULL CHECK (byte_size BETWEEN 1 AND 204800),
    width integer NOT NULL DEFAULT 64 CHECK (width=64),
    height integer NOT NULL DEFAULT 64 CHECK (height=64),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='damumu_app') THEN
        GRANT SELECT, INSERT, UPDATE ON emoji_asset TO damumu_app;
    END IF;
END $$;

INSERT INTO emoji_asset(key,emoji,name,image_url,byte_size) VALUES
('leaf','🌿','绿叶','/uploads/emoji/leaf-2b13854e1312.png',5161),
('coffee','☕','咖啡','/uploads/emoji/coffee-aa44c2636d56.png',5278),
('hiking','🥾','登山鞋','/uploads/emoji/hiking-03ce0892aded.png',5580),
('board-games','🎲','骰子','/uploads/emoji/board-games-fff2346df0a7.png',5050),
('sparkles','✨','闪光','/uploads/emoji/sparkles-c9277d93ef84.png',2990),
('heart','❤','爱心','/uploads/emoji/heart-3ea5707f9354.png',3662),
('group','👥','多人','/uploads/emoji/group-4289c21bc0c0.png',4352),
('chat','💬','对话气泡','/uploads/emoji/chat-edac77d99682.png',4696),
('settings','⚙','齿轮','/uploads/emoji/settings-15276a9c9dca.png',5647),
('noodles','🍜','面食','/uploads/emoji/noodles-8de129cb2772.png',5781),
('running','🏃','跑步','/uploads/emoji/running-5c615b6a0021.png',4692),
('theatre','🎭','戏剧','/uploads/emoji/theatre-2f15c44d9241.png',5215),
('camping','🏕','露营','/uploads/emoji/camping-b97f4210ed8f.png',4379),
('books','📚','书籍','/uploads/emoji/books-759400386abd.png',6357),
('rice','🍚','米饭','/uploads/emoji/rice-0b6ede013109.png',4800),
('workout','🏋','举重','/uploads/emoji/workout-6b376f587802.png',4190),
('movie','🎬','电影','/uploads/emoji/movie-cddfaa2eba90.png',5426),
('camera','📷','相机','/uploads/emoji/camera-c19ff71720c8.png',5998),
('dining','🍽','餐具','/uploads/emoji/dining-5867d003dfef.png',6050),
('chef','🧑‍🍳','厨师','/uploads/emoji/chef-e64714d73693.png',4783),
('football','⚽','足球','/uploads/emoji/football-fc6111b63076.png',5505),
('yoga','🧘','瑜伽','/uploads/emoji/yoga-5c9a011573a5.png',4975),
('art','🎨','调色盘','/uploads/emoji/art-a1ba33ba9694.png',6167),
('walking','🚶','步行','/uploads/emoji/walking-a9a303568266.png',3984),
('travel','🧳','行李箱','/uploads/emoji/travel-7ddf03c9bfbf.png',4588),
('career','💼','公文包','/uploads/emoji/career-de92e43617b1.png',5659),
('learning','🧠','大脑','/uploads/emoji/learning-4f678e7a9546.png',5317),
('paw','🐾','爪印','/uploads/emoji/paw-ad28dd709195.png',4930),
('dumpling','🥟','饺子','/uploads/emoji/dumpling-c135f5965ae0.png',4437),
('brunch','🥐','可颂','/uploads/emoji/brunch-757b0a129891.png',4949),
('cake','🍰','蛋糕','/uploads/emoji/cake-10d884fe4174.png',4844),
('cooking','🍳','煎蛋','/uploads/emoji/cooking-21059ce2551b.png',5116),
('wine','🍷','红酒','/uploads/emoji/wine-918750132129.png',3607),
('basketball','🏀','篮球','/uploads/emoji/basketball-df9a93f94065.png',6095),
('badminton','🏸','羽毛球','/uploads/emoji/badminton-d7da578399dd.png',4402),
('cycling','🚴','骑行','/uploads/emoji/cycling-a03b7f47637a.png',5545),
('exhibition','🖼','画框','/uploads/emoji/exhibition-434ce6874b74.png',6133),
('music','🎵','音符','/uploads/emoji/music-cc4379c6eaa4.png',3782),
('reading','📖','翻开的书','/uploads/emoji/reading-ac2938ec9b58.png',5620),
('craft','🧶','毛线','/uploads/emoji/craft-246ba9ded9c4.png',5576),
('picnic','🧺','篮子','/uploads/emoji/picnic-c3b9fb5a83db.png',6098),
('map','🗺','地图','/uploads/emoji/map-8f38571c47fa.png',5035),
('train','🚆','列车','/uploads/emoji/train-8341797d1788.png',5440),
('flight','✈','飞机','/uploads/emoji/flight-e93e3070214d.png',4773),
('korea','🇰🇷','韩国国旗','/uploads/emoji/korea-b366efd75cce.png',4905),
('chinese-exchange','🀄','麻将红中','/uploads/emoji/chinese-exchange-c7ab4d7bb1a9.png',4711),
('english-exchange','🔤','拉丁字母','/uploads/emoji/english-exchange-554a6afccd4a.png',5715),
('networking','🤝','握手','/uploads/emoji/networking-6005332a308c.png',4523),
('document','📄','文件','/uploads/emoji/document-7d0c9bb815d5.png',3456),
('coding','💻','电脑','/uploads/emoji/coding-a2b21ff1c36b.png',5177),
('finance','📈','上升图表','/uploads/emoji/finance-d90522e1e49b.png',4486),
('welcome','👋','挥手','/uploads/emoji/welcome-356311f38fab.png',4512),
('after-work','🌙','月亮','/uploads/emoji/after-work-e05fa5a7d532.png',3505),
('gaming','🎮','游戏手柄','/uploads/emoji/gaming-0109b888a1c2.png',5885),
('karaoke','🎤','麦克风','/uploads/emoji/karaoke-380cfbc2671b.png',4652),
('pet-walk','🐕','狗','/uploads/emoji/pet-walk-42124cf0e0d4.png',5902),
('study-buddy','📝','记事本','/uploads/emoji/study-buddy-60e51d3ee647.png',5520),
('shopping','🛍','购物袋','/uploads/emoji/shopping-4c746f577b6b.png',5573),
('custom','✏','铅笔','/uploads/emoji/custom-57277f6f98e4.png',3838),
('bear','🐻','熊','/uploads/emoji/bear-7696b4a23e8c.png',6452),
('cat','🐱','猫','/uploads/emoji/cat-788809073e52.png',6022),
('owl','🦉','猫头鹰','/uploads/emoji/owl-f42fb04dd95c.png',6330),
('rabbit','🐰','兔','/uploads/emoji/rabbit-61794044552e.png',6000),
('whale','🐳','鲸','/uploads/emoji/whale-227495c063bf.png',4610),
('otter','🦦','水獭','/uploads/emoji/otter-d0f00a055f79.png',5623),
('external-link','↗','右上箭头','/uploads/emoji/external-link-050371a780ab.png',3394),
('fox','🦊','狐狸','/uploads/emoji/fox-2509a26d1c51.png',6516)
ON CONFLICT DO NOTHING;

COMMIT;

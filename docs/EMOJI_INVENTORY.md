# Emoji 与字符图标清单

核对日期：2026-10-27。对象：当前本地分支源码，非 AWS 数据库导出。

## 核对结果与范围

- 共 **67 种不同字符序列、157 处字面量**，包括 Emoji、可作文本显示的爱心/齿轮/箭头；不是屏幕上同时出现的数量。
- 其中 **56 种**出现在数据库分类/兴趣的历史种子迁移；**8 种**仅出现在预览源码。分类数据可在后台修改，历史迁移不代表线上当前启用清单。
- 检查了 App、Admin、API、SQL 迁移、预览和产品网站的 Dart/JS/TS/C#/SQL/HTML/CSS；排除依赖、构建产物、上传图片、字体文件和测试。网站本次未检出。
- 相同图形复用时只算一种；保留变体选择符及连接序列，例如 🧑‍🍳 算一个，而不是拆为人和锅。统计为源码直接包含的字符，不涵盖运行时转义/拼接生成的字符。
- 用户聊天、昵称和自定义内容可能包含任意 Emoji，不应批量替换。实际 JPEG 系统头像也不属于 Emoji。

## 正式界面的直接使用位置

| 字符 | 当前用途 | 处理建议 |
|---|---|---|
| ✨ | API 分类图标缺失时回退；Admin 新分类默认值 | 保留兼容回退，未来映射统一资源 |
| 👥 / 💬 | App 活动群聊/私信的默认图标 | 统一图标组件，保留文字标签 |
| ❤ | App 用户/申请资料、Admin 收到喜欢与反馈 | 使用统一爱心图标 |
| ⚙ | Admin 功能开关导航 | 使用统一设置图标 |
| 🌿 / ☕ / 🥾 / 🎲 | App 示例活动对象中的字面量 | 属于示例，不应作为正式分类清单 |

正式活动卡片、活动详情、活动记录及分类选择还会直接显示 API 返回的 category_icon/icon。Admin 活动和分类管理同样显示数据库值，因此不能只替换上述几处字面量。

## 完整素材候选表

“建议资源名”仅用于后续设计整理，尚未写入数据库或实现替换。“种子标签”保留历史记录供追踪；最终图标映射应核对线上分类及已有 icon_key。来源列列出该字符在每个文件中的首个位置，全部字面量位置见配套 CSV。

| 字符 | 图形 | 出现范围 | 种子标签/代码 | 建议资源名 | 字面量次数 | 来源 |
|---|---|---|---|---|---:|---|
| 🌿 | 绿叶 | 分类/兴趣迁移、App/Admin 源码、预览 | meditation（冥想疗愈） | `leaf` | 8 | `preview/app/app.js:360`<br>`preview/admin/admin.js:146`<br>`restapi/Migrations/004_category_hierarchy.sql:141`<br>`app/lib/main.dart:253` |
| ☕ | 咖啡 | 分类/兴趣迁移、App/Admin 源码、预览 | coffee（咖啡）、food_cafe（咖啡甜品）、cafe_hopping（咖啡探店） | `coffee` | 10 | `preview/app/app.js:361`<br>`preview/admin/admin.js:162`<br>`restapi/Migrations/004_category_hierarchy.sql:89`<br>`restapi/Migrations/001_initial.sql:441`<br>`app/lib/main.dart:268` |
| 🥾 | 登山鞋 | 分类/兴趣迁移、App/Admin 源码 | hiking（徒步）、outdoors_nature（自然户外）、hiking（登山徒步） | `hiking` | 4 | `restapi/Migrations/004_category_hierarchy.sql:97`<br>`restapi/Migrations/001_initial.sql:443`<br>`app/lib/main.dart:285` |
| 🎲 | 骰子 | 分类/兴趣迁移、App/Admin 源码 | games（桌游）、social_hobby（兴趣娱乐）、board_games（桌游） | `board-games` | 4 | `restapi/Migrations/004_category_hierarchy.sql:104`<br>`restapi/Migrations/001_initial.sql:448`<br>`app/lib/main.dart:300` |
| ✨ | 闪光 | 分类/兴趣迁移、App/Admin 源码、预览 | social（轻松社交）、social_casual（轻松社交） | `sparkles` | 11 | `preview/admin/admin.js:186`<br>`restapi/Migrations/011_illustrated_other_category.sql:12`<br>`restapi/Migrations/004_category_hierarchy.sql:103`<br>`restapi/Migrations/001_initial.sql:437`<br>`admin/src/App.jsx:583`<br>`app/lib/main.dart:560` |
| ❤ | 爱心 | App/Admin 源码、预览 | — | `heart` | 5 | `preview/app/app.js:406`<br>`admin/src/App.jsx:262`<br>`app/lib/main.dart:2628` |
| 👥 | 多人 | App/Admin 源码 | — | `group` | 1 | `app/lib/main.dart:4266` |
| 💬 | 对话气泡 | 分类/兴趣迁移、App/Admin 源码 | language（语言交换）、study_language（语言交流） | `chat` | 3 | `restapi/Migrations/004_category_hierarchy.sql:100`<br>`restapi/Migrations/001_initial.sql:446`<br>`app/lib/main.dart:4266` |
| ⚙ | 齿轮 | App/Admin 源码、预览 | — | `settings` | 3 | `preview/app/app.js:487`<br>`preview/admin/admin.js:35`<br>`admin/src/App.jsx:16` |
| 🍜 | 面食 | 分类/兴趣迁移 | food（美食探店）、restaurant_meetup（餐厅聚餐） | `noodles` | 2 | `restapi/Migrations/004_category_hierarchy.sql:127`<br>`restapi/Migrations/001_initial.sql:432` |
| 🏃 | 跑步 | 分类/兴趣迁移、预览 | sports（运动健身）、running（跑步） | `running` | 6 | `preview/app/app.js:362`<br>`preview/admin/admin.js:178`<br>`restapi/Migrations/004_category_hierarchy.sql:137`<br>`restapi/Migrations/001_initial.sql:433` |
| 🎭 | 戏剧 | 分类/兴趣迁移 | culture（文化艺术）、culture_show（展览演出）、theatre（戏剧舞台） | `theatre` | 3 | `restapi/Migrations/004_category_hierarchy.sql:94`<br>`restapi/Migrations/001_initial.sql:434` |
| 🏕️ | 露营 | 分类/兴趣迁移 | outdoors（户外旅行）、camping（露营） | `camping` | 2 | `restapi/Migrations/004_category_hierarchy.sql:151`<br>`restapi/Migrations/001_initial.sql:435` |
| 📚 | 书籍 | 分类/兴趣迁移 | study（学习交流）、culture_read（阅读影视） | `books` | 2 | `restapi/Migrations/004_category_hierarchy.sql:95`<br>`restapi/Migrations/001_initial.sql:436` |
| 🍚 | 米饭 | 分类/兴趣迁移 | food（美食） | `rice` | 1 | `restapi/Migrations/001_initial.sql:442` |
| 🏋️ | 举重 | 分类/兴趣迁移 | fitness（健身）、sports_fitness（健身训练）、gym_workout（健身房训练） | `workout` | 3 | `restapi/Migrations/004_category_hierarchy.sql:92`<br>`restapi/Migrations/001_initial.sql:444` |
| 🎬 | 电影 | 分类/兴趣迁移 | movies（电影）、movie_club（电影放映） | `movie` | 2 | `restapi/Migrations/004_category_hierarchy.sql:146`<br>`restapi/Migrations/001_initial.sql:445` |
| 📷 | 相机 | 分类/兴趣迁移 | photography（摄影） | `camera` | 2 | `restapi/Migrations/004_category_hierarchy.sql:147`<br>`restapi/Migrations/001_initial.sql:447` |
| 🍽️ | 餐具 | 分类/兴趣迁移 | food_dining（聚餐探店） | `dining` | 1 | `restapi/Migrations/004_category_hierarchy.sql:88` |
| 🧑‍🍳 | 厨师 | 分类/兴趣迁移 | food_cooking（烹饪饮品） | `chef` | 1 | `restapi/Migrations/004_category_hierarchy.sql:90` |
| ⚽ | 足球 | 分类/兴趣迁移 | sports_ball（球类运动）、football（足球） | `football` | 2 | `restapi/Migrations/004_category_hierarchy.sql:91` |
| 🧘 | 瑜伽 | 分类/兴趣迁移 | sports_mindbody（身心健康）、yoga（瑜伽） | `yoga` | 2 | `restapi/Migrations/004_category_hierarchy.sql:93` |
| 🎨 | 调色盘 | 分类/兴趣迁移、预览 | culture_make（手作创作）、drawing（绘画） | `art` | 5 | `preview/app/app.js:363`<br>`restapi/Migrations/004_category_hierarchy.sql:96` |
| 🚶 | 步行 | 分类/兴趣迁移、预览 | outdoors_city（城市探索）、city_walk（城市漫步） | `walking` | 3 | `preview/admin/admin.js:154`<br>`restapi/Migrations/004_category_hierarchy.sql:98` |
| 🧳 | 行李箱 | 分类/兴趣迁移 | outdoors_trip（结伴旅行） | `travel` | 1 | `restapi/Migrations/004_category_hierarchy.sql:99` |
| 💼 | 公文包 | 分类/兴趣迁移 | study_career（职业成长） | `career` | 1 | `restapi/Migrations/004_category_hierarchy.sql:101` |
| 🧠 | 大脑 | 分类/兴趣迁移 | study_skill（技能学习） | `learning` | 1 | `restapi/Migrations/004_category_hierarchy.sql:102` |
| 🐾 | 爪印 | 分类/兴趣迁移 | social_life（生活伙伴） | `paw` | 1 | `restapi/Migrations/004_category_hierarchy.sql:105` |
| 🥟 | 饺子 | 分类/兴趣迁移 | street_food（街头美食） | `dumpling` | 1 | `restapi/Migrations/004_category_hierarchy.sql:128` |
| 🥐 | 可颂 | 分类/兴趣迁移 | brunch（早午餐） | `brunch` | 1 | `restapi/Migrations/004_category_hierarchy.sql:129` |
| 🍰 | 蛋糕 | 分类/兴趣迁移 | dessert（甜品烘焙） | `cake` | 1 | `restapi/Migrations/004_category_hierarchy.sql:131` |
| 🍳 | 煎蛋 | 分类/兴趣迁移 | home_cooking（一起做饭） | `cooking` | 1 | `restapi/Migrations/004_category_hierarchy.sql:132` |
| 🍷 | 红酒 | 分类/兴趣迁移 | wine_cocktail（葡萄酒与调酒） | `wine` | 1 | `restapi/Migrations/004_category_hierarchy.sql:133` |
| 🏀 | 篮球 | 分类/兴趣迁移 | basketball（篮球） | `basketball` | 1 | `restapi/Migrations/004_category_hierarchy.sql:135` |
| 🏸 | 羽毛球 | 分类/兴趣迁移 | badminton（羽毛球） | `badminton` | 1 | `restapi/Migrations/004_category_hierarchy.sql:136` |
| 🚴 | 骑行 | 分类/兴趣迁移 | cycling（骑行） | `cycling` | 1 | `restapi/Migrations/004_category_hierarchy.sql:139` |
| 🖼️ | 画框 | 分类/兴趣迁移 | exhibition（展览看展） | `exhibition` | 1 | `restapi/Migrations/004_category_hierarchy.sql:142` |
| 🎵 | 音符 | 分类/兴趣迁移 | concert（音乐演出） | `music` | 1 | `restapi/Migrations/004_category_hierarchy.sql:143` |
| 📖 | 翻开的书 | 分类/兴趣迁移 | book_club（读书会） | `reading` | 1 | `restapi/Migrations/004_category_hierarchy.sql:145` |
| 🧶 | 毛线 | 分类/兴趣迁移 | craft（手工体验） | `craft` | 1 | `restapi/Migrations/004_category_hierarchy.sql:148` |
| 🧺 | 篮子 | 分类/兴趣迁移 | picnic（野餐） | `picnic` | 1 | `restapi/Migrations/004_category_hierarchy.sql:152` |
| 🗺️ | 地图 | 分类/兴趣迁移 | local_tour（街区探索） | `map` | 1 | `restapi/Migrations/004_category_hierarchy.sql:154` |
| 🚆 | 列车 | 分类/兴趣迁移 | day_trip（周边一日游） | `train` | 1 | `restapi/Migrations/004_category_hierarchy.sql:155` |
| ✈️ | 飞机 | 分类/兴趣迁移 | overseas_trip（海外结伴） | `flight` | 1 | `restapi/Migrations/004_category_hierarchy.sql:156` |
| 🇰🇷 | 韩国国旗 | 分类/兴趣迁移 | korean_exchange（韩语交流） | `korea` | 1 | `restapi/Migrations/004_category_hierarchy.sql:157` |
| 🀄 | 麻将红中 | 分类/兴趣迁移 | chinese_exchange（中文交流） | `chinese-exchange` | 1 | `restapi/Migrations/004_category_hierarchy.sql:158` |
| 🔤 | 拉丁字母 | 分类/兴趣迁移 | english_exchange（英语交流） | `english-exchange` | 1 | `restapi/Migrations/004_category_hierarchy.sql:159` |
| 🤝 | 握手 | 分类/兴趣迁移 | networking（行业交流） | `networking` | 1 | `restapi/Migrations/004_category_hierarchy.sql:160` |
| 📄 | 文件 | 分类/兴趣迁移 | job_search（求职互助） | `document` | 1 | `restapi/Migrations/004_category_hierarchy.sql:161` |
| 💻 | 电脑 | 分类/兴趣迁移 | coding（编程学习） | `coding` | 1 | `restapi/Migrations/004_category_hierarchy.sql:162` |
| 📈 | 上升图表 | 分类/兴趣迁移 | finance（理财学习） | `finance` | 1 | `restapi/Migrations/004_category_hierarchy.sql:163` |
| 👋 | 挥手 | 分类/兴趣迁移 | newcomer（新人欢迎） | `welcome` | 1 | `restapi/Migrations/004_category_hierarchy.sql:164` |
| 🌙 | 月亮 | 分类/兴趣迁移 | after_work（下班搭子） | `after-work` | 1 | `restapi/Migrations/004_category_hierarchy.sql:165` |
| 🎮 | 游戏手柄 | 分类/兴趣迁移 | gaming（电子游戏） | `gaming` | 1 | `restapi/Migrations/004_category_hierarchy.sql:167` |
| 🎤 | 麦克风 | 分类/兴趣迁移 | karaoke（唱歌） | `karaoke` | 1 | `restapi/Migrations/004_category_hierarchy.sql:168` |
| 🐕 | 狗 | 分类/兴趣迁移 | pet_walk（宠物散步） | `pet-walk` | 1 | `restapi/Migrations/004_category_hierarchy.sql:169` |
| 📝 | 记事本 | 分类/兴趣迁移 | study_buddy（自习搭子） | `study-buddy` | 1 | `restapi/Migrations/004_category_hierarchy.sql:170` |
| 🛍️ | 购物袋 | 分类/兴趣迁移 | shopping_buddy（购物搭子） | `shopping` | 1 | `restapi/Migrations/004_category_hierarchy.sql:171` |
| ✏️ | 铅笔 | 分类/兴趣迁移 | — | `custom` | 2 | `restapi/Migrations/012_custom_category_leaves.sql:9` |
| 🐻 | 熊 | 预览 | — | `bear` | 10 | `preview/shared/preview.js:31`<br>`preview/app/app.js:279`<br>`preview/admin/admin.js:57` |
| 🐱 | 猫 | 预览 | — | `cat` | 9 | `preview/app/app.js:290`<br>`preview/admin/admin.js:68` |
| 🦉 | 猫头鹰 | 预览 | — | `owl` | 7 | `preview/app/app.js:301`<br>`preview/admin/admin.js:79` |
| 🐰 | 兔 | 预览 | — | `rabbit` | 3 | `preview/app/app.js:509`<br>`preview/admin/admin.js:90` |
| 🐳 | 鲸 | 预览 | — | `whale` | 2 | `preview/app/app.js:509`<br>`preview/admin/admin.js:526` |
| 🦦 | 水獭 | 预览 | — | `otter` | 1 | `preview/admin/admin.js:528` |
| ↗ | 右上箭头 | 预览 | — | `external-link` | 2 | `preview/shared/preview.js:99`<br>`preview/app/app.js:410` |
| 🦊 | 狐狸 | 预览 | — | `fox` | 1 | `preview/app/app.js:509` |

## 替换时的边界

1. 分类、兴趣等彩色图标：统一绘制风格，优先评估 Flutter、React 和离线预览都能显示的 SVG；细节复杂时可提供透明 PNG。三端复用同一套原始素材。
2. 点赞、设置、聊天等功能图标：用已有矢量图标体系统一线条、大小、颜色；无需为每个功能生成彩色 Emoji 图片。
3. 预览中的 🐻 🐱 🦉 🐰 🐳 🦦 🦊 是头像占位示例，不代表正式系统头像需要重新生成。
4. Admin 还用到 ⌁、◉、◇、△、!、⊞、⌖、◎、≡ 等字符导航图标；它们不在 Emoji 计数内，但同样依赖字体，后续应一起评估。Flutter 的 Icons.* 不属于本清单中的 Emoji。
5. 已有 icon_key 字段可作为映射基础，但当前分类插画资源切换尚未实施。不要删除旧 icon 数据、重写历史迁移或硬编码正式分类；先核对配置并保留兼容回退。
6. 图片化后仍需可访问名称及邻近文字，不能把分类含义仅交给图像表达。

## 线上完整性补核

本次未访问 AWS 或读取真实聊天。需要最终替换时，应在服务器只读导出当前分类/兴趣配置，与此清单比对后台新增值：

```sql
SELECT code, name_zh_cn, icon, icon_key FROM category ORDER BY code;
SELECT code, name_zh_cn, icon FROM interest ORDER BY code;
```

本次仅整理，没有修改 App/Admin 显示、头像文件或数据库。

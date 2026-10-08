# DAMUMU 项目决策记录

## 索引

| 编号 | 决策 | 状态 | 日期 |
| --- | --- | --- | --- |
| ADR-001 | 产品品牌统一为 DAMUMU / 搭慕 | 已采用 | 2026-09-11 |
| ADR-002 | 产品介绍网站独立部署 | 已采用 | 2026-09-11 |
| ADR-003 | 新活动直接发布 | 已采用 | 2026-08-29 |
| ADR-004 | 平台不处理活动支付 | 已采用 | 2026-08-29 |
| ADR-005 | 精确集合地点受审批状态保护 | 已采用 | 2026-08-29 |
| ADR-006 | 分类和行政区域由数据库驱动 | 已采用 | 2026-08-29 |
| ADR-007 | 分类 Emoji 展示与图标键保留 | 已采用 | 2026-08-29 |
| ADR-014 | 其它分类的小分类单独存储 | 已采用 | 2026-09-17 |
| ADR-015 | 各大分类的自定义叶子与活动封面规格 | 已采用 | 2026-09-18 |
| ADR-016 | 活动群聊成员跟随有效参与状态 | 已采用 | 2026-09-21 |
| ADR-017 | REST 存储、WebSocket 实时同步与 FCM 后台推送 | 已采用 | 2026-09-21 |
| ADR-018 | 聊天可靠发送、生命周期与跨实例事件转发 | 已采用 | 2026-10-01 |
| ADR-019 | 图片缩略图、不可变缓存与流量升级阈值 | 已采用 | 2026-10-02 |
| ADR-020 | Lightsail 单机测试部署边界 | 已采用 | 2026-10-04 |
| ADR-021 | Lightsail 测试数据库运行在宿主机 | 已采用 | 2026-10-04 |
| ADR-008 | 用户位置标签跟随 App 语言 | 已采用 | 2026-09-07 |
| ADR-009 | 活动容量包含组织者 | 已采用 | 2026-09-08 |
| ADR-010 | 远端业务数据库使用 damumu 名称 | 已采用 | 2026-09-11 |
| ADR-011 | 客户端统一隐藏服务器技术异常 | 已采用 | 2026-09-11 |
| ADR-012 | APP 活动流使用 Cursor 分页 | 已采用 | 2026-09-11 |
| ADR-013 | 项目文档按职责维护单一入口 | 已采用 | 2026-09-17 |

---

## ADR-001：产品品牌统一为 DAMUMU / 搭慕

状态：已采用
日期：2026-09-11

### 背景

产品曾存在不一致的拉丁字母品牌写法。

### 决定

产品拉丁字母品牌统一为 `DAMUMU`，中文 UI 名称统一为“搭慕”。

### 原因

统一产品文案、网站、文档和运营表达，避免用户认知分裂。

### 替代方案

- 保留旧品牌：兼容成本低，但会继续造成命名不一致。
- 同时展示多个品牌：迁移平滑，但长期维护和传播成本更高。

### 影响

- 新增产品文案必须使用 DAMUMU。
- 小写或 PascalCase 技术标识只有在单独规划兼容迁移时才调整。

### 相关位置

- `AGENTS.md`
- `website/`

## ADR-002：产品介绍网站独立部署

状态：已采用  
日期：2026-09-11

### 背景

营销介绍页与登录后的产品界面面向不同用户，发布节奏也不同。

### 决定

介绍网站作为 `website/` 下的独立静态站点，不依赖 Flutter、API 或 Admin 运行时。

### 原因

降低耦合并允许营销内容独立发布。

### 替代方案

- 合并进 Flutter Web：共享部分视觉，但会增加首屏体积和发布耦合。
- 合并进 Admin：技术简单，但受众和权限边界错误。

### 影响

- 网站只能描述真实已实现或明确规划的能力。
- 网站必须遵守活动费用和位置隐私规则。

### 相关位置

- `website/`

## ADR-003：新活动直接发布

状态：已采用  
日期：2026-08-29

### 决定

新活动以 `published` 状态保存并立即获得 `published_at`；当前 `review_status` 为 `not_required`。

### 原因

MVP 不要求活动发布前经过管理员审批。

### 替代方案

- 强制管理员预审：治理更严格，但阻断 MVP 发布流程且增加运营成本。

### 影响

- 未形成新产品决策前，不得增加强制待审核页面或隐藏新活动。

### 相关位置

- `restapi/Endpoints/EventEndpoints.cs`
- `restapi/Migrations/001_initial.sql`

## ADR-004：平台不处理活动支付

状态：已采用  
日期：2026-08-29

### 决定

DAMUMU 只展示组织者填写的线下预计人均韩元支出，不提供收款、转账、托管、退款或资金担保。

### 原因

支付不在 MVP 范围内，陌生人提前转账也带来诈骗和安全风险。

### 替代方案

- 平台内支付或托管：体验完整，但显著增加合规、安全和退款责任。

### 影响

- 金额 0 表示免费。
- 报名确认和产品文案不得暗示平台收费或担保。

### 相关位置

- `MVP.md`
- `FIRST_RELEASE_FLOWS.md`

## ADR-005：精确集合地点受审批状态保护

状态：已采用  
日期：2026-08-29

### 决定

活动列表永不返回精确集合地点；详情仅向组织者或状态为 `approved`、`attended` 的参与者返回。

### 原因

线下精确位置属于敏感信息，只应向已获准参与的人公开。

### 替代方案

- 对所有登录用户公开：实现简单，但存在明显隐私与线下安全风险。

### 影响

- 匿名、申请中、候补、被拒和已退出用户只能看到公开城市/区域信息。
- 新增详情与参与接口必须维持这一授权边界。

### 相关位置

- `restapi/Endpoints/EventEndpoints.cs`
- `FIRST_RELEASE_FLOWS.md`

## ADR-006：分类和行政区域由数据库驱动

状态：已采用  
日期：2026-08-29

### 决定

Flutter 从 API 加载活动分类和行政区域，并使用稳定行政代码作为标识。

### 原因

避免多客户端硬编码目录分叉，并允许运营后台更新名称、排序和启停状态。

### 替代方案

- 客户端硬编码：离线简单，但目录更新需发布客户端且容易不一致。

### 影响

- 生产目录不得重新硬编码到 Dart。
- 已被引用的行政区域应停用而非物理删除。

### 相关位置

- `app/lib/category_service.dart`
- `app/lib/event_service.dart`
- `restapi/Migrations/004_category_hierarchy.sql`
- `restapi/Migrations/008_administrative_regions.sql`

## ADR-007：分类 Emoji 展示与图标键保留

状态：已采用  
日期：2026-08-29

### 决定

发布页一级分类使用 API 提供的 emoji 和文字，显示为横向矩形按钮。`icon_key` 保留在数据库和 API 中，但当前 App 不加载分类插画资源。新增分类仍由数据库/API 提供，App 不维护分类目录。

### 原因

用户实际查看后选择恢复更清晰的 emoji 按钮；移除不用的插画还能减小 App 资源包。保留 `icon_key` 不改变既有分类数据和接口兼容性。

### 替代方案

- 立即全部改为 Material/SVG：视觉统一，但缺少兼容迁移会造成数据损坏。

### 影响

- 图标体系变化必须包含新 Migration、回退逻辑和 App/Admin/API 协同修改。

### 相关位置

- `restapi/Migrations/011_illustrated_other_category.sql`
- `app/lib/main.dart`

## ADR-014：其它分类的小分类单独存储

状态：已采用
日期：2026-09-17

### 决定

“其它”是固定一级分类，发布时选择固定二级分类 `other_custom`，用户填写的小分类名称另存于 `event.custom_subcategory`，去除首尾空白后限 1 至 15 字。活动列表和详情显示用户填写的名称；管理员仍能按固定分类 ID 查询和统计。发布页默认展示六个精选一级分类及“其它”，其余一级分类通过“显示更多分类”展开。各一级分类下的自定义叶子扩展见 ADR-015。

### 原因

每次发布都创建新的全局分类会让目录迅速膨胀，也会把用户输入误当成管理员维护的分类。固定 ID 保留筛选和统计能力，独立字段保留每场活动的原始描述。

### 相关位置

- `restapi/Migrations/011_illustrated_other_category.sql`
- `restapi/Endpoints/EventEndpoints.cs`
- `app/lib/main.dart`

## ADR-015：各大分类的自定义叶子与活动封面规格

状态：已采用
日期：2026-09-18

### 决定

每个一级分类都有一个固定的“其它”二级分类，分类行以 `requires_custom_label` 标识。选择该叶子时，发布者须填写去空白后 1 至 15 字的活动专属小分类名称；普通叶子拒绝此字段。新增一级分类由数据库触发器自动补齐该叶子。独立字段保留固定分类 ID 的统计能力，避免把自由文本写入全局分类表。

活动封面选填一张。用户直接选择设备照片；客户端先限制输入边长以控制解码与裁剪时的内存，再锁定 4:3 裁剪并输出 1280×960 JPEG。2 MB 是最终上传文件的上限，客户端按画质逐级压缩，API 复核类型、尺寸和大小。无法在设备上处理的极大文件或不支持的格式显示明确错误，不承诺对 1–2 GB RAW 文件原地解码。上传生成归属当前用户的媒体资产，发布活动时只可关联本人可用资产。创建失败时客户端尽力删除未关联图片。封面 URL 在活动列表和详情公开，精确集合地点仍按参与状态保护。暂存于 API 本地 `uploads/events`，未来可替换存储后端。

Web 裁剪器依赖 Cropper.js 1.6.2，静态资源随 App 本地提供，以避免浏览器运行时取不到脚本或样式导致裁切框、旋转与确认失效。头像和活动图片共用此 Web 运行依赖，并在裁剪后提供水平翻转。

### 原因

固定叶子和单独文本兼顾分类统计与自由补充。4:3 横图适合列表缩略图和详情横幅；1280×960 JPEG 在手机上够清晰，并以 2 MB 上限控制上传与存储成本。

### 相关位置

- `restapi/Migrations/012_custom_category_leaves.sql`
- `restapi/Endpoints/EventEndpoints.cs`
- `app/lib/event_cover_image.dart`、`app/lib/main.dart`

## ADR-016：活动群聊成员跟随有效参与状态

状态：已采用
日期：2026-09-21

### 决定

每个活动创建时生成一个唯一的活动群聊。组织者以及活动成员状态为 `approved`、`attended` 且未退出活动的用户默认拥有群聊成员资格；申请中、候补、被拒或退出活动的用户不在群聊中。活动成员状态变化由数据库触发器同步到会话成员表，已有活动在迁移时补齐群聊和有效成员。用户也可以只退出活动群聊；该主动退出标记会被保留，后续成员同步不会自动把用户重新加入。

聊天消息和站内通知分别维护未读状态；用户可逐项已读，也可一次标记全部会话和通知为已读。私信删除采用个人列表隐藏，新消息到达时重新出现；通知删除采用个人软删除。群聊资格只决定聊天访问权，不改变精确集合地点原有的授权规则。

### 原因

数据库同步可覆盖 API、后台任务和后续管理工具产生的成员状态变化，避免群聊成员与实际获批参与者分叉。每个活动的唯一索引可防止重试或并发创建重复群聊。

### 相关位置

- `restapi/Migrations/013_notifications_event_chat.sql`
- `restapi/Migrations/014_event_chat_organizer_membership.sql`
- `restapi/Migrations/016_member_profiles_and_message_actions.sql`
- `restapi/Endpoints/SocialEndpoints.cs`
- `app/lib/social_service.dart`、`app/lib/main.dart`

## ADR-017：REST 存储、WebSocket 实时同步与 FCM 后台推送

状态：已采用
日期：2026-09-21

### 决定

聊天消息、通知和已读状态继续由 PostgreSQL 持久化，并通过 REST API 读写。Flutter 登录后建立一条经过首帧令牌认证的 WebSocket 连接；服务端只推送 `message.created`、`notification.created` 等轻量同步事件，客户端收到后从 REST API 重新读取权威数据。连接断开时指数退避重连，重连或 App 恢复后通过 REST 补齐数据。

App 在后台或被系统挂起时使用 Firebase Cloud Messaging。客户端令牌保存在 `push_device`，服务端凭据只从 Application Default Credentials 读取；未配置 Firebase 时推送服务自动停用，站内通知和 WebSocket 继续工作。FCM 只作为提醒和唤醒通道，不作为消息存储或顺序依据。

### 原因

原生 WebSocket 的 Dart 客户端覆盖 Web、Android 和 iOS，避免依赖缺少 Flutter Web 支持的第三方 SignalR 客户端。REST 同步可容忍 WebSocket 和 FCM 的延迟、断线、重复或乱序投递。首帧认证避免把用户令牌放入 WebSocket URL 和访问日志。

### 影响

- 单 API 实例使用内存连接表；多实例部署前须增加 Redis 等跨实例事件总线。
- Firebase 项目、Web VAPID、公钥配置和服务账号凭据由部署环境提供，不提交仓库。
- 新实时事件只能作为同步提示，业务成功与否仍由数据库事务和 REST 响应决定。

### 相关位置

- `restapi/Infrastructure/RealtimeConnectionManager.cs`
- `restapi/Infrastructure/PushNotificationService.cs`
- `restapi/Migrations/015_push_devices.sql`
- `app/lib/realtime_service.dart`
- `app/lib/push_notification_service.dart`

## ADR-008：用户位置标签跟随 App 语言

状态：已采用  
日期：2026-09-07

### 决定

反向地理编码标签使用 App 当前语言，而不是设备或浏览器语言；不同语言使用隔离缓存。无法使用自动定位时，用户可从 API 返回的行政区中手动选择城市和区域；本地只保存稳定地区代码，展示名称按当前 App 语言从行政区数据重新生成。

### 原因

避免 App 为简体中文时显示繁体或复用其他语言的旧缓存。

### 替代方案

- 跟随设备语言：无需额外参数，但会与 App 内语言设置冲突。

### 影响

- 后续地理编码器必须接收当前 App 语言，不得跨语言复用可读位置标签。
- 手动定位不得内置生产地区目录或保存语言相关名称，活动列表使用行政区代码筛选。

### 相关位置

- `app/lib/location_service.dart`

## ADR-009：活动容量包含组织者

状态：已采用  
日期：2026-09-08

### 决定

组织者是活动第一个已批准参与者，并占用一个容量名额。

### 原因

公开人数和剩余容量应反映所有实际参加者，包括组织者。

### 替代方案

- 容量只计算报名者：实现常见，但显示人数与现场实际人数不一致。

### 影响

- 新活动 `approved_count` 从 1 开始。
- 历史修复和未来计数必须包含组织者及参与者 party size。

### 相关位置

- `restapi/Migrations/009_count_organizer_in_capacity.sql`
- `restapi/Endpoints/EventEndpoints.cs`

## ADR-010：远端业务数据库使用 damumu 名称

状态：已采用  
日期：2026-09-11

### 背景

远端 PostgreSQL 业务数据库曾沿用旧名称 `muda`。

### 决定

远端业务数据库标准名称为 `damumu`，应用通过外部配置连接该名称。

### 原因

数据库名称与当前产品品牌和部署约定保持一致。

### 替代方案

- 保留旧数据库名：无需调整连接，但会继续造成运维命名混乱。

### 影响

- 部署环境变量、备份脚本和连接配置必须使用 `damumu`。
- 凭据不得提交到版本库，应通过环境变量或秘密管理服务提供。

### 相关位置

- `restapi/appsettings.json`
- `docs/PROJECT.md`

## ADR-011：客户端统一隐藏服务器技术异常

状态：已采用  
日期：2026-09-11

### 背景

服务器返回非 JSON 或数据库异常时，Flutter 曾把 `FormatSyntaxError`、Npgsql 文本等内部细节直接显示给用户。

### 决定

HTTP 400/500、连接失败、超时、空响应、非 JSON 及技术异常必须转换为安全错误；读取内容失败时在内容区域显示统一、可重试的错误状态。

### 原因

技术信息对用户无帮助，也可能泄露内部实现；一致的错误体验更清晰且便于后续扩展。

### 替代方案

- 每个页面单独拼装异常文本：实施快，但容易遗漏并导致视觉和安全行为不一致。
- 原样展示服务器错误：便于开发调试，但不适合用户环境且存在信息泄露风险。

### 影响

- 页面不得直接渲染 `snapshot.error` 或异常对象。
- API 仍应返回统一 envelope；客户端必须对非规范响应提供安全兜底。
- 提交类操作可保留当前页面，但只能展示经过清洗的友好提示。

### 相关位置

- `app/lib/event_service.dart`
- `app/lib/main.dart`
- `app/lib/l10n.dart`


## ADR-012：APP 活动流使用 Cursor 分页

状态：已采用  
日期：2026-09-11

### 决定

- APP 公开活动列表使用 `GET /api/v1/activities?limit=20&cursor=...`。
- 沿用 `ApiSupport.Ok` envelope，`data` 内为 `{ items, nextCursor, hasMore }`。
- 按 `event.created_at DESC, event.id DESC` 固定排序；`id` 即活动 UUID。
- 使用 keyset 条件及 `limit + 1`，游标保存版本、UTC 创建时间和 UUID，Base64URL 编码；限制长度并校验格式、版本、时间和 UUID。游标是公开查询位置，不是授权凭证，解码结果仅用于参数化 SQL。
- 最后一页 `nextCursor=null, hasMore=false`。新增活动通过刷新获得；分页时应保留相同过滤条件，变更定位或查询条件时丢弃旧游标。
- 保留原 `/events` 兼容接口和后台分页。其他 APP 列表未来优先遵循 Cursor 规则，本次不宣称已迁移消息、评论和我的活动。

### 原因与边界

offset 会随列表头部插入/删除发生位置偏移；创建时间与 UUID keyset 可避免这一问题，并可在边界活动被删除后继续查询。它不是数据库快照，活动可见性等业务字段变化仍可能改变结果集合。当前 APP 搜索/分类/日期筛选仍作用于已加载活动，UI 明确提示这一范围；服务端保留城市、区域、分类、关键词、时间和地理范围参数，地理范围不改变固定创建顺序。

### 相关位置

- `restapi/Endpoints/ActivityEndpoints.cs`
- `restapi/Infrastructure/ActivityCursor.cs`
- `restapi/Infrastructure/ActivityQueries.cs`
- `restapi/Migrations/010_activity_cursor_index.sql`
- `app/lib/event_service.dart`、`app/lib/main.dart`

## ADR-013：项目文档按职责维护单一入口

状态：已采用

日期：2026-09-17

### 决定

`AGENTS.md` 规定工作规则，`docs/PROJECT.md` 保存稳定的产品和系统事实，`docs/STATUS.md` 只记录当前实现状态、待办和阻塞，`docs/DECISIONS.md` 保存长期决策及原因。模块操作写在各自的 `README.md`。`FIRST_RELEASE_FLOWS.md` 表示目标范围，`MVP.md` 是早期方案；二者都不是实现状态。实际代码、迁移和验证结果优先于文档。

### 原因

旧根目录的项目、交接、决策和开发上下文文档与当前文档重复，且包含过期迁移编号与接手步骤。多份“当前状态”容易产生矛盾。旧内容保留在 Git 历史中，必要时可追溯。

### 影响

只在对应文档维护新事实，不把完成日志持续堆入 `docs/STATUS.md`；判断功能是否完成时要核对真实数据路径。

## ADR-014：活动结束后的参与者反馈与风险提示

状态：已采用
日期：2026-09-30

### 决定

- 只有同一活动中仍有效的组织者、已通过或已签到成员，才可在活动结束后评价；不能评价自己，每个活动上下文内对同一对象各保留一条喜欢和一条举报。
- 对活动的反馈归集到活动组织者，对成员的反馈归集到目标用户。喜欢展示总数及最多三个常用正向标签。
- 举报继续进入统一治理 `report` 流程。客户端不展示举报人或原始举报数；同一目标、同一举报标签须由至少 3 名不同参与者提交，且状态不是 `dismissed`，才向未来参与者显示频率最高的标签。
- 组织者的活动举报提示显示在其后续活动卡片，成员举报提示只在该成员申请其他活动时向审核组织者显示。

### 原因

活动结束和共同参与关系提供可核验的互动背景。正向标签比单一分数更有解释力；举报阈值、去重和驳回过滤可降低单人报复或误操作造成公开伤害的风险，同时把需要处理的内容保留在后台治理流程中。

### 影响

- 风险标签是参与决策提示，不代表平台对事实作出最终认定。
- 调整公开阈值或可选标签时，必须同步 API allowlist、Flutter 本地化与相关测试。
- 数据库需应用 `017_post_event_feedback.sql`。

### 相关位置

- `restapi/Infrastructure/FeedbackPolicy.cs`
- `restapi/Endpoints/FeedbackEndpoints.cs`
- `restapi/Migrations/017_post_event_feedback.sql`
- `app/lib/feedback.dart`

## ADR-018：聊天可靠发送、生命周期与跨实例事件转发

状态：已采用
日期：2026-10-01

### 决定

- 消息、会话更新时间和接收者站内通知在同一个 PostgreSQL 事务中写入。客户端为每次发送生成 `client_message_id`，网络重试返回原消息，不重复创建消息或通知。
- 历史消息以 `(created_at, id)` 复合游标分页。客户端缓存最近 100 条消息，并按用户与会话隔离；未确认消息持久化在本机，恢复网络或重新进入会话时使用原客户端 ID 重试。
- 文本消息可在 15 分钟内编辑、5 分钟内撤回。消息举报保存举报时的目标消息和相邻上下文快照；聊天图片存为当前 API 的本地媒体资产，消息只引用媒体 ID。
- 活动群在最后日程结束 7 天后只读，结束 180 天后归档；活动取消通知写入后立即只读。后台每小时刷新生命周期，API 仍在写入时校验会话状态。
- 多 API 实例使用 PostgreSQL `LISTEN/NOTIFY` 转发轻量实时同步事件。每个实例只向自己的 WebSocket 连接发送事件，实例来源 ID 防止本机重复投递；REST 和数据库仍是权威来源。

### 原因

事务与幂等键解决弱网重试造成的重复和“消息已保存但客户端显示失败”。复合游标避免相同时间戳消息被跳过。PostgreSQL 通知复用现有基础设施，足以支撑当前轻量同步事件，并避免在现阶段新增 Redis 运维依赖。

### 影响

- PostgreSQL 通知负载只允许轻量 ID 事件，不承载消息正文或业务成功状态；客户端收到事件后仍通过 REST 同步。
- 本地图片目录仍需在多 API 实例部署前迁移到共享对象存储。
- 所有数据库环境需应用 `018_chat_reliability.sql`。

### 相关位置

- `restapi/Migrations/018_chat_reliability.sql`
- `restapi/Infrastructure/Db.cs`
- `restapi/Infrastructure/RealtimeConnectionManager.cs`
- `restapi/Infrastructure/RealtimeRelayService.cs`
- `restapi/Infrastructure/ConversationLifecycleService.cs`
- `restapi/Endpoints/SocialEndpoints.cs`
- `app/lib/social_service.dart`、`app/lib/main.dart`

## ADR-019：图片缩略图、不可变缓存与流量升级阈值

状态：已采用
日期：2026-10-02

### 决定

- 新活动封面和聊天图片在保留原图的同时，由 API 生成 WebP 缩略图；活动使用最长边 640px，聊天使用最长边 320px，缩略图目标范围为 50–200 KB，强制上限 200 KB。
- 活动列表、聊天记录和图片气泡默认返回并加载缩略图。只有用户主动打开大图预览时，客户端才请求原图。历史媒体没有缩略图时回退原图，避免迁移后内容失效。
- 本地媒体使用 UUID 文件名且禁止覆盖，`/uploads` 使用一年 `Cache-Control: public, immutable`。媒体发生变化时创建新资产 URL。
- 当前只接受静态 JPEG、PNG 和 WebP 图片，不增加视频或 Live Photo 的上传、下载和转码链路。
- 每月出站流量达到 2 TB 时，结合缓存命中率、源站带宽和运营成本评估对象存储/CDN；达到阈值不自动改变基础设施。

### 原因

列表滚动和聊天历史会重复显示大量图片，缩略图与浏览器长期缓存能直接减少 API 服务器的出站流量。保留按需原图保证查看体验，同时避免现阶段承担视频的带宽与转码成本。

### 影响

- 所有数据库环境需应用 `019_media_thumbnails.sql`。
- 本地文件目录仍是单实例部署方案；采用多 API 实例或达到流量阈值后，需要把原图与缩略图迁移到共享对象存储，并保持不可变 URL 合约。

### 相关位置

- `restapi/Migrations/019_media_thumbnails.sql`
- `restapi/Infrastructure/ImageThumbnailService.cs`
- `restapi/Endpoints/EventEndpoints.cs`
- `restapi/Endpoints/SocialEndpoints.cs`
- `app/lib/main.dart`、`app/lib/social_service.dart`

## ADR-020：Lightsail 单机测试部署边界

状态：已采用
日期：2026-10-04

### 决定

- 测试环境先使用一台 Ubuntu Lightsail 实例。宿主机 Nginx 是唯一公网入口，Admin 和 API 容器只绑定回环地址，不直接开放容器端口；Flutter `app/` 只作为 Android/iOS 客户端构建，不部署 Flutter Web。
- 公网按主机名分流：`www.damumu.com` 提供独立产品主页，`api.damumu.com` 提供移动端公共 API，`admin.damumu.com` 提供 Admin 及其同源管理 API 代理，根域名跳转到 `www`。三个容器继续只绑定回环端口，Lightsail 不开放 8080 至 8082。
- `/api/v1/realtime` 保留 WebSocket Upgrade；`/uploads` 和 API 同源。API 的 `uploads` 使用 Docker 命名卷，在单实例阶段保持持久化。
- 当前 PostgreSQL 位于 Tailscale 私网，Lightsail 必须加入同一 Tailnet；不得为了部署开放公网 5432。
- 测试 Admin 在现有静态 API Key 外增加 Nginx Basic Auth。该组合不视为正式生产认证，正式上线前必须改为管理员登录、短时 Cookie、RBAC 和二次验证。
- 部署秘密只存在于服务器权限为 600 的 `deploy/.env` 或外部凭据文件，不进入镜像源文件或 Git。

### 原因

单机编排符合当前测试流量和本地媒体存储约束，也能以最少基础设施验证真实域名、HTTPS、WebSocket、上传和推送链路。回环端口与双层 Admin 保护降低测试阶段暴露开发接口和静态 Key 的风险。

### 影响

- 多 API 实例前必须把上传目录迁移到共享对象存储。
- Lightsail 自动快照不能替代数据库独立备份；升级或删除实例前保留手动快照。
- Admin 使用 `admin.damumu.com/api/v1` 的相对同源地址，避免把 Basic Auth 凭据跨域发送；公共 API 域名拒绝管理 API 路径。Android/iOS 客户端必须重新构建并指向 `https://api.damumu.com/api/v1`。

### 相关位置

- `deploy/compose.yaml`
- `deploy/nginx/damumu.conf`
- `deploy/README.md`
- `admin/Dockerfile`

## ADR-021：Lightsail 测试数据库运行在宿主机

状态：已采用
日期：2026-10-04

### 决定

- Lightsail 测试环境使用宿主机 PostgreSQL 18/PostGIS，不再把 Tailscale 远端数据库作为运行时依赖；Tailscale 仅用于一次性迁移旧数据。
- API 仍运行在容器中，通过固定 `172.30.0.0/24` Compose 内网连接 `host.docker.internal`。`pg_hba.conf` 只允许 `damumu_app` 从该网段访问 `damumu`，UFW 同样只允许该网段访问 5432。
- Lightsail 公网防火墙不得开放 5432。数据库备份与实例快照分别执行，快照不替代逻辑备份。

### 原因

单机测试阶段把数据库留在宿主机可以降低卷、容器升级和误执行 `down -v` 的操作风险，同时保持应用容器可重复构建。固定容器网段使数据库规则可审计，不需要向公网或任意私网来源开放数据库。

### 影响

- 宿主机 PostgreSQL 必须先于 API 启动，并由系统包管理器维护安全更新。
- 迁移到多实例或托管数据库前，需要替换连接地址、启用传输加密并重新评估备份与故障恢复。
- ADR-020 中关于 Tailscale 远端数据库作为运行时前置条件的部分由本决定取代；其余单机入口、回环端口、上传卷和 Admin 保护仍有效。

### 相关位置

- `deploy/compose.yaml`
- `deploy/.env.example`
- `deploy/README.md`

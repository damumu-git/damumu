# MUDA 开发上下文（新 Session 必读）

> 作用：让新的 Codex Session 在开始工作前快速恢复项目认知。
>
> 最后更新：2026-08-29（Asia/Seoul）
>
> 新 Session 的第一步：完整阅读本文件；修改前再检查相关源码，因为本文件可能落后于后续代码。

## 1. 项目是什么

MUDA（界面名称目前主要为“搭慕慕”）是在韩国使用的线下活动与“找搭子”应用。
用户可以注册、发现附近活动、发布活动、报名、与参与者沟通，并使用安全与举报能力。

项目由三个部分组成：

| 模块 | 目录 | 技术 | 本地地址 |
|---|---|---|---|
| 用户 App | `app/` | Flutter / Dart | Flutter Web 常用 `http://localhost:3000` |
| REST API | `restapi/` | ASP.NET Core 10 / PostgreSQL + PostGIS | `http://localhost:8080/api/v1` |
| 运营后台 | `admin/` | React 19 / Vite | `http://localhost:5173` |

数据库本地通过 Docker 运行。当前机器上曾使用的容器名是 `mudazi-postgres`；旧 README 示例写的是
`muda-postgres`，执行数据库命令前先用 `docker ps` 确认实际名称。

## 2. 快速启动

在项目根目录执行：

```bash
./dev.sh -d chrome --web-port 3000
```

这会一起启动 API、Admin 和 Flutter Web App。地址：

- App：`http://localhost:3000`
- Admin：`http://localhost:5173`
- API：`http://localhost:8080/api/v1`
- OpenAPI：`http://localhost:8080/openapi/v1.json`

只启动 API 和 Admin：

```bash
./dev.sh --services
```

开发日志位于 `.dev-logs/restapi.log` 和 `.dev-logs/admin.log`。按 `Ctrl+C` 停止脚本启动的服务。

Flutter 运行期间：

- `r`：Hot Reload，保留当前页面状态。
- `R`：Hot Restart，清空页面状态并重新执行初始化。

如果修改了 App 初始化、数据服务或全局状态，优先使用 `R`。

## 3. 本地环境与账号

主要版本：

- Flutter / Dart：`app/pubspec.yaml` 要求 Dart `^3.12.2`。
- API：`.NET 10`，项目文件为 `restapi/Muda.Api.csproj`。
- Admin：React `19.2.x`，Vite `8.1.x`。
- PostgreSQL/PostGIS：迁移脚本依赖 `geography(Point, 4326)`。

本地 App 测试账号：

```text
邮箱：tester@muda.local
密码：MudaTest2026!
```

Debug 构建默认尝试自动登录该账号。相关 Dart Define：

```text
DEV_AUTO_LOGIN
DEV_TEST_EMAIL
DEV_TEST_PASSWORD
API_BASE_URL
```

Admin 本地 API Key：

```text
X-Admin-Key: muda-admin-local
```

以上认证方式仅适合本地开发；生产环境必须替换 Admin Key 和当前自定义 Token 方案。

## 4. 关键目录和代码入口

### Flutter App

- `app/lib/main.dart`
  - 当前绝大多数页面、组件和本地 UI 状态仍集中在此文件。
  - 包含首页、发现、发布、消息、我的、活动详情、安全中心等。
  - 文件已经较大，继续开发时应逐步拆分 feature/page/widget。
- `app/lib/auth.dart`
  - 注册、登录、Token 保存、资料、头像与 `AuthScope`。
- `app/lib/event_service.dart`
  - 活动列表、活动发布、我的活动、行政地区 API。
- `app/lib/category_service.dart`
  - 活动分类目录 API。
- `app/lib/location_service.dart`
  - 浏览器/设备定位、反向地理编码和本地缓存。
- `app/lib/l10n.dart`
  - 中文、英文、韩文文案映射。新增正式 UI 文案应进入此处，避免继续散落硬编码。

### REST API

- `restapi/Program.cs`：服务注册、CORS、中间件、路由组入口。
- `restapi/Infrastructure/Db.cs`：轻量数据库访问及报名/审核事务逻辑。
- `restapi/Infrastructure/ApiSupport.cs`：统一响应、用户身份和 Admin Key 校验。
- `restapi/Endpoints/UserEndpoints.cs`：认证、用户资料、头像、我的活动、通知、屏蔽。
- `restapi/Endpoints/EventEndpoints.cs`：活动列表、详情、发布、修改、报名、退出、审核、签到。
- `restapi/Endpoints/CatalogEndpoints.cs`：分类、兴趣、行政地区和公开配置。
- `restapi/Endpoints/SocialEndpoints.cs`：会话、消息、评价。
- `restapi/Endpoints/SafetyEndpoints.cs`：紧急联系人、安全会面。
- `restapi/Endpoints/GovernanceEndpoints.cs`：举报与用户自己的举报记录。
- `restapi/Endpoints/AdminEndpoints.cs`：运营后台全部接口。
- `restapi/Migrations/`：按编号顺序执行的 SQL 迁移。

### Admin

- `admin/src/App.jsx`：当前所有 Admin 页面与主要交互。
- `admin/src/api.js`：Admin API Client。
- `admin/src/App.css`：Admin 样式。

Admin 也较为集中，后续应按页面拆分，但不要在功能闭环未稳定时进行纯重构。

## 5. 数据库与迁移

当前迁移：

```text
001_initial.sql
002_user_auth.sql
003_system_avatar.sql
004_category_hierarchy.sql
005_preset_avatars.sql
006_mvp_core.sql
007_more_preset_avatars.sql
008_administrative_regions.sql
```

新增环境或数据库升级时必须按编号执行全部迁移：

```bash
for migration in restapi/Migrations/*.sql; do
  docker exec -i <实际容器名> psql -v ON_ERROR_STOP=1 -U muda -d muda < "$migration"
done
```

`008_administrative_regions.sql`：

- 创建 `administrative_region`。
- 预置首尔、釜山、仁川、京畿道及部分下级区域，共 24 条基础数据。
- 允许手动集合点暂时没有经纬度（`place.public_geo` 可空）。

行政地区策略：

- 标准行政代码作为稳定主键。
- App 从 `GET /regions` 动态加载，不在 Flutter 中写死。
- Admin 可以增删改、启停、排序、多语言命名。
- 已被活动或子地区引用的地区不可删除，只能停用。
- 长期方向是“官方行政数据为事实源，Admin 管理展示策略”，目前预置数据不是完整韩国行政区全集。

## 6. 已确定的产品和数据规则

### 活动发布与审核

- 新活动发布后立即公开，数据库状态为 `published`。
- `published_at` 在创建时写入。
- 当前 `review_status = not_required`。
- 已预留 Admin 审核接口 `POST /admin/events/{id}/review`，未来可切换为待审核策略。

### 活动费用

- 平台不收取活动费用，也不提供在线支付、转账或担保。
- 创建者可以填写“预计人均线下花销”，单位目前为 KRW。
- App 当前用单个金额，同时写入 `price_min` 和 `price_max`；`price_amount` 随后用于展示。
- 金额 `0` 表示免费；大于 0 显示“预计 ₩金额/人”。
- 报名前需要展示反诈骗和人身财产安全提醒（尚未与真实报名 UI 完整接通）。

### 地点隐私

- 活动列表不返回准确集合点。
- 活动详情只对以下用户返回准确集合点：
  - 活动组织者；
  - 报名状态为 `approved` 或 `attended` 的用户。
- 需要审核的活动：只有审核通过者可看。
- 无需审核的活动：只有成功抢到名额并进入 `approved` 的用户可看。
- 匿名、未报名、申请中、候补、拒绝的用户只能看到城市和区域。

### 分类图标

- 数据库当前仍主要保存 Emoji 字符串，App 直接显示。
- 用户倾向考虑不使用 Emoji。
- 推荐后续方案：数据库保存稳定 `icon_key`，Flutter 映射到 Material Icons；未来可扩展 SVG。
- 此方案尚未实施，不要在没有确认迁移方式前删除现有 `icon` 数据。

## 7. 当前真实联动状态

### 已真实接入 API / 数据库

- 注册、登录、登录态恢复。
- 用户资料读取与部分更新。
- 系统头像列表、选择与上传。
- 活动分类加载。
- 行政地区加载。
- 活动发布：`POST /events`。
- 首页/发现活动列表：`GET /events`。
- 发布成功后回首页并重新加载数据库活动。
- “我的活动”：`GET /me/activities`。
  - 分为“我发布的”和“我参加的”。
  - 返回时间、地区、费用、活动状态、报名状态等。
- Admin：用户、活动、举报、安全警报、分类、地区、头像、Feature Flags、审计、公告。

### API 已存在，但 App 尚未完整接入

- 活动详情：API 有 `GET /events/{id}`，App 详情页仍主要使用列表对象和本地状态。
- 真实报名/退出：API 有 `/events/{id}/join` 和 `/leave`，App 当前报名交互仍有模拟逻辑。
- 组织者审核报名：API 已有 members/approve/reject，App 尚缺组织者管理页面。
- 活动编辑、取消、签到：API 已有，App 尚未形成完整入口。
- 会话与消息：API 已有，App 消息页面仍大量使用演示数据。
- 通知：API 已有，App 通知页仍主要是演示内容。
- 举报、屏蔽、评价、安全会面：API 有骨架或完整端点，App 大多未真实接通。

### 仍是演示或占位内容

- `main.dart` 中仍保留 `demoEvents`，主要供 Widget Test 注入，不应作为生产数据源。
- 消息、私聊和通知列表中的示例内容。
- “我的”页面中的部分统计数字仍是静态展示。
- 信誉评价、屏蔽与举报、帮助规则、隐私与账号管理目前跳转到说明页，避免点击无响应，但不是完整业务页面。
- UI 文案和部分页面尚未完全三语化。

## 8. 重要实现细节与已知技术债

1. `EventItem.id` 在 App 仍是 `int`。数据库 UUID 暂时通过 `rawId.hashCode` 转为整数，未来接活动详情、报名和编辑时应改为保留真实 UUID 字符串。
2. 活动创建当前由多个数据库命令组成，不是完整事务；地点写入成功而活动写入失败时可能留下孤立地点。应改成单事务。
3. API 的通用异常处理中主要处理业务异常和唯一约束；开发环境曾出现未处理 PostgreSQL Check Constraint 返回开发错误页。应补统一数据库/未知异常 JSON 响应，生产环境禁止泄漏堆栈或请求头。
4. Admin 使用静态 `X-Admin-Key`，没有 RBAC、管理员登录或二次验证。
5. App 自定义 Token 方案不是正式 JWT/refresh-token 体系。
6. `main.dart` 和 `Admin App.jsx` 体积过大，但功能闭环优先于纯重构。
7. 旧数据库可能与迁移初始定义存在差异，新增迁移要保持幂等并在真实本地数据库验证。
8. 当前工作目录过去执行 `git status` 曾提示不是 Git 仓库；进行 Git 操作前先确认 `.git` 实际状态，不要假设可提交或回滚。

## 9. 下一步推荐顺序

当前最优先不是 UI 美化，而是完成真实活动闭环：

1. 将 `EventItem.id` 改为真实 UUID 字符串。
2. App 活动详情接入 `GET /events/{id}`。
3. 接入真实报名和退出 API。
4. 报名确认弹窗加入：
   - 平台不支持支付、转账或担保；
   - 不提前向陌生人转账；
   - 注意线下人身和财产安全；
   - 明确预计人均费用。
5. 接组织者报名审核、名额和候补状态。
6. “我的活动”进入真实详情，并提供编辑、取消、审核入口。
7. 接真实通知和活动群聊。
8. 再补举报、屏蔽、评价、安全会面。
9. 核心流程稳定后统一设计系统和界面美化。

核心验收链路：

```text
注册/登录
→ 浏览数据库活动
→ 查看真实活动详情
→ 阅读费用与安全提示
→ 报名（直接通过或等待审核）
→ 名额正确变化
→ 获批后查看准确集合点
→ 我的活动可追踪状态
→ 组织者审核/取消
→ 通知与群聊
```

## 10. API 约定

API 基础地址：

```text
http://localhost:8080/api/v1
```

统一成功响应大致为：

```json
{
  "data": {},
  "meta": null,
  "error": null,
  "traceId": "..."
}
```

统一错误响应大致为：

```json
{
  "data": null,
  "meta": null,
  "error": {
    "code": "error_code",
    "message": "用户可读信息"
  },
  "traceId": "..."
}
```

用户请求使用：

```text
Authorization: Bearer <token>
```

本地开发 API 也支持 `X-User-Id`，但 App 正常流程使用 Bearer Token。

Admin 请求使用：

```text
X-Admin-Key: muda-admin-local
```

## 11. 验证命令

Flutter：

```bash
cd app
/Users/dahai/flutter/bin/dart format lib test
/Users/dahai/flutter/bin/flutter analyze
/Users/dahai/flutter/bin/flutter test test/widget_test.dart
```

已知：`register_snapshot_test.dart` 的 Golden 图片曾与当前渲染环境不一致。不要未经视觉确认直接更新 Golden；先检查 `app/test/failures/`。

REST API：

```bash
cd restapi
/Users/dahai/.dotnet-sdk/dotnet build --no-restore
```

目前没有独立的 API 自动化测试项目，重要数据流程需要补集成测试。

Admin：

```bash
cd admin
npm run lint
npm run build
```

如果 shell 找不到 `npm`，当前机器曾使用：

```bash
PATH=/Users/dahai/.nvm/versions/node/v24.18.0/bin:$PATH npm run build
```

接口快速检查：

```bash
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/regions
curl 'http://localhost:8080/api/v1/events?limit=20'
```

## 12. 现有规划文档的使用方式

- `MVP.md`：产品 MVP 范围和规则。
- `FIRST_RELEASE_FLOWS.md`：较完整的首发流程与缺口分析。
- `app/README.md`、`restapi/README.md`、`admin/README.md`：各端启动与局部说明。

注意：这些文档中的“已有/缺失/部分”状态可能早于最近的地区、活动发布、活动列表和“我的活动”联动。
判断当前实现时，以源码、本文件和实际接口验证为准。

## 13. 给新 Session 的工作原则

1. 先确认用户要求的是“解释/诊断”还是“直接修改”。
2. 修改前检查相关 App、API、数据库和 Admin，避免只改一端。
3. 每完成一个功能，至少验证：编译、静态检查、真实 API 响应和跨端可见性。
4. 数据库结构变化必须新增编号迁移，不要只修改旧迁移。
5. 不要重新引入 App 写死的分类、地区或活动数据。
6. 不要把预计活动费用描述成平台收费或在线支付。
7. 不要向未获批用户泄露准确集合点。
8. 新活动当前应立即公开；管理员审核能力只预留，除非用户明确改变策略。
9. 未实现入口要有清晰提示，但不能把说明页描述成已完成业务功能。
10. 完成后更新本文件中的“真实联动状态、已知技术债和下一步”。

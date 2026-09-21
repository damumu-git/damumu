# 慕搭 REST API

ASP.NET Core 10 + PostgreSQL/PostGIS API，覆盖用户、活动、报名候补、聊天、
安全会面、评价、举报治理、通知、配置与管理员运营接口。

开发环境默认通过 Tailscale 连接 `100.66.109.44:5432/damumu`。真实密码保存在本机
.NET User Secrets，不能写入 `appsettings.json`：

```powershell
dotnet user-secrets set "ConnectionStrings:Muda" "Host=100.66.109.44;Port=5432;Database=damumu;Username=postgres;Password=你的密码;SSL Mode=Disable" --project ./restapi/Muda.Api.csproj
```

Admin 不直接连接 PostgreSQL；它通过 `http://localhost:8080/api/v1` 使用同一个 REST API，
所以 REST API 的连接配置同时决定用户 App 和 Admin 读取的数据库。

## 可选：独立的本地 Docker 环境

以下 `muda` 数据库和容器名是隔离的本地示例，不是当前 Tailscale `damumu` 数据库。运行前先用 `docker ps` 核对实际容器。

数据库容器已运行在宿主机 `127.0.0.1:5432` 时：

```bash
docker build -t muda-api ./restapi
docker run --rm -p 8080:8080 \
  -e 'ConnectionStrings__Muda=Host=host.docker.internal;Port=5432;Database=muda;Username=muda;Password=你的本地密码;SSL Mode=Disable' \
  -e 'Admin__ApiKey=muda-admin-local' \
  muda-api
```

健康检查：

```bash
curl http://localhost:8080/api/v1/health
```

OpenAPI：

```text
http://localhost:8080/openapi/v1.json
```

## 初始化本地数据库

API 使用 PostGIS 地理类型，不能使用普通的 `postgres` 镜像。Docker Desktop 启动后创建数据库：

```bash
docker run -d \
  --name muda-postgres \
  -e POSTGRES_USER=muda \
  -e POSTGRES_PASSWORD=muda2026 \
  -e POSTGRES_DB=muda \
  -p 5432:5432 \
  -v muda-postgres-data:/var/lib/postgresql/data \
  postgis/postgis:16-3.4
```

按编号执行全部迁移：

```bash
for migration in Migrations/*.sql; do
  docker exec -i muda-postgres psql -v ON_ERROR_STOP=1 -U muda -d muda < "$migration"
done
```

验证基础结构：

```bash
docker exec muda-postgres psql -U muda -d muda -c '\\dt'
```

## Tailscale PostgreSQL 集成测试

当前测试通过 Tailscale 连接 `100.66.109.44:5432/damumu`，默认用户为 `postgres`。
在 Windows PowerShell 中先设置数据库密码环境变量，再从仓库根目录执行：

```powershell
$env:DAMUMU_POSTGRES_PASSWORD = '你的密码'
./scripts/test-tailscale-postgres.ps1
```

默认流程只读取现有业务数据，并在事务临时表中执行 SQL 边界测试，不持久化测试数据。
需要显式应用迁移时执行：

```powershell
./scripts/test-tailscale-postgres.ps1 -ApplyMigrations
```

脚本只从 `DAMUMU_POSTGRES_PASSWORD` 读取密码，不再交互询问。不要把密码写入 Git 配置或受版本控制的脚本。

## Windows PowerShell 开发启动

`dev.ps1` 优先使用完整的 `ConnectionStrings__Muda` 环境变量；未提供时，根据
`DAMUMU_POSTGRES_HOST`、`DAMUMU_POSTGRES_DATABASE`、
`DAMUMU_POSTGRES_USERNAME` 和 `DAMUMU_POSTGRES_PASSWORD` 生成连接字符串。
密码缺失时脚本直接退出，不再交互询问：

```powershell
$env:DAMUMU_POSTGRES_PASSWORD = '你的密码'
./dev.ps1 --services
# 或同时启动 Flutter Web：
./dev.ps1 -d chrome --web-port 3000
```

启动脚本会把 API 和 Admin 的 PID 记录到 Git 忽略的 `.dev-logs/dev-processes.json`。
需要从另一个 PowerShell 窗口停止，或原启动窗口已经关闭时，执行：

```powershell
./stop-dev.ps1
```

正常按 `Ctrl+C` 时 `dev.ps1` 也会清理子进程。直接关闭 PowerShell 窗口无法保证执行
脚本的 `finally` 清理，因此应在关闭窗口前运行停止脚本；即使窗口已关闭，PID 文件仍可用于停止进程树。

如果希望新开的 PowerShell 窗口也能读取，可以将密码保存为当前 Windows 用户的环境变量，
随后重新打开终端：

```powershell
[Environment]::SetEnvironmentVariable('DAMUMU_POSTGRES_PASSWORD', '你的密码', 'User')
```

## Bash 开发启动

`./dev.sh -d chrome --web-port 3000` 启动时不再询问密码；默认读取仓库根目录的
`dev.local.sh`，其中设置 `DAMUMU_POSTGRES_PASSWORD='你的密码'`。
该文件已被 Git 忽略，只在本机保存；换机器后需要重新配置。
已有的同名环境变量优先。未配置密码时脚本会报错退出。

## 用户认证与头像

## 多用户互动演示数据

API 启动并应用全部迁移后，可以通过真实注册、活动发布、报名审批和聊天接口生成一组
本地演示数据：

```powershell
./scripts/seed-demo-interactions.ps1 -UserCount 20
```

脚本创建约 20 个带 `[DEMO]` 标识的活动；每个活动有一条获批申请、一条被拒申请和
一条留给界面手动处理的待审核申请，并包含活动群聊消息和相邻账号私信。账号清单保存在 Git 忽略的
`.dev-data/demo-interactions-<时间>.json`，用于在单设备上切换登录。

单设备并行测试时，先用 `./dev.ps1 --services` 启动 API 和 Admin，然后在不同终端以
不同 Web 端口启动 Flutter。不同端口具有隔离的浏览器本地存储，可以同时保持不同账号登录：

```powershell
cd app
flutter run -d chrome --web-port 3000 --dart-define=API_BASE_URL=http://localhost:8080/api/v1
flutter run -d edge --web-port 3001 --dart-define=API_BASE_URL=http://localhost:8080/api/v1
```

从清单选择两个账号分别登录。批次中账号 N 发布活动 N，账号 N+1 的申请已通过并进入群聊，
账号 N+2 的申请被拒且不在群聊，账号 N+3 保持待审核，可直接验证审批、通知、群聊成员、未读气泡和私信。

## 实时消息和 Firebase 推送

登录后的 App 会连接 `/api/v1/realtime`。WebSocket 的第一条消息携带登录令牌完成认证，后续
只接收消息和通知的同步事件；聊天正文、历史记录和未读状态仍通过 REST API 与 PostgreSQL
读写。服务端重启或网络切换后客户端自动重连，并重新读取权威数据。

FCM 未配置时自动停用，不影响 REST、站内通知或 WebSocket。启用服务端发送需要创建 Firebase
项目、启用 Cloud Messaging API，并把服务账号 JSON 保存在仓库外。PowerShell 示例：

```powershell
$env:Firebase__ProjectId = '你的 Firebase Project ID'
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\安全目录\firebase-service-account.json'
./dev.ps1 --services
```

Flutter 构建需要使用对应平台 Firebase App 的公开配置。Web 还需要 VAPID 公钥：

```powershell
flutter run -d chrome --web-port 3000 `
  --dart-define=API_BASE_URL=http://localhost:8080/api/v1 `
  --dart-define=FIREBASE_API_KEY=... `
  --dart-define=FIREBASE_APP_ID=... `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_PROJECT_ID=... `
  --dart-define=FIREBASE_AUTH_DOMAIN=... `
  --dart-define=FIREBASE_STORAGE_BUCKET=... `
  --dart-define=FIREBASE_WEB_VAPID_KEY=...
```

Android、iOS 和 Web 的 `FIREBASE_APP_ID` 通常不同，构建各平台时使用该平台 App 的值。
iOS 还须在 Xcode 启用 Push Notifications、Background fetch 和 Remote notifications；Web
后台通知须按 Firebase 文档提供 `web/firebase-messaging-sw.js`。服务账号 JSON、VAPID 私钥及
其他秘密不得写进 Git；上述客户端 Firebase 配置和 VAPID 公钥不是服务端凭据。

已有数据库升级时先核对已应用的迁移，再按编号执行缺失的 `Migrations/*.sql`；不要只执行 `002` 和 `003`。当前迁移文件到 `015`。测试脚本默认不会持久应用迁移，显式传入 `-ApplyMigrations` 才会执行。

正式用户接口包括：

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/me`
- `PUT /api/v1/me/avatar/system`
- `POST /api/v1/me/avatar`（`multipart/form-data`，字段名 `avatar`）
- `GET /api/v1/system-avatars?locale=zh|en|ko`
- `GET /api/v1/admin/system-avatars`
- `POST /api/v1/admin/system-avatars`（后台上传）
- `PATCH /api/v1/admin/system-avatars/{id}`（名称、排序、启停）

头像统一为 1:1、512×512 JPEG，文件上限 1 MB。上传头像由客户端裁剪和
重新编码，API 会再次检查 MIME、体积与 JPEG 文件签名。系统头像的中、英、韩名称、
排序和启停状态存储在 `system_avatar` 表，通过运营后台的“系统头像”页面管理。

活动分类采用三级结构：大分类用于一级导航，中分类用于主题聚合，小分类用于
活动发布时的最终选择。`004_category_hierarchy.sql` 会创建 6 个大分类、18 个
中分类和完整的小分类目录，并把旧分类无损归入新目录。

部署生产环境前必须通过
环境变量 `Auth__TokenKey` 设置至少 32 位的随机密钥，并将 `uploads/` 挂载到持久卷
或替换为对象存储。

## 本地开发身份

用户接口在开发阶段通过请求头传递：

```text
X-User-Id: 用户 UUID
```

管理员接口通过：

```text
X-Admin-Key: muda-admin-local
```

生产环境必须替换为 Apple/Google/手机号认证、短时 JWT、轮换 refresh token，
并把管理员认证接入 RBAC 与二次验证。


## APP 活动列表 Cursor 分页

```http
GET /api/v1/activities?limit=20
GET /api/v1/activities?limit=20&cursor=<上一页 data.nextCursor>
```

响应沿用项目 envelope：

```json
{
  "data": { "items": [], "nextCursor": null, "hasMore": false },
  "meta": null,
  "error": null,
  "traceId": "..."
}
```

`limit` 默认 20、范围 1–100（越界夹取）。固定按 `event.created_at DESC, event.id DESC`
排序；UUID 即 activity_id。可选过滤参数沿用 `city`、`district`、`categoryId`、`q`、
`from`、`to`、`latitude`、`longitude`、`radiusMeters`。分页期间保持参数相同，改变过滤条件时不传 cursor 重新开始。
游标为版本化 Base64URL 编码位置，不是秘密或鉴权令牌；非法/过长/未知版本游标返回
HTTP 400，`error.code=invalid_cursor`。活动列表永不返回精确集合点。

部署时按迁移顺序执行 `Migrations/010_activity_cursor_index.sql`、
`Migrations/011_illustrated_other_category.sql`、
`Migrations/012_custom_category_leaves.sql` 与
`Migrations/013_notifications_event_chat.sql` 与
`Migrations/014_event_chat_organizer_membership.sql`；`010` 增加公开活动创建时间/UUID
部分索引，`011` 增加分类图标键与活动自定义小分类列，`012` 为各一级分类增加“其它”叶子及标识。
升级 API 前必须先应用 `011`、`012`、`013` 和 `014`，否则活动、分类或活动群聊行为不完整。
活动封面上传接口 `POST /api/v1/events/covers` 接受登录用户的一张 1280×960 JPEG，最大 2 MB；返回媒体 ID 后在 `POST /events` 传入 `coverMediaId`。文件存于 API 本地 `uploads/events`。
原 `/events` 及后台分页接口保持兼容。

在仓库根目录验证（测试输出隔离，避免锁住正在运行的 API）：

```powershell
dotnet build restapi.tests/Muda.Api.PaginationTests.csproj -o restapi/.codex-build/cursor-tests
# 游标编解码测试，无数据库依赖：
dotnet restapi/.codex-build/cursor-tests/Muda.Api.PaginationTests.dll
# 已启动新版本 API 后，增加真实 API 只读检查：
dotnet restapi/.codex-build/cursor-tests/Muda.Api.PaginationTests.dll http://localhost:8080/
# 可选：临时表 SQL 集成测试（需要配置可连接的 PostgreSQL 且至少存在一个活动种子）：
dotnet restapi/.codex-build/cursor-tests/Muda.Api.PaginationTests.dll http://localhost:8080/ restapi/appsettings.json
```

临时表测试执行与 API 相同的 SQL，覆盖相同时间戳 UUID 顺序、头部新增、边界删除、
`limit+1`、末页和空页；不修改持久业务表，事务最后回滚。

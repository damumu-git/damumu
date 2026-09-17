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

## 使用 Docker 启动

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
在 Windows PowerShell 中从仓库根目录执行，脚本会隐藏输入数据库密码：

```powershell
./scripts/test-tailscale-postgres.ps1
```

默认流程只读取现有业务数据，并在事务临时表中执行 SQL 边界测试，不持久化测试数据。
需要显式应用迁移时执行：

```powershell
./scripts/test-tailscale-postgres.ps1 -ApplyMigrations
```

非交互执行时可提前设置仅存在于当前终端进程的
`DAMUMU_POSTGRES_PASSWORD`。不要把密码写入 Git 配置或受版本控制的脚本。

## Bash 开发启动

`./dev.sh -d chrome --web-port 3000` 启动时不再询问密码；默认读取仓库根目录的
`dev.local.sh`，其中设置 `DAMUMU_POSTGRES_PASSWORD='你的密码'`。
该文件已被 Git 忽略，只在本机保存；换机器后需要重新配置。
已有的同名环境变量优先。未配置密码时脚本会报错退出。

## 用户认证与头像

从旧版基础数据库升级时执行：

```bash
psql "$DAMUMU_DATABASE_URL" -f Migrations/002_user_auth.sql
psql "$DAMUMU_DATABASE_URL" -f Migrations/003_system_avatar.sql
```

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

部署时按迁移顺序执行 `Migrations/010_activity_cursor_index.sql`，增加公开活动创建时间/UUID
部分索引；功能查询不依赖新增列。原 `/events` 及后台分页接口保持兼容。

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

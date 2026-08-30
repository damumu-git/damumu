# 慕搭 REST API

ASP.NET Core 10 + PostgreSQL/PostGIS API，覆盖用户、活动、报名候补、聊天、
安全会面、评价、举报治理、通知、配置与管理员运营接口。

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

## 用户认证与头像

从旧版基础数据库升级时执行：

```bash
psql "$MUDA_DATABASE_URL" -f Migrations/002_user_auth.sql
psql "$MUDA_DATABASE_URL" -f Migrations/003_system_avatar.sql
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

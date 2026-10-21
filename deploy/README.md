# Lightsail 单机测试部署

本目录用于 Ubuntu 24.04 Lightsail 单机测试环境。公网只访问宿主机 Nginx；
产品主页、API 和 Admin 容器分别绑定 `127.0.0.1:8081`、`8080`、`8082`。
Nginx 按域名把 `www.damumu.com`、`admin.damumu.com`、`api.damumu.com`
分别转发给三个服务，`damumu.com` 跳转到 `www.damumu.com`。Flutter `app/`
只构建 Android/iOS 客户端，不部署 Flutter Web。

## Ubuntu 目录与图片访问

```text
/opt/damumu/repo/              Git 源码与部署脚本
/srv/damumu/uploads/           持久化图片，独立于源码和容器
  system-avatars/             系统头像
  avatars/                    用户头像
  events/                     活动原图与缩略图
  messages/                   聊天原图与缩略图
/var/backups/damumu/           备份归档，不对公网提供
/etc/nginx/                   宿主机 HTTPS 与域名路由配置
```

只有 API 容器绑定 `/srv/damumu/uploads` 到容器内的
`/var/lib/damumu/uploads`；Admin 容器不挂载图片目录。上传经过 API 校验，浏览器和
App 使用完整 URL，如 `https://api.damumu.com/uploads/system-avatars/green-sprout.jpg`。
宿主机 Nginx 将 `/uploads/` 转发给 API 静态文件服务，响应不暴露磁盘路径。

`Media__RootPath` 配置磁盘位置，`MEDIA_PUBLIC_BASE_URL` 配置公开 URL 前缀。
数据库保留相对存储键与历史 `/uploads/...` 引用，API 在响应边界统一转换为完整 URL，
无需数据库迁移。未来调整媒体域名前，须先确保新地址能读取全部既有文件。

预设头像随发布产物保存在 `/app/preset-avatars`，启动时只补齐缺少的文件，不覆盖
已有头像，也不会被上传目录挂载遮住。用户上传不进入 Git；更新图片应产生新 URL。

首次部署前准备目录：

```bash
sudo install -d -m 755 /srv/damumu /srv/damumu/uploads
sudo install -d -m 700 /var/backups/damumu
```

当前 API 镜像仍以 root 运行；以后改为非 root 时必须同步配置目录属主，不能使用
`chmod 777` 代替。绑定目录缺失时 Compose 会失败，不会自动创建空目录掩盖迁移遗漏。

## 从旧 Docker 图片卷迁移（已有服务器必须执行一次）

先创建 Lightsail 手动快照，并确认数据库独立备份。拉取新配置后，**不要直接执行
`docker compose up`**，先在服务器运行：

```bash
cd /opt/damumu/repo
bash deploy/migrate-uploads.sh
```

脚本从现有 API 容器发现 `/app/uploads` 的实际命名卷，检查目标为空，停止 API 写入，
将原卷归档到 `/var/backups/damumu/uploads-时间戳.tar.gz`，复制并比较全部文件。
成功后记录迁移标记；保留原卷，API 保持停止，然后运行 `damumu-deploy`
（首次受管部署仍需按下文核对迁移并使用 `--migrations-applied`）。其他服务不停止。
存在旧 API 卷但没有成功迁移标记时，部署脚本会拒绝替换 API 容器。

脚本先检查迁移辅助镜像和所需工具，再停止 API。如果旧容器引用的镜像已被清理，
会使用官方 `debian:bookworm-slim`，本地不存在时先下载；下载失败不会停止仍在运行的 API。

失败时不要删除卷或清空目标目录；先检查归档和已复制文件。如果需要恢复旧服务，
可执行 `docker start <原API容器ID>`，它仍挂载原卷；恢复写入后必须重新核对和迁移
增量，不能沿用旧迁移结果。脚本不会自动合并非空目标目录。

部署后验证头像、一张已有活动/聊天图片，并通过后台上传新头像：

```bash
curl --fail --output /dev/null https://api.damumu.com/uploads/system-avatars/green-sprout.jpg
docker compose --env-file deploy/.env -f deploy/compose.yaml exec api \
  ls -l /var/lib/damumu/uploads/system-avatars
```

日常图片操作通过 App/后台完成。备份须覆盖 `/srv/damumu/uploads` 和对应数据库；
暂停写入或使用一致性快照后归档，将备份复制到其他主机或对象存储，并定期验证恢复。
只有本机副本无法应对实例丢失。`git pull` 和重建容器不会备份或同步用户上传。

## 前置条件

- Docker Engine 与 Compose 插件已安装。
- 宿主机 Nginx、Certbot 和 `apache2-utils` 已安装；公网只开放 80/443，
  SSH 由 Lightsail Browser SSH 或可信来源 IP 限制。
- PostgreSQL 18/PostGIS 运行在 Lightsail 宿主机。API 使用固定的
  `172.30.0.0/24` Compose 内网访问；不要把 PostgreSQL 5432 暴露到公网。
- 已按顺序应用 `restapi/Migrations/*.sql`。

## DNS 与 Lightsail 防火墙

下列四条 DNS A 记录必须指向绑定到实例的 Lightsail 静态 IP：

```text
damumu.com        -> 43.201.237.29
www.damumu.com    -> 43.201.237.29
admin.damumu.com  -> 43.201.237.29
api.damumu.com    -> 43.201.237.29
```

Lightsail IPv4/IPv6 防火墙只对公网开放 TCP 80 和 443。不得开放 8080、8081、
8082 或 5432；App 通过 `https://api.damumu.com/api/v1` 访问 API，而不是直接访问
容器端口。

## 宿主机 PostgreSQL

PostgreSQL 需要监听 Docker 网桥，但只接受应用数据库账号从固定 Compose 网段连接。
在 `/etc/postgresql/18/main/postgresql.conf` 设置：

```conf
listen_addresses = '*'
password_encryption = 'scram-sha-256'
```

在 `/etc/postgresql/18/main/pg_hba.conf` 添加：

```conf
host    damumu    damumu_app    172.30.0.0/24    scram-sha-256
```

然后执行：

```bash
sudo ufw allow in from 172.30.0.0/24 to any port 5432 proto tcp comment 'DAMUMU Docker to PostgreSQL'
sudo systemctl restart postgresql
```

Lightsail 公网防火墙不得添加 5432。`pg_hba.conf` 不得添加 `0.0.0.0/0`，UFW
不得允许任意来源访问 5432。

## 首次部署

```bash
sudo apt-get update
sudo apt-get install -y nginx certbot apache2-utils
sudo mkdir -p /opt/damumu
sudo chown "$USER":"$USER" /opt/damumu
git clone --branch main \
  https://github.com/damumu-git/damumu.git /opt/damumu/repo
cd /opt/damumu/repo

cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

编辑 `deploy/.env`，至少配置 `DATABASE_CONNECTION`、`AUTH_TOKEN_KEY` 和
`ADMIN_API_KEY`。生成两个不同的随机密钥：

```bash
openssl rand -hex 32
openssl rand -hex 32
```

不要把 `.env`、Firebase 服务账号或数据库密码提交到 Git。

为测试阶段 Admin 设置额外的 Basic Auth：

```bash
sudo htpasswd -c /etc/nginx/.htpasswd-damumu-admin damumu-admin
sudo chmod 640 /etc/nginx/.htpasswd-damumu-admin
sudo chown root:www-data /etc/nginx/.htpasswd-damumu-admin
```

首次签发证书前安装 HTTP 引导配置，并构建三个容器：

```bash
sudo mkdir -p /var/www/certbot
sudo cp deploy/nginx/damumu-http.conf /etc/nginx/sites-available/damumu
sudo ln -sfn /etc/nginx/sites-available/damumu /etc/nginx/sites-enabled/damumu
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

sudo install -d -m 755 /srv/damumu /srv/damumu/uploads
sudo install -d -m 700 /var/backups/damumu
docker compose --env-file deploy/.env -f deploy/compose.yaml build site api admin
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d site api admin
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
```

先确认四个域名已经能从公网解析到本机，再签发包含全部域名的证书。把下面的
`YOUR_EMAIL` 替换为 ACME 注册使用的真实邮箱；证书续期依赖 Certbot 定时任务，
不能依赖到期提醒邮件：

```bash
sudo certbot certonly \
  --webroot --webroot-path /var/www/certbot \
  --cert-name damumu.com \
  --email YOUR_EMAIL --agree-tos --no-eff-email \
  -d damumu.com \
  -d www.damumu.com \
  -d admin.damumu.com \
  -d api.damumu.com

sudo cp deploy/nginx/damumu.conf /etc/nginx/sites-available/damumu
sudo install -m 755 deploy/nginx/reload-nginx.sh \
  /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
sudo nginx -t
sudo systemctl reload nginx
sudo certbot renew --dry-run
```

## 验证

```bash
curl --fail http://127.0.0.1:8081/healthz
curl --fail http://127.0.0.1:8080/api/v1/health
curl --fail http://127.0.0.1:8082/healthz
curl --fail https://www.damumu.com/healthz
curl --fail https://api.damumu.com/api/v1/health
curl --fail -u damumu-admin https://admin.damumu.com/healthz
```

`www.damumu.com` 提供独立产品主页，不提供 Flutter Web App。Admin 位于
`admin.damumu.com`，整个域名先通过 Nginx Basic Auth；Admin 浏览器使用同源
`/api/v1` 访问管理 API。公共 `api.damumu.com` 拒绝 `/api/v1/admin/`，Android/iOS
App 使用 `https://api.damumu.com/api/v1` 及同源 WebSocket 地址。发布 App 时传入：

```bash
flutter build apk \
  --dart-define=API_BASE_URL=https://api.damumu.com/api/v1
```

## 更新与回滚

更新前先创建 Lightsail 快照。首次安装快捷命令：

```bash
cd /opt/damumu/repo
git switch main
git pull --ff-only origin main
sudo ln -sfn /opt/damumu/repo/deploy/deploy.sh /usr/local/bin/damumu-deploy
```

以后每次 GitHub Pull Request 合并进 `main` 后，只需在服务器执行：

```bash
damumu-deploy
```

第一次运行时还没有“上次成功部署版本”记录，脚本不会猜测数据库状态，而会在更新
源码后停止并显示仓库中的最新迁移编号。备份数据库并核对该编号以前的必要迁移均已
应用后，使用 `damumu-deploy --migrations-applied` 完成首次受管部署。此后直接运行
`damumu-deploy` 即可；只有检测到新迁移时才需要再次确认。

该命令会防止并发部署，要求服务器停留在干净的 `main` 分支，从
`origin/main` 快进更新，校验 `deploy/.env` 和 Compose 配置，构建并启动三个
容器，等待 Docker 健康检查，通过回环端口验证三个服务，按需更新并校验 Nginx，
再验证公网 HTTPS。全部成功后才清理悬空镜像；任一步失败都会打印容器状态和最近
日志。它不会删除 Docker 卷，也不会自动修改数据库。

脚本会在 Git 元数据中记录上次成功部署的提交。如果本次更新含有新的
`restapi/Migrations/*.sql`，命令只更新源码，保持现有容器继续运行，然后停止并列出
迁移文件。先创建数据库备份，审查并按编号应用这些迁移；确认全部成功后再执行：

```bash
damumu-deploy --migrations-applied
```

常用诊断选项：

```bash
damumu-deploy --skip-public-checks  # DNS/证书尚未就绪时跳过公网检查
damumu-deploy --skip-nginx          # 本次明确不更新宿主机 Nginx
damumu-deploy --no-prune            # 成功后保留悬空 Docker 镜像
```

需要回滚时，不要在服务器上 `reset --hard` 或直接修改文件。应在 GitHub 对导致问题的
Pull Request 创建 revert、合并回 `main`，再运行 `damumu-deploy`。如果版本包含数据库
迁移，必须先确认迁移是否向后兼容；数据库回滚应使用事先创建的备份或经过审查的反向
迁移，不能依靠应用脚本自动处理。

图片现存于 `/srv/damumu/uploads`，重建容器不会删除。旧命名卷应在迁移及恢复验证
完成后再人工清理，不要执行 `docker compose down -v`。数据库仍需独立备份。自动 Lightsail 快照会备份实例磁盘，
但删除实例时自动快照也会被删除，重要版本应另存手动快照。

## 当前安全边界

- 这是测试部署。Admin 静态 API Key 会编译进 Admin 前端，因此必须保留 Basic Auth。
- Admin 前端通过 `admin.damumu.com/api/v1` 同源访问管理 API；公共 API 域名拒绝
  `/api/v1/admin/`，不得改成从浏览器跨域直连公共 Admin API。
- 正式上线前需实现管理员登录、短时 Cookie、RBAC 和二次验证，移除浏览器内静态 Key。
- Firebase 服务账号必须作为服务器外部秘密挂载；本编排在未配置时保持 FCM 关闭。

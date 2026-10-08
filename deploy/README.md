# Lightsail 单机测试部署

本目录用于 Ubuntu 24.04 Lightsail 单机测试环境。公网只访问宿主机 Nginx；
产品主页、API 和 Admin 容器分别绑定 `127.0.0.1:8081`、`8080`、`8082`。
Nginx 按域名把 `www.damumu.com`、`admin.damumu.com`、`api.damumu.com`
分别转发给三个服务，`damumu.com` 跳转到 `www.damumu.com`。Flutter `app/`
只构建 Android/iOS 客户端，不部署 Flutter Web。

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

更新前先创建 Lightsail 快照。然后：

```bash
cd /opt/damumu/repo
git pull --ff-only
docker compose --env-file deploy/.env -f deploy/compose.yaml build site api admin
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d site api admin --remove-orphans
docker image prune -f
sudo cp deploy/nginx/damumu.conf /etc/nginx/sites-available/damumu
sudo nginx -t
sudo systemctl reload nginx
```

`damumu_uploads` 是 Docker 命名卷，重建容器不会删除；不要执行
`docker compose down -v`。数据库仍需独立备份。自动 Lightsail 快照会备份实例磁盘，
但删除实例时自动快照也会被删除，重要版本应另存手动快照。

## 当前安全边界

- 这是测试部署。Admin 静态 API Key 会编译进 Admin 前端，因此必须保留 Basic Auth。
- Admin 前端通过 `admin.damumu.com/api/v1` 同源访问管理 API；公共 API 域名拒绝
  `/api/v1/admin/`，不得改成从浏览器跨域直连公共 Admin API。
- 正式上线前需实现管理员登录、短时 Cookie、RBAC 和二次验证，移除浏览器内静态 Key。
- Firebase 服务账号必须作为服务器外部秘密挂载；本编排在未配置时保持 FCM 关闭。

# Lightsail 单机测试部署

本目录用于 Ubuntu 24.04 Lightsail 单机测试环境。公网只访问宿主机 Nginx；
产品主页、API 和 Admin 容器分别绑定 `127.0.0.1:8081`、`8080`、`8082`。
Flutter `app/` 只构建 Android/iOS 客户端；域名根路径发布 `website/dist` 的独立静态产品主页。

## 前置条件

- Docker Engine 与 Compose 插件已安装。
- 宿主机 Nginx 已安装，只开放 80/443；SSH 由 Lightsail Browser SSH 限制。
- PostgreSQL 18/PostGIS 运行在 Lightsail 宿主机。API 使用固定的
  `172.30.0.0/24` Compose 内网访问；不要把 PostgreSQL 5432 暴露到公网。
- 已按顺序应用 `restapi/Migrations/*.sql`。

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
sudo apt-get install -y apache2-utils
sudo mkdir -p /opt/damumu
sudo chown "$USER":"$USER" /opt/damumu
git clone --branch main \
  https://github.com/damumu-git/damumu.git /opt/damumu/repo
cd /opt/damumu/repo

cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

编辑 `deploy/.env`，至少配置 `PUBLIC_ORIGIN`、`DATABASE_CONNECTION`、
`AUTH_TOKEN_KEY` 和 `ADMIN_API_KEY`。生成两个不同的随机密钥：

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

安装宿主机 Nginx 配置并构建：

```bash
sudo cp deploy/nginx/damumu.conf /etc/nginx/sites-available/damumu
sudo ln -sfn /etc/nginx/sites-available/damumu /etc/nginx/sites-enabled/damumu
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

docker compose --env-file deploy/.env -f deploy/compose.yaml build site api admin
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d site api admin
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
```

## 验证

```bash
curl --fail http://127.0.0.1:8081/healthz
curl --fail http://127.0.0.1:8080/api/v1/health
curl --fail http://127.0.0.1:8082/healthz
curl --fail http://127.0.0.1/api/v1/health
curl --fail http://127.0.0.1/healthz
```

域名根路径提供独立产品主页，不提供 Flutter Web App。Admin 位于 `PUBLIC_ORIGIN/admin/`，
先通过 Nginx Basic Auth，再由现有 Admin API Key 调用管理 API；Android/iOS App 使用
`PUBLIC_ORIGIN/api/v1` 和同源 WebSocket 地址。

## 更新与回滚

更新前先创建 Lightsail 快照。然后：

```bash
cd /opt/damumu/repo
git pull --ff-only
docker compose --env-file deploy/.env -f deploy/compose.yaml build site api admin
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d site api admin --remove-orphans
docker image prune -f
```

`damumu_uploads` 是 Docker 命名卷，重建容器不会删除；不要执行
`docker compose down -v`。数据库仍需独立备份。自动 Lightsail 快照会备份实例磁盘，
但删除实例时自动快照也会被删除，重要版本应另存手动快照。

## 当前安全边界

- 这是测试部署。Admin 静态 API Key 会编译进 Admin 前端，因此必须保留 Basic Auth。
- 正式上线前需实现管理员登录、短时 Cookie、RBAC 和二次验证，移除浏览器内静态 Key。
- 正式域名确定后，把 `PUBLIC_ORIGIN` 改为 HTTPS 地址并重新构建 Web/Admin。
- Firebase 服务账号必须作为服务器外部秘密挂载；本编排在未配置时保持 FCM 关闭。

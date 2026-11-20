# 安全升级与发布

本次升级包含 045_security_sessions.sql，适用于 API、网站、Admin 和重新构建的 App。

## 发布前的影响

- 旧登录凭据失效，用户需要重新登录。旧 App 应先更新，新版自动续领 15 分钟访问令牌，固定 30 天后重新登录。
- 网站通过同源 API 和 HttpOnly、Secure、SameSite Cookie 登录。记住登录保存七天，未勾选时使用浏览器会话 Cookie，服务器上限同为七天。
- Admin 使用独立账号、密码及身份验证器六位验证码。原 ADMIN_API_KEY 和 VITE_ADMIN_KEY 不再参与认证。
- 迁移删除退役的安全联系人、会面及关联警报。保留空旧表供现有保留期清理函数使用。恢复这些数据需要发布前备份。
- API 以 UID/GID 1654:1654 运行，根文件系统只读，仅媒体、密钥及临时目录可写，媒体所有权须在发布前调整。
- /srv/damumu/keys 必须持久保存并受限备份。它保护 OAuth 交接及管理员验证器密钥，不可清空后继续使用原有管理员数据。

## 首次升级

合并完成后，在服务器执行：

~~~bash
cd /opt/damumu/repo
git pull --ff-only origin main
sudo bash deploy/prepare-security.sh
chmod 600 deploy/.env
~~~

核对 .env 中数据库和 Google/Kakao 配置。此前出现在截图或对话中的密钥需要轮换，其中数据库密码必须同时更新数据库角色和连接配置。保留提供方 Client ID，按提供方控制台轮换对应 Secret。

AUTH_TOKEN_KEY 应独立随机生成，至少 32 字符。下面命令生成新值并直接写入文件，不输出密钥：

~~~bash
python3 - <<'PY'
from pathlib import Path
import os
import re
import secrets

path = Path("deploy/.env")
text = path.read_text()
line = "AUTH_TOKEN_KEY=" + secrets.token_hex(32)
text = re.sub(r"^AUTH_TOKEN_KEY=.*$", line, text, flags=re.MULTILINE) if re.search(
    r"^AUTH_TOKEN_KEY=", text, re.MULTILINE
) else text.rstrip() + "\n" + line + "\n"
temporary = path.with_name(".env.security.tmp")
descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "w") as output:
    output.write(text)
os.replace(temporary, path)
PY
~~~

旋转签名密钥会使旧会话失效。准备就绪后运行：

~~~bash
damumu-deploy-migration
~~~

该命令备份数据库、应用迁移并发布。旧服务器若未安装此入口，先按 deploy/README.md 安装快捷命令。默认发布流程自动同步仓库 Nginx 配置，通过 nginx -t 后 reload。核对网站 /api/、/uploads/ 同源代理，以及公共域名对管理路由的拒绝规则。

创建第一个管理员：

~~~bash
docker compose --env-file deploy/.env -f deploy/compose.yaml run --rm --no-deps api   --create-admin owner owner
~~~

终端隐藏密码输入，随后显示一次身份验证器设置地址及密钥。将它添加到身份验证器并妥善保管。通过原有 Admin 入口访问验证后，再用新账号、密码、验证码登录。

额外账号可用同一命令创建，最后参数支持 owner、moderator、viewer。owner 可执行全部操作，moderator 处理内容及用户治理，全局配置和公告写入需要 owner，viewer 只读。操作审计依据服务器核验的账号，忽略浏览器提供的操作人 ID。

## 发布验收

- 网站邮箱、Google/Kakao 登录、浏览器恢复、记住登录、退出当前及全部登录。
- App 登录、恢复、跨 15 分钟自动刷新、图片上传、私聊和重连。
- Admin 验证码防重放、只读账号写入拒绝及操作人审计，旧 Cookie 在退出后返回 401。
- 未登录和未批准参与者不能取得名单及集合点。退役会面和联系人 API 返回 404。
- 跨来源 Cookie 写入返回 403，超过限制返回 429，Nginx 错误响应也有安全头。
- API 健康、内存、媒体写入及日志轮转。HSTS 初始为一天，HTTPS 各入口稳定后再延长。

## 密钥、备份与事故恢复

数据库、媒体、.env、入口凭据和密钥目录须作为匹配的一组受限备份，备份不可通过网站访问，定期在隔离环境演练恢复。

验证器丢失时，在服务器创建新的 owner。确认可登录后，在维护窗口禁用丢失账号并删除其 admin_session，只允许受信任服务器操作人执行。

数据清理没有自动回滚 SQL。需回到旧系统时，先停写，再恢复发布前数据库与匹配的配置、镜像及媒体。

## 网络边界与持续检查

保留 Nginx Basic Auth 测试入口保护。数据库和容器端口限本机及指定私有网络，SSH 使用密钥并限制来源。应用数据库角色不能有 superuser、createdb、createrole 权限，实际服务器配置需在发布前核对。

代码中的 IP、账号、上传、并发及 WebSocket 限额限制应用层滥用。云端大流量防护、外部告警渠道及异地备份，需按服务器及预算另行配置。

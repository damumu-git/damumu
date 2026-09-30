# 慕搭 Admin

React + Vite 管理员运营系统，对应 `restapi` 中的 `/api/v1/admin/*` 接口。

包含运营概览、用户管理、活动管理、举报治理、安全警报、分类配置、
Feature Flag、审计日志和站内公告。

用户管理和活动管理列表均可进入详情页：用户详情汇总账号资料、信誉、
喜欢、参与履历和举报；活动详情汇总排期、地点、成员申请、举报与运营
处置记录。详情页和管理列表支持桌面及移动端布局。

## 本地开发

复制环境变量：

```bash
cp .env.example .env.local
```

启动：

```bash
npm install
npm run dev
```

默认访问：

```text
http://localhost:5173
```

REST API 默认地址：

```text
http://localhost:8080/api/v1
```

## Docker

```bash
docker build -t muda-admin .
docker run --rm -p 8088:80 muda-admin
```

生产环境不要把管理员 API Key 编译到浏览器资源中，应改为管理员登录、
短时会话 Cookie、RBAC 和二次验证。

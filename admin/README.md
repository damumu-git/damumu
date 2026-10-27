# 慕搭 Admin

## 界面主题

2026-10-27 已将预览浅蓝设计应用到正式 React 页面。`src/preview-theme.css` 在
原 `App.css` 之后加载，统一白色侧栏、浅蓝主按钮、表格、详情、编辑弹窗和响应式布局。
该文件是正式样式，不依赖 `preview/` 的脚本或示例数据；所有业务继续调用原 API。
同步说明见仓库根目录 `docs/UI_PREVIEW_SYNC.md`。

React + Vite 管理员运营系统，对应 `restapi` 中的 `/api/v1/admin/*` 接口。

包含运营概览、用户管理、活动管理、举报治理、安全警报、分类配置、
Feature Flag、审计日志和站内公告。

用户管理和活动管理列表均可进入详情页：用户详情汇总账号资料、信誉、
喜欢、参与履历和举报；活动详情汇总排期、地点、成员申请、举报与运营
处置记录，并允许管理员直接通过待审核的活动申请。详情页和管理列表支持
桌面及移动端布局。

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

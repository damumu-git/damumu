# 慕搭 Admin

新增“图标素材”管理及分类图片绑定，支持64×64 PNG上传、替换、改名和启停；使用API返回的完整图片URL，不挂载API磁盘。详见仓库根目录 `docs/EMOJI_LIBRARY.md`。

## 界面主题

品牌Logo与标签图标使用选定的蓝底暖白“环抱”图片，本地文件位于 `public/brand/` 及 `public/favicon.png`，不依赖API。母版与导出见根目录 `branding/README.md`。

通用控件由 `src/controls.css` 兜底，特定导航/状态/主操作样式优先。`AdminControls.jsx`提供统一文件选择器和处置/确认弹窗，替代浏览器prompt/confirm；保留原生file表单字段、必填校验及API参数，支持Escape和焦点恢复。新增裸按钮/输入无需另写一套默认样式。

Admin采用Light/Compact风格的灰白蓝管理工作台：224px分组侧栏、统一SVG线性菜单图标、紧凑工具栏、带网格的条纹表格与小圆角表单。字体为自托管Noto Sans SC / KR无衬线，离线预览同步；App字体和主题不变。设计及来源见 `DESIGN.md`，字体重建和许可见 `FONTS.md`。

原浅蓝预览样式作为基础保留，最后加载 `src/enterprise-theme.css` 应用当前工作台风格。`src/preview-theme.css` 在
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

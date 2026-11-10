# 搭慕网页版

`app.damumu.com` 从仓库中的 `app/` 构建，复用 Flutter 页面、登录和公共 API。手机与窄窗口用底部导航，900 像素及以上的窗口用侧边导航；首页按内容宽度显示一到四列活动卡片，保留搜索和筛选；网页支持横屏，桌面内容宽度上限为 1200 像素。浏览活动前仍需按现有流程登录。

## 本地开发

从仓库根目录运行：

```sh
cd app
flutter run -d chrome --dart-define=API_BASE_URL=https://api.damumu.com/api/v1
```

Chrome 的设备模拟模式可用于检查手机、平板和桌面窗口。网页使用浏览器支持的登录方式；原生 Google / Kakao 登录、原生推送和权限能力受平台限制。

## 服务器部署

日常发布从 `main` 运行 `damumu-deploy`。它会从 Flutter 源码构建容器并启动服务。
首次启用域名或从独立容器迁移，见 [服务器部署指南](../deploy/README.md#已有服务器首次启用-appdamumucom)。

## 手动静态构建

在安装 Flutter 的机器上运行：

```sh
cd app
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=https://api.damumu.com/api/v1 --output "$(cd ../app-web && pwd)/dist"
```

在 PowerShell 中将 `--output` 的值替换成 `app-web/dist` 的绝对路径。

`app-web/dist/` 是独立的静态部署产物，部署时将它和 `app-web/` 配置放到服务器的同一目录结构。也可把 `dist/` 作为支持单页应用回退的静态站点根目录。

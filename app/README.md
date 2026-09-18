# 在韩搭子 App

## 启动

默认 API 地址是 `http://localhost:8080/api/v1`。真机或 Android 模拟器需要传入
设备可访问的地址，例如：

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
```

用户模块支持邮箱注册/登录、登录态恢复、服务端系统头像目录，以及拍摄/相册选择、
锁定 1:1 裁剪和 512×512 JPEG 压缩上传。
活动封面锁定 4:3，输出 1280×960 JPEG；手机原照片由 App 先预缩图并自动压缩，
2 MB 仅限制最终上传文件。Web 的裁剪依赖本地 `web/vendor/cropperjs/`（1.6.2，
含许可证），不要删除 `web/index.html` 内对应 CSS 和 JS 引用。

界面支持中文、English、한국어，可从“我的 → 语言”切换并持久保存。用户注册、
登录、头像、个人中心和一级导航已接入三语资源；新增页面文案应统一添加到
`lib/l10n.dart`，不要直接硬编码。

## 本地测试账号

Debug 构建在没有有效登录态时会自动登录固定测试账号：

```text
邮箱：tester@muda.local
密码：MudaTest2026!
```

Release 构建不会启用自动登录。需要显式关闭时传入
`--dart-define=DEV_AUTO_LOGIN=false`。

## 活动列表分页

首页和发现列表使用 `/activities` Cursor 接口，每页 20 条。接近列表底部自动加载，
也可点“加载更多”；下拉刷新重新取首屏。页面共享已加载活动，使用 UUID 去重，
后续页失败保留列表并允许重试，定位变化/刷新使旧请求失效。
搜索和筛选当前作用于已加载活动，尚有后续页时会提示继续加载。

```powershell
flutter analyze
flutter test test/event_pagination_test.dart test/activity_feed_test.dart test/widget_test.dart
```

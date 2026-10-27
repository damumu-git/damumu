# 在韩搭子 App

## 界面主题

2026-10-27 圆体试用：中文 / 英文改用内置资源圆体 `Resource Han Rounded CN`
（Regular / Bold），韩文保留 Noto Sans KR。App 预览同步加载同源字体，Admin 未改动。
来源、许可证和离线预览字体重建说明见 `preview/app/FONTS.md`（仓库根目录）。

2026-10-27 已将预览的浅蓝设计应用到正式 Flutter 页面。统一主题见
`lib/app_theme.dart`；首页、竖版活动封面卡、底部导航及消息标签已同步，登录、发布、
详情、个人中心和弹窗使用共同配色与控件主题。真实 API、报名权限和消息同步沿用原实现。
对应关系与实际页面截图生成方式见 `docs/UI_PREVIEW_SYNC.md`（仓库根目录）。

## 启动

默认 API 地址是 `https://api.damumu.com/api/v1`，正常移动端开发不需要启动本地
REST API 或 Admin。仅在隔离数据库上开发服务端时显式覆盖，例如 Android 模拟器：

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

隐私版本2026-10-21：注册需主动确认满14岁及阅读政策；API需先应用迁移022。
私密聊天图片需要新版App发送认证头，退出/注销清理聊天缓存。App启动删除已过3个自然月的
本地消息，服务端也按相应规则删除内容。系统推送和外部地理编码默认停用；只有完整
跨境告知核定后才可使用`EXTERNAL_PROCESSING_DISCLOSURE_APPROVED=true`发布，并仍需用户
分别选择。API推送开关也需独立批准。不能用默认系统权限或笼统政策阅读替代告知。
运营与未决事项见`docs/PRIVACY_OPERATIONS.md`。注册页面旧golden依赖macOS字体，Windows
不执行该快照；新确认流程有跨平台行为测试，macOS基准需在发布机检查更新。

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

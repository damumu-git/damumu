# Android 首发准备步骤

最后核对：2026-10-15（Asia/Seoul）。P2 商店资料和正式提交暂缓，本页只覆盖当前 P0/P1。

## 1. 创建 Google Play Upload Key

在只由发布负责人控制的电脑执行：

```powershell
keytool -genkeypair -v `
  -keystore C:\secure\damumu-upload-keystore.jks `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias upload
```

要求：

1. `C:\secure\damumu-upload-keystore.jks`、密码和恢复副本必须放入密码管理器或受控备份，不能提交 Git。
2. 将 `app/android/key.properties.example` 复制为 `app/android/key.properties`。
3. 将 `storeFile` 改为密钥库的绝对路径，填写 `storePassword`、`keyPassword` 和 `keyAlias`。
4. `key.properties` 和 `*.jks` 已被 Git 忽略；提交前仍运行 `git status` 和密钥扫描。

验证正式签名：

```powershell
cd app
flutter build appbundle --release
keytool -printcert -jarfile build\app\outputs\bundle\release\app-release.aab
```

首次上传 Play Console 时启用 Play App Signing。以后使用 Upload Key 签名上传包，Google 管理面向用户的 App Signing Key。

## 2. Android API 36 与生产配置

代码已经固定 `compileSdk=36`、`targetSdk=36`，本机还需要：

1. 安装 Android Studio，并在 SDK Manager 安装 Android 16 / API 36 Platform、对应 Build Tools 和 Platform Tools。
2. 运行 `flutter doctor -v`，接受 Android licenses，并确认没有 Android toolchain 错误。
3. 运行 `flutter build apk --debug` 验证资源，再运行上面的正式 AAB 构建。
4. 安装到至少一台 Android 16 设备或模拟器，检查启动画面、登录、定位、相机、图片、聊天、推送和账号注销。
5. 使用 `bundletool` 或 Play Console App Bundle Explorer 确认 `targetSdkVersion=36`、版本 `1.0.0 (1)`、包名 `com.damumu.damu`。

生产客户端默认连接 `https://api.damumu.com/api/v1`，Android 主清单禁止明文 HTTP。本地 API 调试必须显式传入 `--dart-define=API_BASE_URL=http://...`，并在 Debug 清单单独允许所需网络策略，不能放宽 Release 主清单。

## 3. 账号删除上线验收

部署 API 和网站后，用专用测试账号验证：

1. 注册账号，补齐头像、兴趣、联系方式，登记推送设备并参加一场测试活动。
2. 从“我的 → 设置 → 账号与隐私 → 注销账号”确认删除。
3. 确认接口返回 `status=deleted`，App 清除本地登录状态。
4. 使用原邮箱和密码登录必须失败；删除前取得的旧 Bearer Token 也必须立即返回 `account_unavailable`；数据库中 `user_credential`、`push_device`、通知、兴趣、安全联系人及安全定位记录必须不存在。
5. `app_user` 状态必须为 `deleted`，资料只保留“已注销用户”匿名占位；历史活动和聊天不能再显示原昵称、头像、邮箱或联系方式。
6. 该用户尚未开始的活动必须取消；其他用户的历史活动和会话仍可正常读取。
7. 验证 `https://www.damumu.com/account-deletion.html` 无需登录即可访问，邮件删除请求流程能在承诺的 7 日内完成。

## 4. 隐私与合规核对步骤

1. 建立“功能／数据／目的／保存期／接收方／删除方式”清单，以 API、数据库字段和最终 Android 包为准。
2. 核对账号邮箱、资料、精确及大致位置、头像和图片、聊天、活动与报名、推送令牌、举报和诊断日志。
3. 列出第三方处理方：AWS、Firebase Cloud Messaging、OpenStreetMap Nominatim；确认生产配置没有额外分析、广告或崩溃 SDK。
4. 验证权限最小化：位置只在用户触发附近功能时申请，相机和照片只在选择上传时申请；拒绝权限后仍有可用降级路径。
5. 核对隐私政策、App 内文案、Google Data Safety 三处答案一致；没有广告和跨 App 跟踪时不要误报 Tracking。
6. 对删除、举报、纠纷和安全记录确定真实保存期限及负责人，替换隐私政策中仍未确认的运营主体信息。
7. 保存一份上架版本的数据流快照、SDK 列表和核对日期；每次新增 SDK、权限或数据用途都重新评审。

## 5. 当前人工待办

- 选择 `branding/` 中的最终图标方向，再导出 Android adaptive icon 和 Play 512×512 正式图标。
- 安装 Android SDK 36；当前 Windows 主机已有 Flutter，但尚未配置 Android SDK，因此无法在此主机完成 APK/AAB 构建。
- 创建并妥善保管 Upload Key，完成正式 AAB 签名验证。
- 部署本次 API/网站代码后，按第 3 节在 AWS 测试环境走完整注销验收。

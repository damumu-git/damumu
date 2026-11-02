# Google / Kakao 原生登录配置

代码覆盖 Android / iOS App 的第三方登录、服务端身份校验和首次注册。
当前尚未创建平台应用，因此默认关闭，未进行真实账号授权验收。
Flutter Web / 桌面端暂不发起第三方授权，继续使用邮箱；离线预览只演示页面。

## 登录及数据行为

- Google官方Flutter SDK获取ID Token，API使用Google官方.NET库校验签名、发行方、受众和有效期。
- Kakao官方Flutter SDK优先打开Kakao Talk，无安装时使用账号浏览器登录；API调用官方`access_token_info`，核对应用ID、用户ID和有效期。
- 只按`provider + subject`查找本地账号；客户端传入的邮箱、用户ID或头像不作为身份依据，不按相同邮箱自动合并账号。
- 未注册时只返回`registrationRequired`，不发本地Token、不插入账号。用户填写昵称，主动确认满14岁及阅读当前政策后，再次校验第三方凭据并原子创建账号。
- 社交账号没有邮箱密码凭据行，不收集或同步平台头像、邮箱、好友列表，不发送Kakao消息。系统头像从现有目录选择。
- 本地会话沿用当前API认证；取消授权或取消补充注册不创建账号。第三方Token不写数据库、URL或日志，SDK缓存尽力清理。
- 注销时删除本地第三方身份关联；这不等于替用户注销Google/Kakao账号。用户仍可在对应平台管理已授权应用。

## 1. 创建 Google 应用

可复用已有Firebase项目所关联的Google Cloud项目，无需把用户体系迁移到Firebase Authentication。

1. 在[Google Cloud Console](https://console.cloud.google.com/)的Google Auth Platform配置品牌、受众、测试用户和数据访问；发布前完成平台要求的审阅。
2. 创建一个**Web应用OAuth客户端**，其Client ID用于后端ID Token受众，记为`GOOGLE_SERVER_CLIENT_ID`。本方案不使用Web授权码回调，也不需要客户端密钥。
3. 创建Android OAuth客户端，包名为`com.damumu.damu`，录入实际签名证书SHA-1。Debug、Release和Play App Signing证书各自登记，不能只登记上传证书。
4. 创建iOS OAuth客户端，Bundle ID为`com.damumu.damu`，记下iOS Client ID和反转Client ID。
5. App传入`GOOGLE_SERVER_CLIENT_ID`和iOS的`GOOGLE_IOS_CLIENT_ID`；API只允许与App一致的Web Client ID。

参考：[Flutter Android配置](https://pub.dev/packages/google_sign_in_android)、[Flutter iOS配置](https://pub.dev/packages/google_sign_in_ios)、[服务端校验](https://developers.google.com/identity/sign-in/web/backend-auth)。

## 2. 创建 Kakao 应用

在[Kakao Developers](https://developers.kakao.com/)创建应用，启用Kakao Login：

1. 保存**数字App ID**（后台校验）及**Native App Key**（App SDK）。二者不是同一值；不要用REST API Key替代数字App ID。
2. Android平台注册包名`com.damumu.damu`和签名证书Key Hash。Kakao Key Hash是签名证书SHA-1摘要的Base64，与Google显示的十六进制SHA-1不同。
3. iOS平台注册Bundle ID `com.damumu.damu`。
4. 原生回调是`kakao<NativeAppKey>://oauth`。Android从同一个`--dart-define`自动生成Manifest回调；iOS还需配置下述公开URL Scheme。
5. 当前仅使用稳定用户ID，不需要邮箱或好友权限；不要添加不使用的同意项目。开启Client Secret的应用还需核对当前原生SDK支持的配置，不能把Client Secret或Admin Key打包进App。

参考：[官方Flutter设置](https://developers.kakao.com/docs/ko/flutter/getting-started)、[登录流程](https://developers.kakao.com/docs/ko/kakaologin/flutter)、[Token信息校验](https://developers.kakao.com/docs/ko/kakaologin/rest-api#req-access-token-info)。

## 3. 服务端和迁移

新增`restapi/Migrations/024_social_login.sql`，创建`user_external_identity`，无Token或邮箱字段。
先备份数据库并按现有部署流程执行024，再部署API；不能仅添加`--migrations-applied`来跳过实际迁移。
需要额外确认API数据库角色对新表具有所需权限，沿用现有迁移角色/授权流程。

在服务器`deploy/.env`配置公开ID（不需要发到聊天中）：

```dotenv
GOOGLE_LOGIN_ENABLED=true
GOOGLE_SERVER_CLIENT_ID=<Web OAuth Client ID>
KAKAO_LOGIN_ENABLED=true
KAKAO_APP_ID=<数字App ID>
```

Compose已映射至`SocialLogin:google:*`和`SocialLogin:kakao:*`。两个Enabled默认false，可独立开放。
非Compose配置可使用同名.NET环境变量：`SocialLogin__google__Enabled`等。
没有平台配置时维持false；邮箱登录不受影响。

## 4. 构建 App

身份接收方、处理内容和授权撤回说明应先同步到隐私政策，并核定是否需更新政策版本。
客户端现有政策版本仍为`2026-10-21`；服务器和客户端版本必须一致。未完成这一步前保持默认关闭。
项目的FCM和外部地理编码开关与社交登录独立，不要顺带打开。

公开ID可通过本地不入库配置文件传入，或直接传递：

```bash
flutter run --dart-define=DEV_AUTO_LOGIN=false \
  --dart-define=SOCIAL_LOGIN_ENABLED=true \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<Web客户端ID> \
  --dart-define=GOOGLE_IOS_CLIENT_ID=<iOS客户端ID> \
  --dart-define=KAKAO_NATIVE_APP_KEY=<NativeAppKey>
```

iOS还需在Xcode的Runner Target Build Settings配置：

```text
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.<反转后的iOS Client ID>
KAKAO_NATIVE_APP_KEY = <与Dart一致的NativeAppKey>
```

`ios/Flutter/SocialLogin.xcconfig`包含未开放的默认值，`Info.plist`引用上述值。
不要把Web Client ID当作iOS回调Scheme，也不要把数字Kakao App ID当作Native Key。
使用Xcode构建时也需传入相同的Dart配置；现有签名、Firebase推送配置保持独立。

## 5. 验收范围

可自动验证的部分：取消不发请求、不保存会话；首次注册默认不勾选；年龄/政策版本校验；
Kakao应用/有效期检查；并发不重复建号；停用/删除账号拒绝登录；迁移可重复执行。
配置平台之后，仍必须在Android/iOS真机测试首次授权、返回、拒绝、取消、重复登录、Token失效、
卸载Kakao Talk后的浏览器回退、不同签名证书和注销重登，才能开放真实服务。

Apple的[审核规则4.8](https://developer.apple.com/app-store/review/guidelines/#login-services)对用于主要账号的第三方登录要求等效的隐私保护登录选项，除非符合例外；通常需评估同时提供Sign in with Apple。本次不包含Apple登录，不能据此认定iOS已满足上架要求。

Google按钮使用[官方G图标](https://developers.google.com/static/identity/images/g-logo.png)，
按[品牌指南](https://developers.google.com/identity/branding-guidelines)配置白底/描边；
Kakao图标直接使用官方SDK的`icon_talk_login.svg`，不自绘商标。

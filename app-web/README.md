# 搭慕网页版

`app.damumu.com` 使用独立 HTML、CSS 和 JavaScript。活动、分类、地区和账号数据来自搭慕公共 API；网页版与 Android / iOS 使用相同账号及活动。访客可直接搜索、筛选和查看活动。登录后可报名、退出、发布和查看活动记录，也可读取会话及发送文字消息。聊天附件和原生推送仍通过移动 App 使用。

## 本机预览

从仓库根目录运行：

```sh
docker compose -f app-web/compose.yaml up --build
```

浏览器打开 http://127.0.0.1:8083。本地容器可访问公开活动和邮箱登录；注册和网页 OAuth 使用生产同源代理。

## 服务器部署

从 `main` 运行 `damumu-deploy`。它会构建独立网站镜像、部署 API 和其它服务并检查健康状态。首次配置域名或从旧容器迁移，见 [服务器部署指南](../deploy/README.md)。

## 网页 Google 和 Kakao 登录

提供方回调地址必须精确匹配：

| 提供方 | 回调地址 | 服务器 `deploy/.env` |
| --- | --- | --- |
| Google | `https://app.damumu.com/api/v1/auth/web/google/callback` | `GOOGLE_WEB_CLIENT_ID`、`GOOGLE_WEB_CLIENT_SECRET` |
| Kakao | `https://app.damumu.com/api/v1/auth/web/kakao/callback` | `KAKAO_WEB_REST_KEY`、`KAKAO_WEB_CLIENT_SECRET`、`KAKAO_APP_ID` |

在 Google Cloud 建立 Web application 类型的 OAuth 客户端，加入对应回调地址。Kakao 在现有原生登录使用的同一 Kakao 应用内启用登录，将对应回调加到使用的 REST API key，并启用该 key 的 Client secret。两种密钥都只填写在服务器配置。配置完成后运行 `damumu-deploy`，分别用提供方测试账号验证首次注册和再次登录。

第三方首次登录沿用搭慕已有账号规则，需确认年龄和隐私政策。网页不触发定位、相机或通知授权。

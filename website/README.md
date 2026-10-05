DAMUMU 静态官网
================

部署方式
1. 将本文件夹内全部文件上传到 Nginx 网站根目录、AWS S3 静态网站 bucket，或任意静态托管服务。
2. 入口文件为 index.html。
3. 不需要 Node.js、数据库或构建步骤。

上线前必须处理
- 全局搜索“[필수”与“[예:”并替换所有黄色占位内容。
- 用真实 App 截图替换首页 CSS mockup（可选）。
- 把 Google Play / App Store 下载按钮改成真实链接。
- 用真实商店链接生成 QR 图后替换二维码占位。
- 让韩国法律专业人士核对 privacy.html、terms.html。
- 确保 Google Play Data safety、Apple App Privacy 与 privacy.html 及 App 实际行为一致。
- 确认账号删除入口、邮件处理流程和各类数据保存/删除期限。

文件
- index.html 首页
- privacy.html 개인정보 처리방침草案
- terms.html 이용약관草案
- account-deletion.html 账号删除说明
- support.html 客服页
- styles.css 全站样式
- script.js 移动导航与年份

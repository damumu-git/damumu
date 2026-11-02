# 搭慕品牌素材

`tamu-logo-concept-v1.png` 是“搭”字方向的首版 App Logo 候选稿：深墨绿色底、暖白色字形，右上部用两个人物连接的负形表达“搭伴、相遇”。

该“搭”字稿及 `candidates/` 中的图稿保留为历史候选，现已由下述环抱方案替代。

## 当前 Logo：晴空蓝立体环抱（2026-11-02 用户选定）

当前母版 `damumu-embrace-3d-master.png` 是用户上传并明确选定的晴空蓝底、暖白陶瓷立体环抱图；隐含 D 的包围形状与 M 的双峰节奏，不使用直白字母文字。1254×1254不透明RGB PNG，直接使用附件原图，未重新生成、重绘或调色。SHA-256：`faadf524758a45c12984268afc363125626356947c76af5852b7d1b0d46e65b3`。

旧版雾蓝平面母版 `damumu-embrace-master.png` 保留为历史素材，导出脚本已切换到新母版。Android启动背景与留白使用原图左上角颜色 `#aad6f9`，Web主题色采用晴空蓝 `#86bff0`。

该图来自先前内置 imagegen 的立体方案；提示方向为隐藏DM结构、环抱曲线与双峰、明亮晴空蓝、暖白柔和陶瓷、正面视角及克制阴影。此次替换不调用图片生成。

运行 `python branding/export-logo.py`（需要 Pillow）从母版重新导出：

- Flutter登录/注册页本地图片、Android各密度桌面图标与启动图、自适应图标及安全留白。
- iOS AppIcon完整尺寸和LaunchImage的1x/2x/3x图片，商店1024px图片为不透明RGB。
- Flutter Web图标、加载Logo及maskable图标；Admin品牌与标签图标。
- 产品网站页头/页脚、标签和Apple触摸图标；App/Admin离线预览。

网页中的小Logo采用256px图片，标签图标48px。品牌素材本地打包，不依赖API、数据库或媒体上传目录；三个Docker构建上下文各自拥有所需文件。导出只进行缩放和安全留白，不自动生成SVG，也不覆盖历史候选。平台安装包/商店图标需要重新构建发布，网站和Admin需要重新部署才能上线。

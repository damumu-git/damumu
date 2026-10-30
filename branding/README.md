# 搭慕品牌素材

`tamu-logo-concept-v1.png` 是“搭”字方向的首版 App Logo 候选稿：深墨绿色底、暖白色字形，右上部用两个人物连接的负形表达“搭伴、相遇”。

该“搭”字稿及 `candidates/` 中的图稿保留为历史候选，现已由下述环抱方案替代。

## 当前 Logo：环抱（2026-10-30 用户选定）

母版 `damumu-embrace-master.png` 为内置 imagegen 生成的第二款方案：雾蓝底、暖白环抱曲线，隐含 D 的包围形状与 M 的双峰节奏，不使用直白字母文字。保留用户选定原图，未重绘；原稿为1254×1254不透明PNG。

生成提示方向：abstract hidden D/M, welcoming ribbon enclosure and double wave, dusty blue and warm ivory, simple centered app icon, no readable lettering or text。

运行 `python branding/export-logo.py`（需要 Pillow）从母版重新导出：

- Flutter登录/注册页本地图片、Android各密度桌面图标与启动图、自适应图标及安全留白。
- iOS AppIcon完整尺寸和LaunchImage的1x/2x/3x图片，商店1024px图片为不透明RGB。
- Flutter Web图标、加载Logo及maskable图标；Admin品牌与标签图标。
- 产品网站页头/页脚、标签和Apple触摸图标；App/Admin离线预览。

网页中的小Logo采用256px图片，标签图标48px。品牌素材本地打包，不依赖API、数据库或媒体上传目录；三个Docker构建上下文各自拥有所需文件。导出只进行缩放和安全留白，不自动生成SVG，也不覆盖历史候选。平台安装包/商店图标需要重新构建发布，网站和Admin需要重新部署才能上线。

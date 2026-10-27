# Admin Light/Compact 管理工作台

2026-10-27按DevExpress风格方向调整现有React后台。参考官方
[浅色/紧凑主题](https://js.devexpress.com/React/Documentation/24_2/Guide/Themes_and_Styles/Predefined_Themes/)
和[组件示例](https://js.devexpress.com/React/Demos/WidgetsGallery/)。
实现采用项目自有CSS、SVG与既有React组件，未新增组件套件依赖或更改API协议。

## 视觉与布局

- 灰白工作区、蓝色主操作与选中态，统一4–6px小圆角、细边框、较紧凑间距。
- 224px左侧导航，区分业务管理与系统配置；主内容顶部64px工具栏。
- 菜单使用11个同尺寸、同线宽SVG图标，选中项显示蓝色边条。
  移除与真实举报数量无关的固定感叹号；移动端菜单提供可关闭遮罩。
- 表格统一表头、列边界、浅色隔行及悬停态；管理表格在自身容器中滚动，
  窄屏保留横向滚动。低高度窗口仍保留足够的可读行区域。
- 表单、文件选择器、分类卡片、确认/处置弹窗采用同一套外观；
  原有提交、取消、权限、筛选、审计和数据来源保持不变。
- 使用自托管Noto Sans SC / KR无衬线字体，见 `FONTS.md`。App继续使用原主题与文楷。

## 维护位置

- `src/enterprise-theme.css`：最后加载的正式工作台样式。
- `src/navigation-icons.json` / `AdminNavIcon.jsx`：共享路径数据及React SVG渲染器。
- `src/controls.css` / `AdminControls.jsx`：通用控件语义和行为。
- `preview/admin/enterprise-theme.css`：离线预览样式，App预览不加载此文件。
- `preview/admin/admin-fonts.css`：独立离线字库，不引用App字体。

图标变更后在仓库根目录执行 `python admin/build-navigation.py`；
字体变更执行 `python admin/build-fonts.py`（需fonttools[woff]）。
生产构建直接使用已提交的资源，无需运行Python。

Admin预览使用独立的enterprise-v1主题存储键，防止此前保存的浅蓝/圆角参数
覆盖新默认值；App原有主题存储不变。预览仍是虚构数据，不调用生产API。

## 发布

按原流程合并并重建Admin服务即可，无新增数据库迁移，不需要改动API或发布App。

# 页面覆盖清单

按实际 Flutter / React 的用户可见页面及弹窗整理。弹窗在目录中可独立打开，便于评审；不代表正式产品新增独立路由。通用加载、空数据、失败状态由顶部选择器切换。

此清单由离线检查读取页面目录生成；业务变化后应重新核对源代码并更新。

| 页面 / 弹窗 | 本地入口 | 代码来源 | 类型 |
| --- | --- | --- | --- |
| 首页 | `app/index.html#home` | app/lib/main.dart · HomePage | 业务预览 |
| 发现活动 | `app/index.html#discover` | app/lib/main.dart · DiscoverPage | 业务预览 |
| 地图视图 | `app/index.html#map` | app/lib/main.dart · MapPlaceholder | 现有占位 / 说明 |
| 位置与地区选择 | `app/index.html#location` | app/lib/main.dart · _showLocationOptions / _ManualLocationSheet | 业务预览 |
| 首页提醒 | `app/index.html#home-notice` | app/lib/main.dart · _showNotice | 业务预览 |
| 活动详情 | `app/index.html#event` | app/lib/main.dart · EventDetailPage | 业务预览 |
| 报名申请 | `app/index.html#apply` | app/lib/main.dart · _EventDetailPageState._join | 业务预览 |
| 报名结果 | `app/index.html#join-result` | app/lib/main.dart · _showJoinResult | 业务预览 |
| 退出活动确认 | `app/index.html#leave` | app/lib/main.dart · _EventDetailPageState | 业务预览 |
| 公开用户资料 | `app/index.html#public-profile` | app/lib/main.dart · PublicUserProfilePage | 业务预览 |
| 发布 · 基本信息 | `app/index.html#create-basic` | app/lib/main.dart · CreateEventPage._basic | 业务预览 |
| 发布 · 时间地点 | `app/index.html#create-schedule` | app/lib/main.dart · CreateEventPage._schedule | 业务预览 |
| 发布 · 费用与规则 | `app/index.html#create-rules` | app/lib/main.dart · CreateEventPage._rules | 业务预览 |
| 从过往活动发布 | `app/index.html#copy-event` | app/lib/main.dart · _chooseSource / MyActivitiesPage | 业务预览 |
| 封面选择与裁剪 | `app/index.html#cover-crop` | app/lib/event_cover_image.dart · EventCoverImage / WebCropperLayout | 业务预览 |
| 未保存退出确认 | `app/index.html#unsaved` | app/lib/main.dart · CreateEventPage._confirmLeave | 业务预览 |
| 我的活动 | `app/index.html#my-activities` | app/lib/main.dart · MyActivitiesPage | 业务预览 |
| 活动参与记录 | `app/index.html#activity-record` | app/lib/main.dart · _MyActivityRecordPage | 业务预览 |
| 组织者管理详情 | `app/index.html#organizer` | app/lib/main.dart · _MyActivityRecordPage / _OrganizerApplications | 业务预览 |
| 取消活动 | `app/index.html#cancel-event` | app/lib/main.dart · _MyActivityRecordPage._cancelEvent | 业务预览 |
| 活动后喜欢与举报 | `app/index.html#feedback` | app/lib/feedback.dart · FeedbackActionGrid / FeedbackTagDialog | 业务预览 |
| 消息中心 | `app/index.html#messages` | app/lib/main.dart · MessagesPage | 业务预览 |
| 通知详情 | `app/index.html#notification` | app/lib/main.dart · NotificationDetailPage | 业务预览 |
| 会话聊天 | `app/index.html#chat` | app/lib/main.dart · ChatPage | 业务预览 |
| 只读活动群 | `app/index.html#chat-readonly` | app/lib/main.dart · ChatPage / group lifecycle | 业务预览 |
| 消息操作 | `app/index.html#message-actions` | app/lib/main.dart · _showMessageActions | 业务预览 |
| 举报消息 | `app/index.html#message-report` | app/lib/main.dart · ChatPage._report | 业务预览 |
| 聊天图片预览 | `app/index.html#chat-image` | app/lib/main.dart · ChatImagePreviewPage | 业务预览 |
| 拍照与相册 | `app/index.html#chat-attachment` | app/lib/main.dart · ChatPage._chooseChatImageSource | 业务预览 |
| 退出群聊 / 隐藏会话 | `app/index.html#conversation-remove` | app/lib/main.dart · MessagesPage / ChatPage | 业务预览 |
| 我的 | `app/index.html#profile` | app/lib/main.dart · ProfilePage | 业务预览 |
| 邮箱登录 | `app/index.html#login` | app/lib/auth.dart · AuthPage | 业务预览 |
| 注册账号 | `app/index.html#register` | app/lib/auth.dart · AuthPage | 业务预览 |
| 头像编辑 | `app/index.html#avatar` | app/lib/auth.dart · showAvatarEditor | 业务预览 |
| 头像裁剪与确认 | `app/index.html#avatar-crop` | app/lib/auth.dart · cropAndUploadAvatar | 业务预览 |
| 头像全屏预览 | `app/index.html#avatar-preview` | app/lib/activity_interactions.dart · AvatarPreviewPage | 业务预览 |
| 设置 | `app/index.html#settings` | app/lib/main.dart · _ProfileInfoPage | 现有占位 / 说明 |
| 语言选择 | `app/index.html#language` | app/lib/main.dart · _showLanguagePicker | 业务预览 |
| 通知与外部处理 | `app/index.html#external` | app/lib/external_processing.dart · ExternalProcessingSettings | 业务预览 |
| 隐私政策入口 | `app/index.html#privacy` | app/lib/main.dart · _openPrivacyPolicy | 业务预览 |
| 注销账号确认 | `app/index.html#delete-account` | app/lib/main.dart · _confirmAccountDeletion | 业务预览 |
| 退出登录 | `app/index.html#logout` | app/lib/main.dart · AuthController.logout | 业务预览 |
| 信誉与评价 | `app/index.html#trust` | app/lib/main.dart · _ProfileInfoPage | 现有占位 / 说明 |
| 屏蔽与举报记录 | `app/index.html#blocks` | app/lib/main.dart · _ProfileInfoPage | 现有占位 / 说明 |
| 帮助与社区规则 | `app/index.html#help` | app/lib/main.dart · _ProfileInfoPage | 业务预览 |
| 安全中心 | `app/index.html#safety` | app/lib/main.dart · SafetyCenterPage | 现有占位 / 说明 |
| 紧急帮助 | `app/index.html#emergency` | app/lib/main.dart · _showEmergency | 现有占位 / 说明 |
| 运营概览 | `admin/index.html#dashboard` | admin/src/App.jsx · Dashboard | 业务预览 |
| 用户管理 | `admin/index.html#users` | admin/src/App.jsx · Users | 业务预览 |
| 活动管理 | `admin/index.html#events` | admin/src/App.jsx · Events | 业务预览 |
| 举报治理 | `admin/index.html#reports` | admin/src/App.jsx · Reports | 业务预览 |
| 安全警报 | `admin/index.html#safety` | admin/src/App.jsx · Safety | 业务预览 |
| 分类配置 | `admin/index.html#categories` | admin/src/App.jsx · Categories | 业务预览 |
| 地区管理 | `admin/index.html#regions` | admin/src/App.jsx · Regions | 业务预览 |
| 系统头像 | `admin/index.html#avatars` | admin/src/App.jsx · SystemAvatars | 业务预览 |
| 审计日志 | `admin/index.html#audit` | admin/src/App.jsx · Audit | 业务预览 |
| 功能开关 | `admin/index.html#settings` | admin/src/App.jsx · Settings | 业务预览 |
| 用户详情 | `admin/index.html#user-detail` | admin/src/App.jsx · UserDetail | 业务预览 |
| 活动详情与成员 | `admin/index.html#event-detail` | admin/src/App.jsx · EventDetail | 业务预览 |
| 新建分类 | `admin/index.html#category-new` | admin/src/App.jsx · CategoryEditor | 业务预览 |
| 编辑分类 | `admin/index.html#category-edit` | admin/src/App.jsx · CategoryEditor | 业务预览 |
| 新建地区 | `admin/index.html#region-new` | admin/src/App.jsx · RegionEditor | 业务预览 |
| 编辑地区 | `admin/index.html#region-edit` | admin/src/App.jsx · RegionEditor | 业务预览 |
| 发布站内公告 | `admin/index.html#announcement` | admin/src/App.jsx · AnnouncementDialog | 业务预览 |
| 账号状态处置 | `admin/index.html#user-action` | admin/src/App.jsx · UserDetail.changeStatus / Users.changeStatus | 业务预览 |
| 活动处置 | `admin/index.html#event-action` | admin/src/App.jsx · EventDetail.moderate / Events.moderate | 业务预览 |
| 举报处置 | `admin/index.html#report-action` | admin/src/App.jsx · Reports.update | 业务预览 |
| 警报响应 | `admin/index.html#safety-action` | admin/src/App.jsx · Safety.update | 业务预览 |
| 删除分类确认 | `admin/index.html#delete-category` | admin/src/App.jsx · Categories | 业务预览 |
| 删除地区确认 | `admin/index.html#delete-region` | admin/src/App.jsx · Regions | 业务预览 |

| 图标素材 | `admin/index.html#emoji-assets` | admin/src/EmojiAssets.jsx · EmojiAssetManager | 真实素材离线图册，管理操作在正式Admin |

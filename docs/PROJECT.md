# DAMUMU 项目说明

## 产品定位

DAMUMU（中文 UI 名称“搭慕慕”）是一款面向韩国本地生活场景的线下活动发现、发布与结伴应用。核心流程是用户注册或登录后发现活动、查看详情、报名或申请、由组织者处理申请，并在获得批准后参与活动和交流。

## 核心模块

- 用户认证、个人资料与头像。
- 活动分类、行政区域、活动发现与筛选。
- 活动发布、报名、候补、组织者审批与参与记录。
- 消息、通知、活动聊天及安全治理（部分仍待接入真实数据）。
- 用户端 App、运营管理后台和独立产品介绍网站。

## 系统组成

- `app/`：Flutter 用户端，覆盖 Web、Android 和 iOS。
- `restapi/`：ASP.NET Core REST API。
- `restapi/Migrations/`：按编号执行的 PostgreSQL 迁移。
- `admin/`：React/Vite 运营管理后台。
- `website/`：独立静态产品介绍网站。
- `docs/`：项目上下文、当前状态与架构决策。

## 技术栈

- Backend：ASP.NET Core 10 Minimal API、Npgsql 10。
- Database：PostgreSQL、PostGIS；当前远端业务数据库名为 `damumu`。
- App：Flutter、Dart、Material 3。
- Admin：React 19、Vite 8。
- Infrastructure：本地开发服务加 Tailscale 可达的 PostgreSQL 主机。
- Object Storage：尚未确定，头像当前使用 API 本地持久化目录。
- Push / Realtime：尚未选型或完整接入。

## 长期业务规则

- 平台不收取活动费用，不提供支付、转账、托管、退款或资金担保；金额仅表示组织者填写的线下预计人均韩元支出。
- 精确集合地点只允许组织者以及状态为 `approved` 或 `attended` 的参与者读取。
- 新活动当前直接发布，不强制经过管理员预审。
- 活动分类、行政区域和生产活动列表以 API/数据库为准，不在客户端重新维护硬编码目录。
- 活动容量包含组织者本人；组织者是第一个已批准参与者。
- API 使用统一的 `{ data, meta, error, traceId }` 响应封装，不向客户端泄露 SQL、堆栈、凭据或内部连接信息。
- 用户端服务器读取失败时使用统一内容区错误状态，不显示原始 HTTP、解析器或数据库异常。
- 未实现功能必须如实标注，不得把说明性占位页描述成已完成能力。

## 外部服务与依赖

- PostgreSQL/PostGIS：业务数据、地理位置与目录数据。
- 浏览器/设备定位：附近活动和本地化位置标签。
- Apple、Google、短信认证、对象存储和推送服务尚未作为生产依赖确定。

## 进一步资料

- `docs/STATUS.md`：当前实现状态与下一步。
- `docs/DECISIONS.md`：已采用的长期架构和产品决策。
- `MVP.md`、`FIRST_RELEASE_FLOWS.md`：首发范围与验收流程。
- `DEVELOPMENT_CONTEXT.md`：详细历史背景，仅作参考。

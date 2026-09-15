# DAMUMU 当前项目状态

最后更新：2026-09-15（Asia/Seoul）

## 正在进行

- REST API 集成测试暂时统一使用电脑现有的 `localhost:5432/muda` PostgreSQL，不连接远端 PostgreSQL。
- 完成真实、数据库驱动的活动参与闭环；优先处理真实 UUID、详情、加入/退出及组织者成员管理。
- 统一 Flutter 内容加载错误状态，覆盖 HTTP 400/500、超时、断网、空响应及非 JSON 响应。

## 最近完成

- 新增 `scripts/test-local-postgres.ps1`：固定连接 `127.0.0.1:5432`，从隐藏输入或本机环境变量读取密码，默认只读启动临时 API 并执行 Cursor 数据库及 HTTP 集成测试；迁移必须通过 `-ApplyMigrations` 明确启用。
- 已确认本机 PostgreSQL 17 服务正在运行且要求密码认证，现有业务测试库名为 `muda`。误建的 Docker `55432` 测试容器及专用 volume 已删除。
- `localhost:5432/muda` 验证通过：API 与测试项目构建成功；Cursor 编解码、真实查询 SQL 的同时间戳排序、翻页期间插入/删除、`limit+1`、末页/空页及 HTTP 非法游标检查全部通过。SQL 样本仅存在于事务临时表并已回滚，本机业务表没有写入测试数据。
- 追加 Flutter 构建异常友好兜底：MaterialApp 配置 `ErrorWidget.builder`，不把异常文本/堆栈呈现在用户页面，开发诊断保留；重试重新挂载页面树。
- 截图中的 `Null is not a subtype of bool` 缺少运行时堆栈，尚不能确认具体字段；热重载保留旧状态是待核实原因。真实运行环境已增加构建异常友好兜底，开发诊断仍写入控制台；发布新字段后应执行 Hot Restart。

- APP 首页/发现活动流已改为 Cursor 分页，每页 20 条：滚动加载、手动加载更多、下拉刷新、失败重试、UUID 去重及请求代次隔离。
- 新增 `GET /api/v1/activities`，`data={items,nextCursor,hasMore}`；按 `event.created_at DESC, event.id DESC` 使用 keyset SQL 和 `limit+1`，非法游标安全返回 400。原 `/events` 与后台分页保留。
- 新增 `010_activity_cursor_index.sql`（尚未应用到持久数据库）以及 ADR-012。
- 本次验证：Dart 格式化、Flutter analyze 无问题；错误兜底、分页服务/界面和现有 widget 核心测试共 11 项通过；API 和测试程序构建 0 警告/错误。
- 游标校验测试、真实 API 只读检查（当前 1 条公开活动）和数据库临时表测试通过；临时表验证同时间戳 UUID 顺序、头部新增、边界删除、多页/末页/空页，事务已回滚。
- 全量 Flutter 测试另有 1 项原有注册快照测试失败：硬编码 macOS 字体路径在 Windows 不存在，Golden 差异 83.85%；未修改快照基线。

- 远端 PostgreSQL 业务数据库已从 `muda` 重命名为 `damumu`，项目连接配置已同步，连接验证通过。
- Flutter Web 启动遮罩会等待字体和首帧稳定，避免 CanvasKit 缺字方框闪现。
- 首页活动加载、我的活动、分类、地区及报名申请已接入统一内容区错误页，不再直接呈现解析或数据库异常。
- 首页筛选使用原始开始时间、定位结果和服务端新手友好标识。
- 组织者活动记录可以加载、批准和拒绝待处理报名申请。
- 活动容量包含组织者；迁移 `009_count_organizer_in_capacity.sql` 用于修复历史计数。
- 独立静态产品介绍网站已放在 `website/`。
- 已建立 `AGENTS.md`、`docs/PROJECT.md`、`docs/STATUS.md`、
  `docs/DECISIONS.md` 四文件项目上下文体系。

## 下一步

1. 在本机设置 `DAMUMU_LOCAL_POSTGRES_PASSWORD` 或运行脚本时隐藏输入密码，然后执行 `./scripts/test-local-postgres.ps1`；远端部署仍需单独应用 `010_activity_cursor_index.sql`。
2. 将 Flutter 的 `EventItem.id` 从整数/hash 改为数据库 UUID 字符串并保持 list → detail → join/leave 全链路一致。
3. 使用 `GET /events/{id}` 加载真实活动详情。
4. 接入真实加入、退出、候补及完整组织者成员管理。
5. 接入通知和活动聊天，再完成举报、屏蔽、评价与安全会面流程。

## 已知问题

- APP 搜索、分类和日期筛选仍针对已加载活动，尚非服务端全量筛选；有后续页时 UI 已标注该范围。

- Flutter `EventItem.id` 仍有旧的整数/hash 行为。
- 活动与地点创建尚未合并成单个数据库事务。
- 用户令牌和管理员静态 API Key 仍是开发阶段机制。
- `app/lib/main.dart` 和 `admin/src/App.jsx` 体积较大，但当前不应为拆分而进行无关重构。
- 消息、通知、统计和部分治理页面仍有演示数据或说明性占位内容。
- 头像文件仍依赖 API 本地目录，生产对象存储方案未确定。
- 数据库连接秘密目前存在本地配置风险，应改用环境变量并轮换已暴露凭据。

## 当前阻塞

- Flutter SDK 锁文件和 Dart 分析缓存需要用户目录写权限；本次使用 SDK 内 Dart/Flutter 工具并允许缓存写入，格式化、分析和 11 项核心测试已完成。
- 原有注册 Golden 测试仍受 macOS 专属字体路径阻塞。
- Cursor 索引迁移及正常开发服务重新部署尚未执行；验证使用独立临时 API 端口，未替换正在运行的开发服务。

## 最近重要变更

- 仓库任务默认在修改前自动创建按任务命名的分支，验证完成后执行秘密检查、创建 conventional commit，并将任务分支推送到 `origin`；用户明确要求留在当前分支或仅保留本地时除外。规则记录于 `AGENTS.md`。
- 新任务应读取 `AGENTS.md`、`docs/PROJECT.md`、`docs/STATUS.md`，涉及长期约束时读取 `docs/DECISIONS.md`。
- `docs/` 下文件是新任务的规范上下文；根目录旧文档暂时保留为历史参考。
- 远端数据库标准名称为 `damumu`。
- 用户可见的服务器错误必须经过清洗，并使用统一、可重试的内容区状态呈现。

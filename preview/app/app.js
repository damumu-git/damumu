/* Route inventory follows Flutter screens and user-visible sheets, not API endpoints. */
(() => {
  const P = window.Preview,
    {
      button: b,
      link: l,
      badge,
      field: f,
      area,
      select: s,
      check,
      toggle,
      avatar: a,
      note,
      panel,
      menu,
      scene,
    } = P;
  const source = "app/lib/main.dart";
  const route = (
    id,
    title,
    group,
    widget,
    description = "",
    placeholder = false,
    file = source,
  ) => ({
    id,
    title,
    group,
    source: `${file} · ${widget}`,
    description,
    placeholder,
  });
  const routes = [
    route("home", "首页", "发现与报名", "HomePage"),
    route("discover", "发现活动", "发现与报名", "DiscoverPage"),
    route(
      "map",
      "地图视图",
      "发现与报名",
      "MapPlaceholder",
      "当前地图为示意占位，尚非真实地图。",
      true,
    ),
    route(
      "location",
      "位置与地区选择",
      "发现与报名",
      "_showLocationOptions / _ManualLocationSheet",
    ),
    route("home-notice", "首页提醒", "发现与报名", "_showNotice"),
    route("event", "活动详情", "发现与报名", "EventDetailPage"),
    route("apply", "报名申请", "发现与报名", "_EventDetailPageState._join"),
    route("join-result", "报名结果", "发现与报名", "_showJoinResult"),
    route("leave", "退出活动确认", "发现与报名", "_EventDetailPageState"),
    route(
      "public-profile",
      "公开用户资料",
      "发现与报名",
      "PublicUserProfilePage",
    ),
    route(
      "create-basic",
      "发布 · 基本信息",
      "发布与管理",
      "CreateEventPage._basic",
    ),
    route(
      "create-schedule",
      "发布 · 时间地点",
      "发布与管理",
      "CreateEventPage._schedule",
    ),
    route(
      "create-rules",
      "发布 · 费用与规则",
      "发布与管理",
      "CreateEventPage._rules",
    ),
    route(
      "copy-event",
      "从过往活动发布",
      "发布与管理",
      "_chooseSource / MyActivitiesPage",
    ),
    route(
      "cover-crop",
      "封面选择与裁剪",
      "发布与管理",
      "EventCoverImage / WebCropperLayout",
      "本地选图可预览；此稿仅模拟裁剪区域，不代替生产图片处理。",
      false,
      "app/lib/event_cover_image.dart",
    ),
    route(
      "unsaved",
      "未保存退出确认",
      "发布与管理",
      "CreateEventPage._confirmLeave",
    ),
    route("my-activities", "我的活动", "发布与管理", "MyActivitiesPage"),
    route(
      "activity-record",
      "活动参与记录",
      "发布与管理",
      "_MyActivityRecordPage",
    ),
    route(
      "organizer",
      "组织者管理详情",
      "发布与管理",
      "_MyActivityRecordPage / _OrganizerApplications",
    ),
    route(
      "cancel-event",
      "取消活动",
      "发布与管理",
      "_MyActivityRecordPage._cancelEvent",
    ),
    route(
      "feedback",
      "活动后喜欢与举报",
      "发布与管理",
      "FeedbackActionGrid / FeedbackTagDialog",
      "已结束活动的参与者反馈。",
      false,
      "app/lib/feedback.dart",
    ),
    route("messages", "消息中心", "聊天与通知", "MessagesPage"),
    route("notification", "通知详情", "聊天与通知", "NotificationDetailPage"),
    route("chat", "会话聊天", "聊天与通知", "ChatPage"),
    route(
      "chat-readonly",
      "只读活动群",
      "聊天与通知",
      "ChatPage / group lifecycle",
    ),
    route("message-actions", "消息操作", "聊天与通知", "_showMessageActions"),
    route("message-report", "举报消息", "聊天与通知", "ChatPage._report"),
    route("chat-image", "聊天图片预览", "聊天与通知", "ChatImagePreviewPage"),
    route(
      "chat-attachment",
      "拍照与相册",
      "聊天与通知",
      "ChatPage._chooseChatImageSource",
    ),
    route(
      "conversation-remove",
      "退出群聊 / 隐藏会话",
      "聊天与通知",
      "MessagesPage / ChatPage",
    ),
    route("profile", "我的", "账号与个人中心", "ProfilePage"),
    route(
      "login",
      "邮箱登录",
      "账号与个人中心",
      "AuthPage",
      "",
      false,
      "app/lib/auth.dart",
    ),
    route(
      "register",
      "注册账号",
      "账号与个人中心",
      "AuthPage",
      "",
      false,
      "app/lib/auth.dart",
    ),
    route(
      "avatar",
      "头像编辑",
      "账号与个人中心",
      "showAvatarEditor",
      "",
      false,
      "app/lib/auth.dart",
    ),
    route(
      "avatar-crop",
      "头像裁剪与确认",
      "账号与个人中心",
      "cropAndUploadAvatar",
      "",
      false,
      "app/lib/auth.dart",
    ),
    route(
      "avatar-preview",
      "头像全屏预览",
      "账号与个人中心",
      "AvatarPreviewPage",
      "",
      false,
      "app/lib/activity_interactions.dart",
    ),
    route(
      "settings",
      "设置",
      "账号与个人中心",
      "_ProfileInfoPage",
      "当前设置入口为说明页；实际语言、隐私等操作在“我的”。",
      true,
    ),
    route(
      "language",
      "语言选择",
      "账号与个人中心",
      "_showLanguagePicker",
      "预览以中文呈现；正式 App 支持中英韩。",
    ),
    route(
      "external",
      "通知与外部处理",
      "账号与个人中心",
      "ExternalProcessingSettings",
      "当前发布开关关闭，外部推送及地理编码不可启用。",
      false,
      "app/lib/external_processing.dart",
    ),
    route(
      "privacy",
      "隐私政策入口",
      "账号与个人中心",
      "_openPrivacyPolicy",
      "正式 App 打开外部政策网页；此处展示入口和保留摘要。",
    ),
    route(
      "delete-account",
      "注销账号确认",
      "账号与个人中心",
      "_confirmAccountDeletion",
    ),
    route("logout", "退出登录", "账号与个人中心", "AuthController.logout"),
    route(
      "trust",
      "信誉与评价",
      "说明与安全",
      "_ProfileInfoPage",
      "该入口当前为说明页；保留现有能力边界。",
      true,
    ),
    route(
      "blocks",
      "屏蔽与举报记录",
      "说明与安全",
      "_ProfileInfoPage",
      "该入口当前为说明页，未展示真实处理记录。",
      true,
    ),
    route("help", "帮助与社区规则", "说明与安全", "_ProfileInfoPage"),
    route(
      "safety",
      "安全中心",
      "说明与安全",
      "SafetyCenterPage",
      "当前安全会面为本地演示，联系人通知与位置分享尚未接通。",
      true,
    ),
    route(
      "emergency",
      "紧急帮助",
      "说明与安全",
      "_showEmergency",
      "仅展示现有操作入口，不发送通知、不分享位置。",
      true,
    ),
  ];
  const eventData = [
    {
      title: "汉江日落，和新朋友慢慢走",
      category: "户外 · 散步",
      area: "首尔 · 永登浦区",
      time: "10月31日 周六 · 16:30",
      face: "🐻",
      host: "小林",
      count: "4 / 6",
      kind: 0,
      price: "预计 ₩5,000 / 人",
    },
    {
      title: "周末咖啡，聊聊最近的生活",
      category: "社交 · 咖啡",
      area: "首尔 · 麻浦区",
      time: "11月1日 周日 · 14:00",
      face: "🐱",
      host: "安安",
      count: "3 / 5",
      kind: 1,
      price: "预计 ₩8,000 / 人",
    },
    {
      title: "轻徒步，去山里呼吸一下",
      category: "运动 · 徒步",
      area: "首尔 · 恩平区",
      time: "11月7日 周六 · 09:00",
      face: "🦉",
      host: "阿树",
      count: "5 / 8",
      kind: 2,
      price: "免费",
    },
  ];
  let avatarReturn = "profile";
  let selected = 0,
    detailStatus = "未报名",
    messageTab = "活动群",
    activityTab = "我参加的",
    discoverTab = "全部",
    feedFilter = "全部",
    search = "",
    messages = [],
    safeActive = false,
    feedbackTag = "友善",
    capacity = 6;
  let draft = {
    title: "汉江日落，和新朋友慢慢走",
    description: "带上一点零食，沿着汉江走走，看看日落。欢迎第一次参加的朋友。",
    start: "2026-10-31T16:30",
    end: "2026-10-31T18:30",
    meeting: "示例集合点（仅预览）",
    price: "5000",
    note: "",
  };
  const heading = (title, back = "home") =>
    `<header class="app-heading">${l("‹", back)}<h2>${title}</h2>${l("⌂", "home", "ghost")}</header>`;
  const stack = (content) => `<div class="stack">${content}</div>`;
  const chips = (items, action, active) =>
    `<div class="chips">${items.map((x, i) => b(x, `${action}:${i}`, x === active ? "active" : "")).join("")}</div>`;
  const draftField = (key, label, type = "text") =>
    f(label, draft[key], type, `data-draft="${key}"`);
  const card = (event, index) =>
    `<article class="event-card" tabindex="0" role="button" aria-label="查看${event.title}" data-action="event:${index}">${scene(event.kind)}<div class="copy"><div class="row between wrap">${badge(event.category)}${badge(index === 0 ? "参与者认证 · 新手友好" : "组织者声明 · 新手友好")}</div><h3>${event.title}</h3><p>${event.time}<br>⌖ ${event.area} · 2.1 km</p><div class="divider"></div><div class="row between"><span class="row">${a(event.face)}<small>${event.host} · ★ 4.8</small></span><small>${event.count} 人</small></div></div></article>`;
  const cards = () =>
    eventData
      .map((e, i) => ({ e, i }))
      .filter(({ e }) => `${e.title} ${e.area}`.includes(search))
      .filter(({ i }) => feedFilter !== "本周末" || i < 2)
      .filter(
        ({ e }) => discoverTab === "全部" || e.category.includes(discoverTab),
      )
      .map(({ e, i }) => card(e, i))
      .join("") || '<p class="empty-search">没有符合条件的示例活动</p>';
  const eventSummary = () =>
    panel(
      "",
      `<div class="row">${a(eventData[selected].face)}<div><h3>${eventData[selected].title}</h3><small>${eventData[selected].time}</small></div></div>`,
    );
  const actions = {};
  function render(id) {
    const e = eventData[selected];
    switch (id) {
      case "home":
        return stack(
          `<div class="row between"><div><span class="eyebrow">DAMUMU · 一起出发</span><h2>今天，想和谁一起？</h2></div>${l("◉", "home-notice", "ghost")}</div>${l("⌖ 首尔 · 永登浦区　⌄", "location", "ghost")}<div class="app-hero"><span class="eyebrow">A LITTLE COMPANY</span><h1>把平常的周末，<br>过成喜欢的样子。</h1><p>附近的小活动，刚刚好的新朋友。</p></div><input type="search" data-feed-search value="${P.esc(search)}" placeholder="搜索活动、地区…" aria-label="搜索活动"><div class="mini-actions">${[
            ["🌿", "户外"],
            ["☕", "社交"],
            ["🏃", "运动"],
            ["🎨", "兴趣"],
          ]
            .map(([icon, title]) =>
              b(`<b>${icon}</b>${title}`, `category:${title}`),
            )
            .join(
              "",
            )}</div>${chips(["全部", "本周末", "新手友好"], "feed", feedFilter)}<div class="section-title"><h3>附近的好时光</h3>${l("发现更多 →", "discover", "ghost")}</div><div id="feed-cards" class="stack">${cards()}</div>`,
        );
      case "discover":
        return stack(
          `${heading("发现活动")}<input type="search" data-feed-search value="${P.esc(search)}" placeholder="搜索活动" aria-label="搜索活动">${chips(["全部", "户外", "社交", "运动"], "discover", discoverTab)}<div class="row between"><small>首尔 · 已加载 3 场示例活动</small>${l("⌖ 地图", "map")}</div><div id="feed-cards" class="stack">${cards()}</div>${note("正式 App 的搜索和筛选作用于已加载活动；此处仅筛选虚构示例。")}`,
        );
      case "map":
        return stack(
          `${heading("附近地图", "discover")}${note("当前正式代码为地图占位，未接入真实地图服务。")}<div class="scene" style="height:330px;background:repeating-linear-gradient(25deg,#e8eee2 0 40px,#fff 41px 46px)"><div style="position:absolute;top:45%;left:35%">${b("⌖ 汉江散步", "event:0", "primary")}</div></div>${card(eventData[0], 0)}`,
        );
      case "location":
        return stack(
          `${heading("选择你的位置")}<h2>发现身边的活动</h2><p class="muted">使用设备定位，或手动选择想探索的地区。</p>${b("使用设备当前位置", "locate", "primary wide")}${s("城市 / 道", ["首尔特别市", "京畿道", "釜山广域市"])}${s("区 / 市", ["永登浦区", "麻浦区", "江南区"])}${b("保存手动地区", "save-location", "primary wide")}${b("清除手动地区", "demo", "wide")}${note("演示不会请求设备定位；正式分类和地区来自 API。")}`,
        );
      case "home-notice":
        return stack(
          `${heading("社区提醒")}<h2>轻松相遇，安全同行</h2><p>参加前确认时间与区域，通过报名后查看集合地点。线下费用由参与者自行承担，请勿提前向陌生人转账。</p>${l("看看附近活动", "home", "primary wide")}`,
        );
      case "event":
        return stack(
          `${heading("活动详情")}${scene(e.kind)}<div class="row wrap">${badge(e.category)}${badge("新手友好")}${badge(detailStatus, "amber")}</div><h1>${e.title}</h1><div class="row between"><div class="row">${a(e.face)}<div><strong>${e.host}</strong><small class="block">组织者 · ★ 4.8 · 获得 12 个喜欢</small></div></div>${l("查看", "public-profile", "ghost")}</div>${panel("活动安排", `<p>◷ ${e.time}<br>⌖ ${e.area}<br>♧ ${e.count} 人（含组织者）<br>₩ ${e.price}</p>`)}${panel("集合地点", detailStatus === "已通过" ? "<p>示例集合点 · 公园入口（虚构地点）</p>" : note("通过报名后可查看精确集合地点。"))}${panel("一起度过一个轻松的下午", `<p>${P.esc(draft.description)}</p><div class="divider"></div><small>组织者声明与参与者认证分别展示；平台不收取活动费用，也不提供支付担保。</small>`)}${panel("同行伙伴", `<div class="row">${a("🐻")}${a("🐱")}${a("🦉")}${l("查看成员", "public-profile", "ghost")}</div>`)}${s("预览参与身份", ["未报名", "待审核", "已通过", "候补中", "已拒绝", "活动已结束", "活动已取消"]).replace("<select>", "<select data-participation>")}${detailStatus === "未报名" ? l("申请参加", "apply", "primary wide") : detailStatus === "已通过" ? `${l("进入活动群", "chat", "primary wide")}${l("退出活动", "leave", "wide")}` : detailStatus === "活动已结束" ? l("喜欢 / 举报", "feedback", "primary wide") : note(`${detailStatus} · ${detailStatus === "待审核" ? "请等待组织者处理申请。" : "当前状态不可重复申请。"}`)}`,
        );
      case "apply":
        return stack(
          `${heading("申请参加", "event")}${eventSummary()}<h2>和组织者打个招呼</h2><form class="stack" data-form="apply">${area("申请备注（选填）", "你好，第一次参加，很期待一起看日落！")}${note("申请不计入已通过人数。通过审核后可见集合点，并加入活动群聊。")}<button type="submit" class="primary wide">提交申请</button></form>`,
        );
      case "join-result":
        return stack(
          `${heading("报名结果", "event")}<div class="state-card"><div class="state-icon">✓</div><h2>申请已提交</h2><p>预览中的申请正在等待组织者审核。正式服务会通过站内通知同步结果。</p>${l("返回活动详情", "event", "primary")}</div>`,
        );
      case "leave":
        return stack(
          `${heading("退出活动", "event")}${eventSummary()}${note("退出后将失去活动群聊和精确集合地点访问资格。当前业务不支持退出后再次申请。")}${b("确认退出（模拟）", "leave-confirm", "danger wide")}`,
        );
      case "public-profile":
        return stack(
          `${heading("用户资料", "event")}<div style="text-align:center">${b(a(e.face, true), "avatar-preview", "ghost")}<h2>${e.host}</h2><p style="color:#b65a6c">❤ 12</p></div><div class="row wrap" style="justify-content:center">${badge("友善")}${badge("守时")}${badge("新人友好")}</div>${panel("活动后的相遇反馈", `${l("喜欢 / 举报同场成员", "feedback", "wide")}<small>仅携带活动上下文且符合反馈资格时显示。</small>`)}${note("公开展示头像、昵称、喜欢数与高频正向标签，不展示邮箱或原始举报数量。")}`,
        );
      case "create-basic":
        return stack(
          `${heading("发布活动")}<span class="eyebrow">STEP 01 / 03</span><h1>先介绍一下活动</h1><p class="muted">清晰的主题，更容易找到合适的搭子。</p>${l("↗ 从过往活动中发布", "copy-event", "wide")}${draftField("title", "活动名称")}${l(scene(0) + "<small>选择 / 更换封面 · 4:3</small>", "cover-crop", "wide")}${chips(["🌿 户外", "☕ 社交", "🏃 运动", "🎨 兴趣", "其它"], "major", "🌿 户外")}${s("小分类", ["散步", "野餐", "其它"])}${f("其它小分类名称（选填）", "", "text", 'maxlength="15"')}${area("活动介绍", draft.description).replace("<textarea>", '<textarea data-draft="description">')}${l("下一步 · 时间地点", "create-schedule", "primary wide")}${l("退出编辑", "unsaved", "ghost wide")}`,
        );
      case "create-schedule":
        return stack(
          `${heading("时间与集合点", "create-basic")}<span class="eyebrow">STEP 02 / 03</span><h1>约一个好时间</h1>${draftField("start", "开始时间", "datetime-local")}${draftField("end", "结束时间", "datetime-local")}${s("城市 / 道", ["首尔特别市", "京畿道"])}${s("区 / 市", ["永登浦区", "麻浦区"])}${draftField("meeting", "精确集合点")}${note("公开页面只展示地区；通过审核的成员才可查看精确集合点。")}<div class="grid2">${l("上一步", "create-basic")}${l("下一步", "create-rules", "primary")}</div>`,
        );
      case "create-rules":
        return stack(
          `${heading("费用与规则", "create-schedule")}<span class="eyebrow">STEP 03 / 03</span><h1>刚刚好的一小群人</h1>${draftField("price", "预计线下人均费用（₩）", "number")}${note("0 表示免费。平台不收款，不提供支付、转账或资金担保。")}${panel("人数上限", `<div class="row between"><small>包含组织者本人</small><div class="row">${b("−", "capacity-minus")}<strong id="capacity">${capacity}</strong>${b("＋", "capacity-plus")}</div></div>`)}${s("报名方式", ["需要组织者审核", "直接加入"])}${toggle("组织者声明 · 适合新手", true)}<small>组织者声明不等于“参与者认证”。</small>${note("发布即代表同意社区规范。新活动直接发布，无需后台预审。")}${b("发布活动（模拟）", "publish", "primary wide")}`,
        );
      case "copy-event":
        return stack(
          `${heading("从过往活动发布", "create-basic")}<p class="muted">复用内容，重新选择开始和结束时间。</p>${eventData.map((e, i) => panel("", `<h3>${e.title}</h3><small>${e.area}</small><div style="margin-top:14px">${b("使用此活动", `copy:${i}`, "primary")}</div>`)).join("")}`,
        );
      case "cover-crop":
        return stack(
          `${heading("活动封面", "create-basic")}<h2>选一张有氛围的封面</h2><input type="file" accept="image/*" data-local-image aria-label="选择本地封面"><div id="local-image" class="scene" style="height:240px">${scene(0)}</div><div class="row">${b("水平翻转", "flip")}${b("旋转", "rotate")}${b("移除", "remove-image")}</div>${note("固定 4:3 · 正式 App 输出 1280×960 JPEG、最多 1.5 MB。此预览仅展示选图和调整界面。")}${l("使用此封面", "create-basic", "primary wide")}`,
        );
      case "unsaved":
        return stack(
          `${heading("离开发布页", "create-basic")}<h2>还有未保存的内容</h2><p>离开后本次编辑不会发布。是否继续编辑？</p>${l("继续编辑", "create-basic", "primary wide")}${l("放弃并返回首页", "home", "danger wide")}`,
        );
      case "my-activities":
        return stack(
          `${heading("我的活动", "profile")}${chips(["我参加的", "我发布的"], "activities", activityTab)}${eventData.map((e, i) => panel("", `<div class="row between">${badge(i === 2 ? "已完成" : "已通过", i === 2 ? "" : "amber")}<small>${e.time}</small></div><h3 style="margin:12px 0">${e.title}</h3><div class="row">${l(activityTab === "我发布的" ? "管理详情" : "参与记录", activityTab === "我发布的" ? "organizer" : "activity-record", "primary")}${b("发布同类活动", `copy:${i}`)}</div>`)).join("")}`,
        );
      case "activity-record":
        return stack(
          `${heading("参与记录", "my-activities")}${eventSummary()}${badge("已完成")}${panel("我的报名", `<p>参与者：小慕<br>状态：已参加<br>申请备注：期待认识新朋友。</p>`)}${l("查看活动", "event", "wide")}${l("发布同类活动", "copy-event", "wide")}${l("喜欢 / 举报", "feedback", "primary wide")}`,
        );
      case "organizer":
        return stack(
          `${heading("管理详情", "my-activities")}${eventSummary()}${panel("成员与申请", `<div class="row between"><span>已通过 4 / 6</span>${badge("待审核 2")}</div><div class="divider"></div>${["小雨", "阿禾"].map((name, i) => `<div class="stack" style="margin-bottom:20px"><div class="row">${a(i ? "🐱" : "🦉")}<div class="grow">${l(name, "public-profile", "ghost")}<small class="block">10月26日 14:20 · 想来认识新朋友</small></div></div><div class="row">${b("通过", `approve:${i}`, "primary")}${b("拒绝", `reject:${i}`)}</div></div>`).join("")}`)}${l("进入活动群", "chat", "wide")}${l("发布同类活动", "copy-event", "wide")}${l("取消活动", "cancel-event", "danger wide")}`,
        );
      case "cancel-event":
        return stack(
          `${heading("取消活动", "organizer")}${eventSummary()}<form data-form="cancel" class="stack">${area("取消原因（必填，最多 500 字）").replace("<textarea>", '<textarea required maxlength="500">')}${note("正式服务取消后立即将活动群设为只读，并通知成员。")}<button type="submit" class="danger wide">确认取消（模拟）</button></form>`,
        );
      case "feedback":
        return stack(
          `${heading("活动后反馈", "activity-record")}${eventSummary()}<h2>谢谢这一次相遇</h2>${s("评价对象", ["活动组织者", "同场成员 · 小雨"])}${chips(["友善", "守时", "新人友好", "沟通顺畅"], "feedback", feedbackTag)}${b("送出喜欢", "like", "primary wide")}${panel("需要反馈问题？", `${s("举报标签", ["爽约", "不当言论", "骚扰", "其他"])}${area("补充说明")}${b("提交举报（模拟）", "report", "danger wide")}`)}${note("仅同场已通过 / 已签到成员在活动结束后提交；每个对象只允许一次。举报人和原始举报数不公开。")}`,
        );
      case "messages":
        return stack(
          `${heading("消息")}${chips(["活动群", "私信", "通知"], "messages", messageTab)}<div class="row between"><small>2 条未读</small>${b("全部已读", "read-all", "ghost")}</div>${messageTab === "通知" ? `${menu("报名申请已通过", "现在可以查看集合点并进入活动群。", "notification")}${menu("搭慕社区公告", "周末活动参与提醒", "notification")}` : messageTab === "私信" ? `${menu("🐱 安安", "这周末一起去喝咖啡吗？ · 12:20", "chat")}` : `${menu("🌿 汉江日落散步群", "小林：大家周六见！ · 2 条未读", "chat")}${menu("☕ 周末咖啡局", "活动已结束 · 群聊只读", "chat-readonly")}`}${l("列表项操作 / 退出群聊", "conversation-remove", "ghost wide")}`,
        );
      case "notification":
        return stack(
          `${heading("通知详情", "messages")}${badge("活动通知")}<h1>你的报名申请已通过</h1><small>10月26日 · 14:30</small><p>组织者通过了你的活动申请。你现在可以查看精确集合地点，并在活动群里与伙伴交流。</p>${b("查看活动", "notification-event", "primary wide")}`,
        );
      case "chat":
      case "chat-readonly":
        return stack(
          `${heading("汉江日落散步群", "messages")}${l("查看活动 · 4 位同行伙伴 →", "event", "soft wide")}${id === "chat-readonly" ? note("活动结束超过 7 天，群聊只读；内容在规定的 3 个自然月期限届满后删除。") : ""}<small style="text-align:center">10月26日 · 14:30</small><div class="chat-item">${a("🐻")}<div><small>小林 · 组织者</small><div class="chat-bubble" data-route="message-actions">大家好，周六见！沿江走一小段，等一场日落。</div></div></div><div class="chat-bubble mine" data-route="message-actions">好呀！我会带一点零食。</div><div class="chat-item">${a("🐱")}<div class="chat-bubble">${l(scene(0), "chat-image", "ghost wide")}<small>点开查看图片</small></div></div><div id="new-messages" class="stack">${messages.map((x) => `<div class="chat-bubble mine">${P.esc(x)}</div>`).join("")}</div>${id === "chat-readonly" ? '<p class="muted" style="text-align:center">当前会话不可发送消息</p>' : `<form data-form="chat" class="row">${l("＋", "chat-attachment")}<input name="message" required aria-label="消息内容" placeholder="说点什么…"><button type="submit" class="primary">发送</button></form>`}${l("会话操作", "conversation-remove", "ghost wide")}`,
        );
      case "message-actions":
        return stack(
          `${heading("消息操作", "chat")}${panel("", '<div class="chat-bubble">好呀！我会带一点零食。</div>')}${b("回复此消息", "reply", "wide")}${b("编辑消息（发送后 15 分钟内）", "edit-message", "wide")}${b("撤回消息（发送后 5 分钟内）", "recall", "wide")}${l("举报消息", "message-report", "danger wide")}`,
        );
      case "message-report":
        return stack(
          `${heading("举报消息", "chat")}${s("举报原因", ["骚扰", "不当内容", "诈骗", "其他"])}${area("补充说明")}${note("正式服务会保存被举报消息及相邻上下文快照，按举报提交起保留 3 个自然月。")}${b("提交举报（模拟）", "report", "danger wide")}`,
        );
      case "chat-image":
        return stack(
          `${heading("图片预览", "chat")}<div class="image-zoom">${scene(0)}<small>图片缩放界面示意</small></div><label class="field">缩放<input type="range" min="100" max="180" value="100" data-zoom></label>${note("正式聊天图片需要登录且具有会话权限，预览使用本地插画，不读取私密媒体。")}`,
        );
      case "chat-attachment":
        return stack(
          `${heading("添加图片", "chat")}<label class="field">相册选图<input type="file" accept="image/*" data-local-image></label><div id="local-image" class="scene">${scene(0)}</div>${b("拍照", "camera", "wide")}${b("发送图片（模拟）", "send-image", "primary wide")}${note("正式 App 在设备端压缩为最长边 1600px、目标 1.5 MB 的 JPEG。此预览不请求相机权限。")}`,
        );
      case "conversation-remove":
        return stack(
          `${heading("会话管理", "messages")}${b("标记已读", "read-all", "wide")}${b("从个人列表隐藏", "hide-conversation", "wide")}${note("隐藏列表项与删除聊天内容不同；退出群聊后将不能继续访问该会话。")}${b("退出活动群（模拟）", "exit-group", "danger wide")}`,
        );
      case "profile":
        return stack(
          `<div class="row between"><h1>我的</h1>${l("⚙", "settings", "ghost")}</div>${panel(
            "",
            `<div class="row">${b(a("🐻", true), "avatar-preview", "ghost")}<div class="grow"><h2>小慕</h2><small>preview@example.invalid</small></div>${l("编辑", "avatar", "ghost")}</div><div class="divider"></div><div class="stats">${[
              ["4.8", "信誉"],
              ["12", "参加"],
              ["3", "组织"],
              ["96%", "出席"],
            ]
              .map(
                ([v, k]) =>
                  `<div><strong>${v}</strong><small>${k}</small></div>`,
              )
              .join("")}</div>`,
          )}<div class="app-hero" data-route="safety" role="button" tabindex="0"><span class="eyebrow">CARE FOR EACH OTHER</span><h2>安全中心　→</h2><p>安心见面，从多一点准备开始</p></div>${panel("", `${menu("我的活动", "查看我发布和参加的活动", "my-activities")}${menu("信誉与评价", "守时 · 友善 · 沟通顺畅", "trust")}${menu("屏蔽与举报", "", "blocks")}`)}${panel("", `${menu("帮助与规则", "", "help")}${menu("隐私与账号", "", "privacy")}${menu("通知与外部处理", "当前外部服务默认停用", "external")}${menu("语言", "简体中文", "language")}${menu("注销账号", "", "delete-account")}${menu("退出登录", "", "logout")}`)}`,
        );
      case "login":
      case "register":
        return stack(
          `<div style="text-align:center;padding:15px 0"><span class="eyebrow">DAMUMU · LITTLE MOMENTS</span><h1>${id === "register" ? "从这里，遇见搭子" : "欢迎回来"}</h1><p class="muted">一起发现生活里的小美好</p></div><form data-form="auth" class="stack">${id === "register" ? `${b("🐻　🐱　🦉　选择系统头像", "register-avatar", "wide")}${f("昵称", "", "text", 'required minlength="2"')}` : ""}${f("邮箱", "", "email", 'required placeholder="you@example.com"')}${f("密码", "", "password", 'required minlength="8" placeholder="至少 8 位，包含字母和数字"')}${id === "register" ? `${check("我确认已满14岁").replace('type="checkbox"', 'type="checkbox" required')}${check("我已阅读当前隐私政策").replace('type="checkbox"', 'type="checkbox" required')}${l("阅读隐私政策", "privacy", "ghost")}` : ""}<button type="submit" class="primary wide">${id === "register" ? "创建账号（模拟）" : "登录（模拟）"}</button></form>${l(id === "register" ? "已有账号？登录" : "还没有账号？注册", id === "register" ? "login" : "register", "ghost wide")}${note("仅用于设计预览，请勿输入真实密码。")}`,
        );
      case "avatar":
        return stack(
          `${heading("选择头像", "profile")}<h2>选一个喜欢的自己</h2><div class="grid3">${["🐻", "🐱", "🦉", "🐰", "🦊", "🐳"].map((face) => b(a(face, true), "pick-avatar")).join("")}</div>${l("从设备选择照片", "avatar-crop", "wide")}${b("保存头像（模拟）", "save-avatar", "primary wide")}`,
        );
      case "avatar-crop":
        return stack(
          `${heading("编辑头像", "avatar")}<input type="file" accept="image/*" data-local-image aria-label="选择本地头像"><div id="local-image" class="scene" style="width:240px;height:240px;border-radius:50%;margin:auto">${scene(1)}</div>${b("水平翻转", "flip")}${note("头像处理界面示意。正式输出为 512×512 JPEG，固定 1:1 裁剪。")}${l("确认并预览头像", "avatar", "primary wide")}`,
        );
      case "avatar-preview":
        return stack(
          `${heading("头像预览", "profile")}<div style="text-align:center;padding:50px 0;background:var(--soft);border-radius:var(--radius)"><span style="font-size:150px">🐻</span></div>${l("关闭预览", "profile", "wide")}`,
        );
      case "settings":
        return stack(
          `${heading("设置", "profile")}<div class="placeholder">当前正式页面是设置说明：账号、通知、隐私和语言设置可以在这里统一管理。实际设置入口位于“我的”。</div>${l("返回个人中心", "profile", "primary wide")}`,
        );
      case "language":
        return stack(
          `${heading("选择语言", "profile")}${["简体中文", "English", "한국어"].map((x, i) => `<label class="panel check"><input type="radio" name="language" ${i === 0 ? "checked" : ""}>${x}</label>`).join("")}${b("确认选择", "language-save", "primary wide")}${note("本预览仅维护中文设计稿；正式 App 的文案通过 l10n.dart 提供三语。")}`,
        );
      case "external":
        return stack(
          `${heading("通知与外部处理", "profile")}${note("完整外部处理告知核定前，系统推送及外部地理编码默认停用。站内消息不受影响。")}${panel("可选功能", `${toggle("系统推送", false, true)}<div class="divider"></div>${toggle("外部地理编码", false, true)}`)}${l("阅读隐私政策", "privacy", "wide")}`,
        );
      case "privacy":
        return stack(
          `${heading("隐私与账号", "profile")}<h2>你的资料与内容</h2><p>最低注册年龄14岁。注销后立即清除账号资料与凭据；必要关联内容按既定期限保留。</p>${panel("保留期限", "<p>聊天：发送起3个自然月。<br>活动及群聊：最终结束或取消起3个自然月。<br>举报及证据：提交起3个自然月。</p>")}${note("此处是预览摘要，完整中韩政策以正式网站为准；不会在离线预览中自动访问外部网站。")}<p><code>www.damumu.com/privacy.html</code><br><code>www.damumu.com/privacy-ko.html</code></p>${l("注销账号", "delete-account", "danger wide")}`,
        );
      case "delete-account":
        return stack(
          `${heading("注销账号", "profile")}<h1>确定要离开搭慕吗？</h1><p>正式服务会立即撤销登录凭据、清除个人资料与头像。仍需有限期保留的内容将显示默认头像和“注销用户_数字”。</p>${note("这不是即时删除所有聊天、活动或举报的承诺；相关内容按既定3个自然月期限清理。")}${check("我了解注销后无法恢复账号").replace('type="checkbox"', 'type="checkbox" data-delete-check')}${b("确认注销（模拟）", "delete-confirm", "danger wide")}${l("暂不注销", "profile", "wide")}`,
        );
      case "logout":
        return stack(
          `${heading("退出登录", "profile")}<h2>要退出当前账号吗？</h2><p>正式 App 会停止当前消息连接并清理该账号的聊天及图片缓存。</p>${l("确认退出（模拟）", "login", "primary wide")}${l("返回", "profile", "wide")}`,
        );
      case "trust":
        return stack(
          `${heading("信誉与评价", "profile")}<div class="placeholder">现有说明页：参加活动并完成签到后，可提交信誉评价。此入口尚未接入评价记录接口。活动后的喜欢与举报有独立入口。</div>${l("查看活动后反馈", "feedback", "wide")}`,
        );
      case "blocks":
        return stack(
          `${heading("屏蔽与举报", "profile")}<div class="placeholder">当前入口为说明页，屏蔽列表和处理进度尚未接通。此预览不虚构已完成记录。</div>${l("查看消息举报界面", "message-report", "wide")}`,
        );
      case "help":
        return stack(
          `${heading("帮助与社区规则", "profile")}${panel("参加活动前", "<p>确认时间、地区和预计线下费用。不要向陌生人提前转账，通过审核后核对集合点。</p>")}${panel("友好相处", "<p>尊重他人边界，守时沟通。禁止商业导流、歧视、危险和违法活动。</p>")}${l("安全中心", "safety", "primary wide")}`,
        );
      case "safety":
        return stack(
          `${heading("安全中心", "profile")}${note("现有安全会面仅本地演示；真实联系人通知、位置分享及逾时提醒尚未接通。")}<div class="app-hero"><span class="eyebrow">SAFETY FIRST</span><h1>${safeActive ? "安全会面进行中" : "开启安全会面"}</h1><p>按时确认状态，做好见面准备。</p><div style="margin-top:20px">${b(safeActive ? "我现在安全 · 完成确认" : "开始设置", "safety-toggle", "wide")}</div></div>${s("确认频率", ["30 分钟", "60 分钟", "90 分钟"])}${panel("紧急联系人", "<p>示例联系人 · 010••••0000</p><small>仅界面示意，尚不可实际编辑或通知。</small>")}${panel("", `${b("位置分享 · 尚未接通", "placeholder", "wide")}${b("紧急分享模板 · 尚未接通", "placeholder", "wide")}`)}${l("需要紧急帮助", "emergency", "danger wide")}<small>本功能不是救援服务。如面临即时危险，请联系当地紧急服务。</small>`,
        );
      case "emergency":
        return stack(
          `${heading("紧急帮助", "safety")}<h2>先确保自己的安全</h2><p>若正处于危险中，请优先联系当地紧急服务。</p>${b("通知紧急联系人并分享位置", "placeholder", "danger wide")}${note("当前正式入口尚未接通通知与位置分享。预览不会联系任何人。")}`,
        );
      default:
        throw new Error(`Unmapped app route: ${id}`);
    }
  }
  actions.locate = ({ toast }) => toast("定位界面演示：不会请求设备定位权限。");
  actions["save-location"] = ({ go, toast }) => {
    toast("已保存示例地区");
    go("home");
  };
  actions["leave-confirm"] = ({ go, toast }) => {
    detailStatus = "已退出";
    toast();
    go("event");
  };
  actions.publish = ({ go, toast }) => {
    if (
      !draft.title.trim() ||
      !draft.start ||
      !draft.end ||
      new Date(draft.end) <= new Date(draft.start)
    ) {
      toast("请填写名称，以及结束晚于开始的日期时间。");
      return;
    }
    detailStatus = "已通过";
    toast("预览发布成功，未创建真实活动");
    go("organizer");
  };
  actions["notification-event"] = ({ go }) => {
    detailStatus = "已通过";
    go("event");
  };
  actions["avatar-preview"] = ({ go }) => go("avatar-preview");
  actions["pick-avatar"] = ({ target, toast }) => {
    target.parentElement
      .querySelectorAll("button")
      .forEach((el) => el.classList.remove("primary"));
    target.classList.add("primary");
    toast("已选择示例头像");
  };
  actions["save-avatar"] = ({ go, toast }) => {
    toast("头像选择已模拟保存");
    go(avatarReturn);
  };
  actions["register-avatar"] = ({ go }) => {
    avatarReturn = "register";
    go("avatar");
  };
  actions["language-save"] = ({ go, toast }) => {
    toast("已演示语言选择；预览文案仍为中文");
    go("profile");
  };
  actions["delete-confirm"] = ({ toast, go }) => {
    if (!document.querySelector("[data-delete-check]")?.checked) {
      toast("请先确认已了解注销影响");
      return;
    }
    toast("仅模拟注销，不影响真实账号");
    go("login");
  };
  actions["safety-toggle"] = ({ draw }) => {
    safeActive = !safeActive;
    draw();
  };
  actions.placeholder = ({ toast }) =>
    toast("现有代码尚未接通该功能，此处仅展示界面。");
  actions["send-image"] = ({ go, toast }) => {
    toast("图片发送界面已模拟，未上传任何文件");
    go("chat");
  };
  actions.camera = ({ toast }) => toast("拍照入口演示，不会请求相机权限。");
  actions.like = ({ toast }) => toast(`已模拟送出“${feedbackTag}”喜欢`);
  actions.report = ({ go, toast }) => {
    toast("举报已模拟提交，未向服务器发送内容");
    go("activity-record");
  };
  actions["read-all"] = ({ toast, target }) => {
    target.textContent = "已全部读完";
    toast();
  };
  actions["hide-conversation"] = ({ go, toast }) => {
    toast("已模拟隐藏列表项");
    go("messages");
  };
  actions["exit-group"] = ({ go, toast }) => {
    toast("已模拟退出群聊");
    go("messages");
  };
  actions.reply = ({ go, toast }) => {
    toast("已选择回复示例消息");
    go("chat");
  };
  actions["edit-message"] = ({ modal }) =>
    modal(
      "编辑消息",
      area("消息内容", "好呀！我会带一点零食。"),
      "保存（模拟）",
      () => P.toast("已模拟编辑消息"),
    );
  actions.recall = ({ modal, go }) =>
    modal("撤回消息", "<p>确认撤回这条消息？</p>", "撤回（模拟）", () => {
      P.toast();
      go("chat");
    });
  for (const action of ["flip", "rotate", "remove-image"])
    actions[action] = ({ toast }) => {
      const img = document.querySelector("#local-image img");
      if (img) {
        if (action === "remove-image") img.remove();
        else
          img.style.transform =
            action === "flip" ? "scaleX(-1)" : "rotate(90deg)";
      }
      toast("仅预览图片显示调整，未执行正式裁剪或上传");
    };
  for (const [prefix, values, set] of [
    [
      "feed",
      ["全部", "本周末", "新手友好"],
      (x) => {
        feedFilter = x;
      },
    ],
    [
      "discover",
      ["全部", "户外", "社交", "运动"],
      (x) => {
        discoverTab = x;
      },
    ],
    [
      "messages",
      ["活动群", "私信", "通知"],
      (x) => {
        messageTab = x;
      },
    ],
    [
      "activities",
      ["我参加的", "我发布的"],
      (x) => {
        activityTab = x;
      },
    ],
    [
      "feedback",
      ["友善", "守时", "新人友好", "沟通顺畅"],
      (x) => {
        feedbackTag = x;
      },
    ],
  ])
    values.forEach((v, i) => {
      actions[`${prefix}:${i}`] = ({ draw }) => {
        set(v);
        draw();
      };
    });
  ["🌿 户外", "☕ 社交", "🏃 运动", "🎨 兴趣", "其它"].forEach((_, i) => {
    actions[`major:${i}`] = ({ target }) => {
      target.parentElement
        .querySelectorAll("button")
        .forEach((x) => x.classList.remove("active"));
      target.classList.add("active");
    };
  });
  ["户外", "社交", "运动", "兴趣"].forEach((x) => {
    actions[`category:${x}`] = ({ go }) => {
      discoverTab = x;
      go("discover");
    };
  });
  eventData.forEach((_, i) => {
    actions[`event:${i}`] = ({ go }) => {
      selected = i;
      go("event");
    };
    actions[`copy:${i}`] = ({ go, toast }) => {
      selected = i;
      draft.title = eventData[i].title;
      draft.start = "";
      draft.end = "";
      toast("已复用示例活动内容，请重新选择时间");
      go("create-basic");
    };
  });
  ["capacity-minus", "capacity-plus"].forEach((key) => {
    actions[key] = () => {
      capacity = Math.max(2, capacity + (key.endsWith("minus") ? -1 : 1));
      document.getElementById("capacity").textContent = capacity;
    };
  });
  [0, 1].forEach((i) => {
    actions[`approve:${i}`] = ({ target, toast }) => {
      target.parentElement.innerHTML = badge("已通过");
      toast("申请已模拟通过");
    };
    actions[`reject:${i}`] = ({ modal, target }) =>
      modal("拒绝申请", area("拒绝原因"), "确认拒绝（模拟）", () => {
        target.parentElement.innerHTML = badge("已拒绝", "red");
        P.toast();
      });
  });
  const runtime = P.boot({ kind: "app", routes, render, actions });
  document.addEventListener("input", (e) => {
    if (e.target.dataset.draft) draft[e.target.dataset.draft] = e.target.value;
    if (e.target.matches("[data-feed-search]")) {
      search = e.target.value;
      document.getElementById("feed-cards").innerHTML = cards();
    }
    if (e.target.matches("[data-zoom]"))
      document.querySelector(".image-zoom .scene").style.transform =
        `scale(${Number(e.target.value) / 100})`;
  });
  document.addEventListener("change", (e) => {
    if (e.target.matches("[data-participation]")) {
      detailStatus = e.target.value;
      P.toast(`预览身份已切换为${detailStatus}`);
      runtime.draw();
    }
    if (e.target.matches("[data-local-image]") && e.target.files[0]) {
      const file = e.target.files[0];
      if (!file.type.startsWith("image/")) return;
      const reader = new FileReader();
      reader.onload = () => {
        const container = document.getElementById("local-image");
        if (container)
          container.innerHTML = `<img src="${reader.result}" alt="本地图片预览" style="width:100%;height:100%;object-fit:cover">`;
      };
      reader.readAsDataURL(file);
    }
  });
  function appRuntimeDraw() {
    window.dispatchEvent(new HashChangeEvent("hashchange"));
  }
  document.addEventListener("submit", (e) => {
    const type = e.target.dataset.form;
    if (!type) return;
    e.preventDefault();
    if (type === "apply") {
      detailStatus = "待审核";
      location.hash = "join-result";
    }
    if (type === "auth") {
      P.toast("登录 / 注册流程模拟完成");
      location.hash = "home";
    }
    if (type === "cancel") {
      detailStatus = "活动已取消";
      P.toast("已模拟取消活动");
      location.hash = "event";
    }
    if (type === "chat") {
      const input = e.target.elements.message;
      messages.push(input.value);
      input.value = "";
      appRuntimeDraw();
    }
  });
  document.addEventListener("keydown", (e) => {
    if (
      (e.key === "Enter" || e.key === " ") &&
      e.target.matches("[role=button]")
    ) {
      e.preventDefault();
      e.target.click();
    }
  });
  window.APP_PREVIEW_ROUTES = routes;
})();

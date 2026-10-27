(() => {
  const P = window.Preview,
    {
      button: b,
      link: l,
      badge,
      field: f,
      area,
      select: s,
      toggle,
      avatar: a,
      note,
      panel,
      scene,
      table,
    } = P;
  const route = (id, title, widget, main = false, icon = "◇") => ({
    id,
    title,
    group: main ? "运营栏目" : "详情与操作",
    source: `admin/src/App.jsx · ${widget}`,
    main,
    icon,
  });
  const routes = [
    route("dashboard", "运营概览", "Dashboard", true, "⌁"),
    route("users", "用户管理", "Users", true, "◉"),
    route("events", "活动管理", "Events", true, "◇"),
    route("reports", "举报治理", "Reports", true, "△"),
    route("safety", "安全警报", "Safety", true, "!"),
    route("categories", "分类配置", "Categories", true, "⊞"),
    route("regions", "地区管理", "Regions", true, "⌖"),
    route("emoji-assets", "图标素材", "EmojiAssetManager", true, "▧"),
    route("avatars", "系统头像", "SystemAvatars", true, "◎"),
    route("audit", "审计日志", "Audit", true, "≡"),
    route("settings", "功能开关", "Settings", true, "⚙"),
    route("user-detail", "用户详情", "UserDetail"),
    route("event-detail", "活动详情与成员", "EventDetail"),
    route("category-new", "新建分类", "CategoryEditor"),
    route("category-edit", "编辑分类", "CategoryEditor"),
    route("region-new", "新建地区", "RegionEditor"),
    route("region-edit", "编辑地区", "RegionEditor"),
    route("announcement", "发布站内公告", "AnnouncementDialog"),
    route(
      "user-action",
      "账号状态处置",
      "UserDetail.changeStatus / Users.changeStatus",
    ),
    route("event-action", "活动处置", "EventDetail.moderate / Events.moderate"),
    route("report-action", "举报处置", "Reports.update"),
    route("safety-action", "警报响应", "Safety.update"),
    route("delete-category", "删除分类确认", "Categories"),
    route("delete-region", "删除地区确认", "Regions"),
  ];
  const users = [
    {
      name: "小林",
      face: "🐻",
      id: "preview-user-001",
      region: "首尔 · 永登浦区",
      role: "组织者",
      score: "4.8",
      events: "12",
      reports: 0,
      status: "正常",
    },
    {
      name: "安安",
      face: "🐱",
      id: "preview-user-002",
      region: "首尔 · 麻浦区",
      role: "普通用户",
      score: "4.9",
      events: "8",
      reports: 0,
      status: "正常",
    },
    {
      name: "阿树",
      face: "🦉",
      id: "preview-user-003",
      region: "首尔 · 恩平区",
      role: "组织者",
      score: "4.7",
      events: "6",
      reports: 1,
      status: "已暂停",
    },
    {
      name: "小雨",
      face: "🐰",
      id: "preview-user-004",
      region: "京畿道 · 水原市",
      role: "普通用户",
      score: "4.6",
      events: "3",
      reports: 0,
      status: "正常",
    },
  ];
  const events = [
    {
      title: "汉江日落，和新朋友慢慢走",
      host: "小林",
      category: "户外 · 散步",
      area: "首尔 · 永登浦区",
      time: "10/31 16:30",
      count: "4 / 6",
      status: "已发布",
      reports: 0,
    },
    {
      title: "周末咖啡，聊聊最近的生活",
      host: "安安",
      category: "社交 · 咖啡",
      area: "首尔 · 麻浦区",
      time: "11/01 14:00",
      count: "3 / 5",
      status: "已发布",
      reports: 0,
    },
    {
      title: "轻徒步，去山里呼吸一下",
      host: "阿树",
      category: "运动 · 徒步",
      area: "首尔 · 恩平区",
      time: "10/24 09:00",
      count: "5 / 8",
      status: "已完成",
      reports: 1,
    },
    {
      title: "雨天读书小聚",
      host: "小雨",
      category: "兴趣 · 阅读",
      area: "京畿道 · 水原市",
      time: "10/25 14:00",
      count: "2 / 4",
      status: "已取消",
      reports: 0,
    },
  ];
  const categories = [
    {
      name: "户外",
      code: "outdoor",
      icon: "🌿",
      en: "Outdoors",
      ko: "야외",
      level: 1,
    },
    {
      name: "散步",
      code: "outdoor_walk",
      icon: "🚶",
      en: "Walking",
      ko: "산책",
      level: 2,
    },
    {
      name: "社交",
      code: "social",
      icon: "☕",
      en: "Social",
      ko: "친목",
      level: 1,
    },
    {
      name: "咖啡",
      code: "social_coffee",
      icon: "☕",
      en: "Coffee",
      ko: "커피",
      level: 2,
    },
    {
      name: "运动",
      code: "sports",
      icon: "🏃",
      en: "Sports",
      ko: "운동",
      level: 1,
    },
    {
      name: "其它",
      code: "outdoor_other",
      icon: "✨",
      en: "Other",
      ko: "기타",
      level: 2,
    },
  ];
  const regions = [
    {
      name: "首尔特别市",
      code: "KR-11",
      en: "Seoul",
      ko: "서울특별시",
      level: 1,
    },
    {
      name: "永登浦区",
      code: "KR-11-560",
      en: "Yeongdeungpo-gu",
      ko: "영등포구",
      level: 2,
    },
    {
      name: "麻浦区",
      code: "KR-11-440",
      en: "Mapo-gu",
      ko: "마포구",
      level: 2,
    },
    {
      name: "京畿道",
      code: "KR-41",
      en: "Gyeonggi-do",
      ko: "경기도",
      level: 1,
    },
  ];
  const reports = [
    {
      title: "活动成员不当言论",
      user: "小雨",
      target: "阿树",
      priority: "P1",
      status: "新举报",
      text: "示例举报：活动聊天中出现不当言论，请运营核实。",
    },
    {
      title: "活动爽约反馈",
      user: "安安",
      target: "轻徒步活动",
      priority: "P2",
      status: "调查中",
      text: "示例举报：参与者未按约定时间出现。",
    },
  ];
  const alerts = [
    { name: "小雨", type: "安全会面逾时", status: "待响应" },
    { name: "安安", type: "用户主动求助", status: "已联系" },
  ];
  let userIndex = 0,
    eventIndex = 0,
    categoryIndex = 0,
    regionIndex = 0,
    reportIndex = 0,
    alertIndex = 0,
    userAction = "暂停账号",
    eventAction = "隐藏活动",
    reportAction = "开始调查",
    safetyAction = "已联系紧急联系人",
    search = "",
    filter = "",
    role = "",
    categoryLevel = "全部";
  const actions = {};
  const stats = (items) =>
    `<div class="metrics">${items.map(([title, value, note]) => `<article class="metric"><small>${title}</small><strong>${value}</strong><small>${note}</small></article>`).join("")}</div>`;
  const filters = (placeholder, options, roleOptions) =>
    `<div class="row wrap" style="margin-bottom:20px"><input class="grow" style="flex-basis:220px" data-search aria-label="${placeholder}" value="${P.esc(search)}" placeholder="${placeholder}">${roleOptions ? `<select data-role aria-label="身份筛选" style="width:140px">${roleOptions.map((o) => `<option ${o === role ? "selected" : ""}>${o}</option>`).join("")}</select>` : ""}${options ? `<select data-filter aria-label="状态筛选" style="width:150px">${options.map((o) => `<option ${o === filter ? "selected" : ""}>${o}</option>`).join("")}</select>` : ""}</div>`;
  const heading = (title, sub, action = "") =>
    `<div class="row between wrap" style="margin-bottom:20px"><div><span class="eyebrow">DAMUMU OPERATIONS</span><h2>${title}</h2><p class="muted" style="font-size:12px;margin-top:6px">${sub}</p></div>${action}</div>`;
  const fields = (items) =>
    `<dl class="field-list">${items.map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join("")}</dl>`;
  const userRows = () => {
    const rows = users
      .map((u, i) => ({ u, i }))
      .filter(
        ({ u }) =>
          `${u.name} ${u.id}`.includes(search) &&
          (!filter || filter === "全部状态" || u.status === filter) &&
          (!role || role === "全部身份" || u.role === role),
      );
    return rows.length
      ? table(
          [
            "用户",
            "地区 / 身份",
            "信誉",
            "活动记录",
            "安全信号",
            "状态",
            "操作",
          ],
          rows.map(({ u, i }) => [
            `<div class="row">${a(u.face)}<div><strong>${u.name}</strong><small class="block">${u.id}</small></div></div>`,
            `${u.region}<small class="block">${u.role}</small>`,
            `${u.score} <small>/ 5.0</small>`,
            `${u.events} 次参加<small class="block">0 次爽约</small>`,
            `${u.reports} 条举报`,
            badge(u.status, u.status === "正常" ? "" : "amber"),
            `<div class="row">${b("查看详情", `user:${i}`)}${b(u.status === "正常" ? "暂停" : "恢复", `user-status:${i}`)}</div>`,
          ]),
        )
      : '<p class="empty-search">没有符合条件的示例用户</p>';
  };
  const eventRows = () => {
    const rows = events
      .map((e, i) => ({ e, i }))
      .filter(
        ({ e }) =>
          e.title.includes(search) &&
          (!filter || filter === "全部状态" || e.status === filter),
      );
    return rows.length
      ? table(
          [
            "活动",
            "组织者",
            "时间 / 地点",
            "参与情况",
            "治理信号",
            "状态",
            "操作",
          ],
          rows.map(({ e, i }) => [
            `<strong>${e.title}</strong><small class="block">${e.category} · preview-event-00${i + 1}</small>`,
            e.host,
            `${e.time}<small class="block">${e.area}</small>`,
            `${e.count}<small class="block">候补 0</small>`,
            `${e.reports} 条举报`,
            badge(e.status, e.status === "已取消" ? "red" : ""),
            `<div class="row">${b("查看详情", `event:${i}`)}${b("隐藏", `event-hide:${i}`)}</div>`,
          ]),
        )
      : '<p class="empty-search">没有符合条件的示例活动</p>';
  };
  const reportCards = () =>
    reports
      .map((r, i) => ({ r, i }))
      .filter(
        ({ r }) => !filter || filter === "全部状态" || r.status === filter,
      )
      .map(({ r, i }) =>
        panel(
          "",
          `<div class="row between"><div class="row">${badge(r.priority, "red")}${badge(r.status, "amber")}</div><small>10/26 13:20</small></div><h3 style="margin:16px 0">${r.title}</h3><p class="muted">${r.text}</p><small class="block">举报人 ${r.user} · 对象 ${r.target}</small><div class="divider"></div><div class="row wrap">${["完成分诊", "开始调查", "处置完成", "驳回"].map((x) => b(x, `report:${i}:${x}`, x === "处置完成" ? "primary" : "")).join("")}</div>`,
        ),
      )
      .join("") || '<p class="empty-search">没有符合条件的举报</p>';
  const safetyCards = () =>
    alerts
      .map((r, i) => ({ r, i }))
      .filter(
        ({ r }) => !filter || filter === "全部状态" || r.status === filter,
      )
      .map(({ r, i }) =>
        panel(
          "",
          `<div class="row wrap between"><div><div class="row">${badge(r.status, "amber")}<small>10/26 14:10</small></div><h3 style="margin:14px 0">${P.esc(r.name)} · ${r.type}</h3><p class="muted">示例活动 · 下次确认 14:00</p></div><div class="stack">${["已联系紧急联系人", "标记已解决", "确认误报"].map((x) => b(x, `safety:${i}:${x}`, x === "标记已解决" ? "primary" : "")).join("")}</div></div>`,
        ),
      )
      .join("") || '<p class="empty-search">没有符合条件的警报</p>';
  const categoryCards = () =>
    categories
      .map((c, i) => ({ c, i }))
      .filter(
        ({ c }) =>
          (categoryLevel === "全部" ||
            (categoryLevel === "大分类" ? c.level === 1 : c.level === 2)) &&
          `${P.esc(c.name)} ${c.code} ${c.en} ${c.ko}`
            .toLowerCase()
            .includes(search.toLowerCase()),
      )
      .map(({ c, i }) =>
        panel(
          "",
          `<div class="row">${a(c.icon)}<div class="grow"><small>${c.level === 1 ? "大分类" : "小分类"}</small><h3>${P.esc(c.name)}</h3></div>${toggle(`启用${P.esc(c.name)}`, !c.disabled)}</div><small class="block">${c.level === 2 ? "户外 / " : ""}${P.esc(c.name)} · ${c.code}</small><p class="muted">${c.en} · ${c.ko}</p><div class="divider"></div><div class="row">${b("编辑", `category:${i}`)}${b("删除", `delete-category:${i}`, "danger")}</div>`,
        ),
      )
      .join("") || '<p class="empty-search">没有符合条件的分类</p>';
  let renderedRoute = "";
  function render(id) {
    if (id !== renderedRoute) {
      resetSearch();
      renderedRoute = id;
    }
    const u = users[userIndex],
      e = events[eventIndex];
    switch (id) {
      case "emoji-assets":
        return `${heading("图标素材", "本页展示随项目保存的64×64真实素材；上传与启停请在正式Admin操作。", badge("离线素材预览"))}<div class="grid3">${window.EmojiArtwork.map(item => `<article class="panel"><img src="${item.src}" width="64" height="64" alt="${item.emoji}"><h3>${item.name}</h3><p class="muted">${item.key} · 64×64 PNG</p></article>`).join("")}</div>`;

      case "dashboard":
        return `${heading("社区今天，也在发生好事", "以下为虚构统计，用于评审信息层级与页面布局。", badge("离线预览"))}${stats(
          [
            ["累计用户", "1,284", "近7日 +86"],
            ["在架活动", "42", "累计 186 场"],
            ["待处理举报", "2", "按优先级处置"],
            ["安全警报", "2", "需及时响应"],
          ],
        )}<div class="grid2">${panel("社区增长与报名", `<div class="row"><small>● 用户</small><small style="color:#bd914b">● 报名</small></div><div class="chart">${[38, 55, 43, 66, 48, 80, 64].map((h, i) => `<div class="bar-group"><i style="height:${h}%"></i><i style="height:${h * 0.7}%"></i><span>10/${20 + i}</span></div>`).join("")}</div>`)}${panel("过去24小时", `<span class="eyebrow">COMMUNITY PULSE</span><h1 style="font-size:58px;margin:20px 0">326</h1><p class="muted">条站内消息</p><div class="divider"></div><div class="row between"><span>累计签到</span><strong>684</strong></div><div class="divider"></div>${note("此处为示例数据，不代表服务器健康状态。")}`)}</div><div class="grid2">${panel(
          "最新活动",
          events
            .slice(0, 3)
            .map(
              (x, i) =>
                `<div class="row between" style="padding:14px 0;border-bottom:1px solid var(--line)"><div><strong>${x.title}</strong><small class="block">${x.host} · ${x.time}</small></div>${b("详情", `event:${i}`)}</div>`,
            )
            .join(""),
        )}${panel("优先举报", reports.map((x, i) => `<div class="row" style="padding:14px 0">${badge(x.priority, "red")}<div class="grow"><strong>${x.title}</strong><small class="block">${x.user} · ${x.status}</small></div>${b("处理", `report:${i}:开始调查`)}</div>`).join(""))}</div>`;
      case "users":
        return panel(
          "",
          `${heading("用户管理", "查看账号资料、参与履历、正向反馈和安全治理信号", badge("4 位示例用户"))}${filters("搜索昵称或用户 UUID", ["全部状态", "正常", "已暂停", "已封禁"], ["全部身份", "普通用户", "组织者", "管理员"])}<div id="list-content">${userRows()}</div>`,
        );
      case "events":
        return panel(
          "",
          `${heading("活动管理", "检查活动资料、成员构成与治理记录", badge("4 场示例活动"))}${filters("搜索活动标题", ["全部状态", "草稿", "已发布", "已满员", "已隐藏", "已取消", "已完成"])}<div id="list-content">${eventRows()}</div>`,
        );
      case "user-detail":
        return `${l("← 返回用户列表", "users", "ghost")}${heading(u.name, `用户 ID · ${u.id}`, `<div class="row wrap">${b("恢复账号", "restore-user")}${b("暂停账号", "suspend-user")}${b("封禁账号", "ban-user", "danger")}</div>`)}${stats(
          [
            ["信誉分", u.score, "12 次评价"],
            ["获得喜欢", "12", "守时 · 友善"],
            ["参加活动", u.events, "已完成活动"],
            ["举报记录", u.reports, "仅运营可见"],
          ],
        )}<div class="grid2">${panel(
          "账号资料",
          `<div class="row">${a(u.face, true)}<div><h2>${u.name}</h2>${badge(u.status)}</div></div>${fields(
            [
              ["邮箱", "preview@example.invalid"],
              ["身份", u.role],
              ["地区", u.region],
              ["注册时间", "2026/09/01"],
              ["账号状态", u.status],
              ["最后活跃", "2026/10/26 13:40"],
            ],
          )}`,
        )}<div class="stack">${panel(
          "活动履历",
          events
            .slice(0, 2)
            .map(
              (x, i) =>
                `<div class="row between" style="padding:14px 0"><div><strong>${x.title}</strong><small class="block">${x.time}</small></div>${b("查看", `event:${i}`)}</div>`,
            )
            .join(""),
        )}${panel("举报记录", u.reports ? "<p>示例反馈 · 调查中</p>" : '<p class="muted">没有举报记录</p>')}</div></div>`;
      case "event-detail":
        return `${l("← 返回活动列表", "events", "ghost")}${heading(e.title, "活动 ID · preview-event-001", `<div class="row">${b("恢复展示", "restore-event")}${b("隐藏活动", "hide-event")}${b("取消活动", "cancel-event", "danger")}</div>`)}${stats(
          [
            ["已通过", e.count, "候补 0 人"],
            ["预计人均费用", "₩5,000", "线下自付 · KRW"],
            ["活动举报", e.reports, "包含参与者反馈"],
            ["可见状态", e.status, "组织者审核报名"],
          ],
        )}<div class="grid2">${panel(
          "活动资料",
          `${scene(eventIndex % 3)}${fields([
            ["分类", e.category],
            ["组织者", e.host],
            ["地区", e.area],
            ["集合点", "虚构示例集合点"],
            ["活动介绍", "沿江散步，轻松认识新朋友。"],
            ["语言", "中文 / 한국어"],
            ["开始", e.time],
            ["结束", "10/31 18:30"],
          ])}`,
        )}<div class="stack">${panel("时间安排", "<p>2026/10/31 16:30 — 18:30</p><small>Asia/Seoul · 已排期</small>")}${panel("处置记录", '<p class="muted">暂无处置记录</p>')}${panel("治理信号", "<p>举报数量仅运营可见。</p><small>新活动直接发布，不要求管理员预审。</small>")}</div></div>${panel(
          "成员与申请",
          table(
            ["用户", "角色", "状态", "人数", "信誉", "申请备注", "操作"],
            users.map((x, i) => [
              x.name,
              i === 0 ? "组织者" : "参与者",
              badge(i === 3 ? "待审核" : "已通过", i === 3 ? "amber" : ""),
              "1",
              x.score,
              i === 3 ? "第一次参加，期待一起看日落。" : "—",
              i === 3 ? b("通过申请", "approve-member", "primary") : "—",
            ]),
          ),
        )}${panel("举报与风险反馈", '<p class="muted">当前示例活动没有举报记录。</p>')}`;
      case "reports":
        return panel(
          "",
          `${heading("举报治理", "按优先级处理举报，记录原因与处置结果")}${filters("搜索举报内容", ["全部状态", "新举报", "已分诊", "调查中", "已解决", "已驳回"])}<div class="grid2" id="list-content">${reportCards()}</div>`,
        );
      case "safety":
        return panel(
          "",
          `${heading("安全警报", "联系人通知和运营响应不代替紧急救援")}${note("App 安全会面仍有占位能力。此处展示后台警报处置界面，不表示告警链路已验收。")}${filters("搜索警报", ["全部状态", "待响应", "已联系", "已解决", "误报"])}<div class="stack" id="list-content">${safetyCards()}</div>`,
        );
      case "categories":
        return panel(
          "",
          `${heading("活动分类", "分类层级、多语言名称、排序与 App 可见状态", l("＋ 新建分类", "category-new", "primary"))}<div class="tabs" style="margin-bottom:20px">${["全部", "大分类", "小分类"].map((x, i) => b(x, `level:${i}`, categoryLevel === x ? "active" : "")).join("")}</div>${filters("搜索分类路径、代码或多语言名称")}<div class="grid3" id="list-content">${categoryCards()}</div>`,
        );
      case "category-new":
      case "category-edit":
        return categoryForm(id === "category-edit");
      case "regions":
        return panel(
          "",
          `${heading("行政地区", "标准代码保持稳定，维护多语言名称、排序和可见状态", l("＋ 新建地区", "region-new", "primary"))}${table(
            [
              "地区",
              "代码",
              "层级",
              "English / 한국어",
              "活动",
              "启用",
              "操作",
            ],
            regions.map((r, i) => [
              `<strong>${P.esc(r.name)}</strong><small class="block">${r.level === 1 ? "一级地区" : "首尔特别市"}</small>`,
              `<code>${r.code}</code>`,
              r.level === 1 ? "城市 / 道" : "区 / 市",
              `${r.en}<small class="block">${r.ko}</small>`,
              i + 3,
              toggle(`启用${P.esc(r.name)}`),
              `<div class="row">${b("编辑", `region:${i}`)}${b("删除", `delete-region:${i}`, "danger")}</div>`,
            ]),
          )}`,
        );
      case "region-new":
      case "region-edit":
        return regionForm(id === "region-edit");
      case "avatars":
        return `${panel("", `${heading("系统头像库", "仅接收 512×512 JPEG，文件最大 1 MB")}<form data-form="avatar" class="stack"><div class="grid3">${f("唯一代码", "", "text", 'required placeholder="forest_fox"')}${f("中文名称", "", "text", "required")}${f("English name", "", "text", "required")}${f("한국어 이름", "", "text", "required")}${f("排序", "10", "number")}${f("头像文件", "", "file", 'required accept="image/jpeg"')}</div><div>${b("上传头像（模拟）", "upload-avatar", "primary")}</div></form>`)}<div class="grid3">${[
          ["🐻", "蓝蓝熊", "Blue Bear", "파란 곰"],
          ["🐱", "奶油猫", "Cream Cat", "크림 고양이"],
          ["🐰", "月亮兔", "Moon Rabbit", "달 토끼"],
          ["🐳", "青鲸", "Teal Whale", "청록 고래"],
          ["🦉", "天空猫头鹰", "Sky Owl", "하늘 부엉이"],
          ["🦦", "绿松石水獭", "Turquoise Otter", "터키석 수달"],
        ]
          .map(([face, name, en, ko], i) =>
            panel(
              "",
              `<div class="row">${a(face, true)}<div class="grow"><h3>${name}</h3><small>${en} · ${ko}</small><small class="block">preview_avatar_${i} · 45 KB</small></div></div><div class="divider"></div>${toggle(`启用${name}`)}`,
            ),
          )
          .join("")}</div>`;
      case "audit":
        return panel(
          "",
          `${heading("审计日志", "管理员高风险操作及敏感对象访问记录")}${filters("按准确操作代码筛选")}<div id="list-content">${auditRows()}</div>`,
        );
      case "settings":
        return panel(
          "",
          `${heading("功能开关", "示例标志仅用于评审开关布局，正式键与值以 API 为准")}${[
            ["preview_activity_flag", "活动能力示例"],
            ["preview_chat_flag", "聊天能力示例"],
            ["preview_optional_flag", "灰度功能示例"],
          ]
            .map(
              ([key, label], i) =>
                `<div class="row between" style="padding:23px 0;border-bottom:1px solid var(--line)"><div><h3>${key}</h3><p class="muted">${label}</p><small>版本 1 · 10/26 14:00</small></div>${toggle(label, i !== 2)}</div>`,
            )
            .join("")}`,
        );
      case "announcement":
        return panel(
          "",
          `${heading("发布站内公告", "对应正式后台公告弹窗；预览不会发送给任何用户")}<form data-form="announcement" class="stack">${f("公告标题", "", "text", 'required maxlength="160" placeholder="例如：周末活动参与提醒"')}${area("公告内容").replace("<textarea>", '<textarea required maxlength="1000">')}${note("正式发布会通知所有活跃用户；请在真实后台核对标题、正文和发送范围。")}<div class="row">${l("取消", "dashboard")}<button type="submit" class="primary">确认发布（模拟）</button></div></form>`,
        );
      case "user-action":
        return actionPage(
          "账号处置",
          `${u.name} · ${userAction}`,
          "处置原因（必填）",
          "user-confirm",
          "user-detail",
        );
      case "event-action":
        return actionPage(
          "活动处置",
          `${e.title} · ${eventAction}`,
          "处置原因（必填）",
          "event-confirm",
          "event-detail",
        );
      case "report-action":
        return actionPage(
          "举报处置",
          `${reports[reportIndex].title} · ${reportAction}`,
          "处理说明",
          "report-confirm",
          "reports",
        );
      case "safety-action":
        return actionPage(
          "警报响应",
          `${alerts[alertIndex].name} · ${safetyAction}`,
          "记录本次响应情况",
          "safety-confirm",
          "safety",
        );
      case "delete-category":
        return actionPage(
          "删除分类",
          categories[categoryIndex]?.name || "示例分类",
          "删除说明（预览备注）",
          "delete-category-confirm",
          "categories",
        );
      case "delete-region":
        return actionPage(
          "删除地区",
          regions[regionIndex]?.name || "示例地区",
          "删除说明（预览备注）",
          "delete-region-confirm",
          "regions",
        );
      default:
        throw new Error(`Unmapped admin route: ${id}`);
    }
  }
  function categoryForm(edit) {
    const c = edit ? categories[categoryIndex] : null;
    return panel(
      "",
      `${heading(edit ? "编辑分类" : "新建分类", "对应 CategoryEditor 的完整字段")}${l("← 返回分类列表", "categories", "ghost")}<form data-form="category" class="stack"><div class="grid3">${s("父级分类", ["无（作为大分类）", "户外", "社交", "运动"])}${f("唯一代码", c?.code || "", "text", 'required pattern="[a-z0-9_]+"')}${f("图标 Emoji", c?.icon || "✨")}${f("插画资源键", "", "text", 'placeholder="未提供时显示 Emoji"')}${f("主题颜色", "#287756", "color")}${f("中文名称", c?.name || "", "text", 'required data-name="zh"')}${f("English", c?.en || "")}${f("한국어", c?.ko || "")}${f("排序", "10", "number")}</div>${area("中文说明")}${area("English description")}${area("한국어 설명")}${toggle("在 App 中启用此分类")}${toggle("默认展示在发布页", false)}<div class="row">${l("取消", "categories")}<button type="submit" class="primary">保存分类（模拟）</button></div></form>`,
    );
  }
  function regionForm(edit) {
    const r = edit ? regions[regionIndex] : null;
    return panel(
      "",
      `${heading(edit ? "编辑地区" : "新建地区", "对应 RegionEditor 的业务字段")}${l("← 返回地区列表", "regions", "ghost")}<form data-form="region" class="stack"><div class="grid2">${s("层级", ["城市 / 道", "区 / 市"])}${s("上级地区", ["无（城市 / 道）", "首尔特别市", "京畿道"])}${f("标准代码", r?.code || "", "text", `required ${edit ? "readonly" : ""}`)}${f("中文名称", r?.name || "", "text", 'required data-name="zh"')}${f("English", r?.en || "")}${f("한국어", r?.ko || "")}${f("排序", "10", "number")}</div>${toggle("在 App 中启用此地区")}<div class="row">${l("取消", "regions")}<button type="submit" class="primary">保存地区（模拟）</button></div></form>`,
    );
  }
  function actionPage(title, subject, label, action, back) {
    return panel(
      "",
      `${heading(title, subject)}${note("仅模拟处置界面，不写入数据库或真实审计日志。")}<form class="stack" data-form="action" data-confirm="${action}">${area(label).replace("<textarea>", `<textarea ${label.includes("必填") ? "required" : ""}>`)}<div class="row">${l("取消", back)}<button type="submit" class="danger">确认操作（模拟）</button></div></form>`,
    );
  }
  function auditRows() {
    const rows = [
      ["user.status.update", "账号状态更新", "小林"],
      ["event.application.approve", "通过活动申请", "小雨"],
      ["category.update", "修改活动分类", "户外"],
      ["announcement.create", "发布站内公告", "示例公告"],
    ].filter(([code]) => !search || code === search);
    return rows.length
      ? table(
          ["时间", "操作代码", "对象", "操作者", "追踪号"],
          rows.map(([code, title, target]) => [
            "10/26 14:30",
            `<strong>${title}</strong><small class="block">${code}</small>`,
            target,
            "示例管理员",
            "preview-trace-001",
          ]),
        )
      : '<p class="empty-search">没有符合条件的审计记录</p>';
  }
  function resetSearch() {
    search = "";
    filter = "";
    role = "";
  }
  const runtime = P.boot({ kind: "admin", routes, render, actions });
  const go = (id) => {
    resetSearch();
    runtime.go(id);
  };
  users.forEach((u, i) => {
    actions[`user:${i}`] = () => {
      userIndex = i;
      go("user-detail");
    };
    actions[`user-status:${i}`] = () => {
      userIndex = i;
      userAction = u.status === "正常" ? "暂停账号" : "恢复账号";
      go("user-action");
    };
  });
  events.forEach((_, i) => {
    actions[`event:${i}`] = () => {
      eventIndex = i;
      go("event-detail");
    };
    actions[`event-hide:${i}`] = () => {
      eventIndex = i;
      eventAction = "隐藏活动";
      go("event-action");
    };
  });
  for (const [key, label] of [
    ["restore-user", "恢复账号"],
    ["suspend-user", "暂停账号"],
    ["ban-user", "封禁账号"],
  ])
    actions[key] = () => {
      userAction = label;
      go("user-action");
    };
  for (const [key, label] of [
    ["restore-event", "恢复展示"],
    ["hide-event", "隐藏活动"],
    ["cancel-event", "取消活动"],
  ])
    actions[key] = () => {
      eventAction = label;
      go("event-action");
    };
  reports.forEach((_, i) =>
    ["完成分诊", "开始调查", "处置完成", "驳回"].forEach((label) => {
      actions[`report:${i}:${label}`] = () => {
        reportIndex = i;
        reportAction = label;
        go("report-action");
      };
    }),
  );
  alerts.forEach((_, i) =>
    ["已联系紧急联系人", "标记已解决", "确认误报"].forEach((label) => {
      actions[`safety:${i}:${label}`] = () => {
        alertIndex = i;
        safetyAction = label;
        go("safety-action");
      };
    }),
  );
  function registerCatalogActions() {
    categories.forEach((_, i) => {
      actions[`category:${i}`] = () => {
        categoryIndex = i;
        go("category-edit");
      };
      actions[`delete-category:${i}`] = () => {
        categoryIndex = i;
        go("delete-category");
      };
    });
    regions.forEach((_, i) => {
      actions[`region:${i}`] = () => {
        regionIndex = i;
        go("region-edit");
      };
      actions[`delete-region:${i}`] = () => {
        regionIndex = i;
        go("delete-region");
      };
    });
  }
  registerCatalogActions();
  ["全部", "大分类", "小分类"].forEach((x, i) => {
    actions[`level:${i}`] = () => {
      categoryLevel = x;
      runtime.draw();
    };
  });
  actions["approve-member"] = ({ target, toast }) => {
    target.closest("tr").children[2].innerHTML = badge("已通过");
    target.outerHTML = "<small>已通过</small>";
    toast("已模拟通过申请，未调用真实接口");
  };
  actions["upload-avatar"] = ({ toast }) => {
    const form = document.querySelector("[data-form=avatar]");
    if (form.reportValidity())
      toast("已模拟上传。正式服务会校验 JPEG、512×512 尺寸与文件大小。");
  };
  document.addEventListener("input", (e) => {
    if (e.target.matches("[data-search]")) {
      search = e.target.value;
      updateList();
    }
  });
  document.addEventListener("change", (e) => {
    if (e.target.matches("[data-filter]")) {
      filter = e.target.value;
      updateList();
    }
    if (e.target.matches("[data-role]")) {
      role = e.target.value;
      updateList();
    }
  });
  function updateList() {
    const id = location.hash.slice(1) || "dashboard";
    const el = document.getElementById("list-content");
    if (!el) return;
    el.innerHTML = (
      {
        users: userRows,
        events: eventRows,
        reports: reportCards,
        safety: safetyCards,
        categories: categoryCards,
        audit: auditRows,
      }[id] || (() => "")
    )();
  }
  document.addEventListener("submit", (e) => {
    const type = e.target.dataset.form;
    if (!type) return;
    e.preventDefault();
    if (type === "announcement") {
      P.toast("公告已模拟发布，不会向任何人发送通知");
      go("dashboard");
    }
    if (type === "category") {
      const name = e.target.querySelector("[data-name=zh]").value;
      if (location.hash === "#category-new")
        categories.push({
          name,
          code: "preview_new",
          icon: "✨",
          en: "Preview",
          ko: "미리보기",
          level: 1,
        });
      else categories[categoryIndex].name = name;
      P.toast("已模拟保存分类名称");
      go("categories");
    }
    if (type === "region") {
      const name = e.target.querySelector("[data-name=zh]").value;
      if (location.hash === "#region-new")
        regions.push({
          name,
          code: "PREVIEW-NEW",
          en: "Preview",
          ko: "미리보기",
          level: 1,
        });
      else regions[regionIndex].name = name;
      P.toast("已模拟保存地区名称");
      go("regions");
    }
    if (type === "action") {
      const confirm = e.target.dataset.confirm;
      if (confirm === "user-confirm") {
        users[userIndex].status = {
          暂停账号: "已暂停",
          封禁账号: "已封禁",
          恢复账号: "正常",
        }[userAction];
        go("user-detail");
      }
      if (confirm === "event-confirm") {
        events[eventIndex].status = {
          隐藏活动: "已隐藏",
          取消活动: "已取消",
          恢复展示: "已发布",
        }[eventAction];
        go("event-detail");
      }
      if (confirm === "report-confirm") {
        reports[reportIndex].status = {
          完成分诊: "已分诊",
          开始调查: "调查中",
          处置完成: "已解决",
          驳回: "已驳回",
        }[reportAction];
        go("reports");
      }
      if (confirm === "safety-confirm") {
        alerts[alertIndex].status = {
          已联系紧急联系人: "已联系",
          标记已解决: "已解决",
          确认误报: "误报",
        }[safetyAction];
        go("safety");
      }
      if (confirm === "delete-category-confirm") {
        categories[categoryIndex].disabled = true;
        P.toast("删除确认界面已演示；目录示例保留，防止页面引用失效。");
        go("categories");
      } else if (confirm === "delete-region-confirm") {
        P.toast("删除确认界面已演示；地区示例保留。");
        go("regions");
      } else P.toast("操作已模拟完成，未更改正式数据");
    }
  });
  document.addEventListener("submit", registerCatalogActions);
  window.ADMIN_PREVIEW_ROUTES = routes;
})();

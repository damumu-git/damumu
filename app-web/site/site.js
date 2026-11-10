const apiRoot = "https://api.damumu.com";
const oauth = "/api/v1/auth/web";
const $ = (selector, root = document) => root.querySelector(selector);
const dialog = $("#dialog");
const panel = $("#panel");
const page = $("#page");
const browse = $("#browse");
const cards = $("#cards");
const status = $("#status");
const city = $("#city");
const district = $("#district");
const ward = $("#ward");
const more = $("#more");
let regions = [],
  categories = [],
  options = {};
let category = "",
  query = "",
  cursor = null,
  feedRequest,
  feedCount = 0;
let dialogRequest = 0;

function readSession() {
  try {
    return JSON.parse(sessionStorage.getItem("damu-session")) ?? null;
  } catch {
    return null;
  }
}
let session = readSession();

function setSession(value) {
  session = value;
  if (value) sessionStorage.setItem("damu-session", JSON.stringify(value));
  else sessionStorage.removeItem("damu-session");
  $("#login").textContent = value ? value.user.nickname : "登录";
  $("#login").href = value ? "/settings/profile" : "/login";
}

async function request(
  path,
  { data, signal, auth = false, sameOrigin = false, method } = {},
) {
  const headers = {};
  if (data !== undefined) headers["Content-Type"] = "application/json";
  if (auth && session?.accessToken)
    headers.Authorization = "Bearer " + session.accessToken;
  const response = await fetch((sameOrigin ? "" : apiRoot + "/api/v1") + path, {
    headers,
    signal,
    method: method ?? (data === undefined ? "GET" : "POST"),
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok || !payload || payload.error) {
    if (
      auth &&
      response.status === 401 &&
      headers.Authorization === "Bearer " + session?.accessToken
    ) {
      setSession(null);
    }
    throw new Error(payload?.error?.message ?? "请求失败，请稍后再试。");
  }
  return payload.data;
}

function node(tag, text, className) {
  const element = document.createElement(tag);
  if (text != null) element.textContent = text;
  if (className) element.className = className;
  return element;
}

function button(text, onClick, className = "button ghost") {
  const element = node("button", text, className);
  element.type = "button";
  element.addEventListener("click", onClick);
  return element;
}

function fillSelect(
  element,
  values,
  placeholder,
  valueKey,
  nameKey = "name_zh_cn",
) {
  const previous = element.value;
  element.replaceChildren(new Option(placeholder, ""));
  for (const value of values)
    element.add(new Option(value[nameKey] || value[valueKey], value[valueKey]));
  if (values.some((value) => value[valueKey] === previous))
    element.value = previous;
}

function region(code) {
  return regions.find((entry) => entry.code === code);
}

function regionChildren(parent, level) {
  return regions.filter(
    (entry) => entry.parent_code === parent && entry.level === level,
  );
}

function area(item) {
  const leaf = region(item.district_code);
  const middle =
    item.municipality_code || (leaf?.level === 3 ? leaf.parent_code : "");
  return [
    item.city_name || region(item.city_code)?.name_zh_cn,
    item.municipality_name || region(middle)?.name_zh_cn,
    item.district_name || leaf?.name_zh_cn,
  ]
    .filter(Boolean)
    .join(" · ");
}

function updateWard(select, label, parent, placeholder = "全部下辖区") {
  const choices = regionChildren(parent, 3);
  select.value = "";
  fillSelect(select, choices, placeholder, "code");
  select.disabled = choices.length === 0;
  label.hidden = select.disabled;
}

const dates = new Intl.DateTimeFormat("zh-CN", {
  timeZone: "Asia/Seoul",
  month: "long",
  day: "numeric",
  weekday: "short",
  hour: "2-digit",
  minute: "2-digit",
});
function time(value) {
  const date = new Date(value);
  return value && Number.isFinite(date.valueOf())
    ? dates.format(date)
    : "时间待定";
}

function cost(item) {
  const amount = item.price_amount ?? item.price_max;
  return amount == null
    ? "费用待定"
    : amount === 0
      ? "免费"
      : "预计 ₩" + Number(amount).toLocaleString("ko-KR") + "/人";
}

const coverKinds = new Set([
  "culture",
  "food",
  "other",
  "outdoors",
  "social",
  "sports",
  "study",
]);
function uploadedImage(value) {
  try {
    const url = new URL(value ?? "", apiRoot);
    return url.origin === apiRoot && url.pathname.startsWith("/uploads/")
      ? url.href
      : null;
  } catch {
    return null;
  }
}
function cover(item, className = "") {
  const image = node("img", null, className);
  image.alt = "";
  image.loading = "lazy";
  const kind = coverKinds.has(item.cover_category_code)
    ? item.cover_category_code
    : "other";
  const fallback = "/assets/covers/" + kind + ".webp";
  const sub = item.cover_subcategory_code;
  const specific =
    typeof sub === "string" && /^[a-z0-9_]+$/.test(sub)
      ? "/assets/covers/sub/" + sub + ".webp"
      : null;
  const candidates = [uploadedImage(item.cover_url), specific, fallback].filter(
    Boolean,
  );
  image.addEventListener("error", () => {
    if (candidates.length) image.src = candidates.shift();
  });
  image.src = candidates.shift();
  return image;
}

function eventLink(id) {
  return "/activities/" + encodeURIComponent(id);
}
function card(item) {
  const article = node("article", null, "card");
  const thumbnail = node("a", null, "cover");
  thumbnail.href = eventLink(item.id);
  thumbnail.setAttribute("aria-label", item.title);
  thumbnail.append(cover(item));
  if (item.category_name) {
    const badge = node("span", null, "tag");
    const icon = uploadedImage(item.category_icon_url);
    if (icon) {
      const image = node("img");
      image.alt = "";
      image.src = icon;
      image.addEventListener("error", () => image.remove(), { once: true });
      badge.append(image);
    } else if (item.category_icon)
      badge.append(node("span", item.category_icon));
    badge.append(node("span", item.category_name));
    thumbnail.append(badge);
  }
  const heading = node("h3");
  const link = node("a", item.title);
  link.href = thumbnail.href;
  heading.append(link);
  const host = node("div", null, "host");
  host.append(
    node("strong", item.organizer_name || "活动组织者"),
    node("span", cost(item)),
  );
  article.append(
    thumbnail,
    heading,
    node(
      "p",
      [time(item.starts_at), area(item)].filter(Boolean).join(" · "),
      "meta",
    ),
    host,
  );
  return article;
}

function renderCategories() {
  const list = $("#categories");
  const choices = [
    { id: "", name_zh_cn: "全部活动" },
    ...categories.filter((entry) => entry.level === 2),
  ];
  list.replaceChildren(
    ...choices.map((entry) => {
      const item = button(entry.name_zh_cn, () => {
        category = entry.id;
        renderCategories();
        loadFeed();
      });
      item.setAttribute("aria-pressed", String(category === entry.id));
      return item;
    }),
  );
}

async function loadFeed(append = false) {
  feedRequest?.abort();
  const controller = new AbortController();
  feedRequest = controller;
  const params = new URLSearchParams({
    limit: location.pathname === "/" ? "8" : "20",
  });
  for (const [key, value] of Object.entries({
    city: city.value,
    district: ward.value || district.value,
    sort: $("#sort").value,
    q: query,
    categoryId: category,
    cursor: append ? cursor : null,
  }))
    if (value) params.set(key, value);
  const day = $("#day").value;
  if (day) {
    params.set("from", new Date(day + "T00:00:00+09:00").toISOString());
    params.set("to", new Date(day + "T23:59:59.999+09:00").toISOString());
  }
  if (!append) {
    cards.replaceChildren();
    cursor = null;
    feedCount = 0;
  }
  status.classList.remove("error");
  status.textContent = "正在加载活动…";
  more.hidden = true;
  try {
    const page = await request("/activities?" + params, {
      signal: controller.signal,
    });
    if (feedRequest !== controller) return;
    cards.append(...page.items.map(card));
    feedCount += page.items.length;
    cursor = page.hasMore ? page.nextCursor : null;
    status.textContent = feedCount
      ? "已展示 " + feedCount + " 场活动"
      : "暂时没有符合条件的活动。试试其他城市、类别或关键词。";
  } catch (error) {
    if (feedRequest !== controller) return;
    status.classList.add("error");
    status.replaceChildren(
      node("span", error.message + " "),
      button("重试", () => loadFeed(append), "text-button"),
    );
  } finally {
    if (feedRequest === controller)
      more.hidden = location.pathname === "/" || !cursor;
  }
}

function show(title, layout = "reading", modal = false) {
  dialogRequest++;
  const content = node(
    "section",
    null,
    modal ? "dialog-body" : "page-content " + layout,
  );
  const heading = node(modal ? "h2" : "h1", title);
  heading.id = modal ? "dialog-title" : "page-title";
  content.append(heading);
  if (modal) {
    panel.replaceChildren(content);
    if (!dialog.open) dialog.showModal();
    dialog.scrollTop = 0;
  } else {
    if (dialog.open) dialog.close();
    browse.hidden = true;
    page.hidden = false;
    page.replaceChildren(content);
    document.title = title + " · 搭慕 DAMU";
  }
  return content;
}

function actionLink(label, href, style = "button ghost") {
  const link = node("a", label, style);
  link.href = href;
  return link;
}

function showError(content, error) {
  const slot = $(".form-error", content) ?? node("p", null, "form-error");
  slot.setAttribute("role", "alert");
  slot.textContent = error.message;
  if (!slot.isConnected) content.append(slot);
}

function currentPage() {
  return location.pathname + location.search;
}
function safeReturn(value) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/";
  let url;
  try {
    url = new URL(value, location.origin);
  } catch {
    return "/";
  }
  return url.origin === location.origin &&
    !["/login", "/register", "/auth/complete"].includes(url.pathname)
    ? url.pathname + url.search
    : "/";
}
function requireLogin(action) {
  if (session) action();
  else location.assign("/login?next=" + encodeURIComponent(currentPage()));
}
function finishLogin(result) {
  setSession(result);
  const target =
    sessionStorage.getItem("damu-return") ??
    new URLSearchParams(location.search).get("next");
  sessionStorage.removeItem("damu-return");
  location.replace(safeReturn(target));
}

function formValues(form) {
  return Object.fromEntries(new FormData(form));
}

function handleForm(form, content, action) {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const submit = $('button[type="submit"]', form);
    submit.disabled = true;
    $(".form-error", content)?.remove();
    try {
      await action(formValues(form));
    } catch (error) {
      showError(content, error);
    } finally {
      submit.disabled = false;
    }
  });
}

function showLogin(register = false, socialRegistration = false, notice = "") {
  const content = show(
    socialRegistration ? "完成注册" : register ? "创建搭慕账号" : "登录搭慕",
    "account-page",
  );
  if (notice) content.append(node("p", notice, "notice"));
  if (register || socialRegistration)
    content.append(node("p", "创建账号后即可报名或发起活动。", "meta"));
  if (!register && !socialRegistration) {
    const social = node("div", null, "social");
    for (const [provider, title] of [
      ["google", "使用 Google 登录"],
      ["kakao", "使用 Kakao 登录"],
    ]) {
      social.append(
        button(
          title,
          async () => {
            try {
              options = await request(oauth + "/options", { sameOrigin: true });
              if (!options[provider])
                throw new Error(
                  title.slice(3, -3) + " 尚未在服务器启用，请先使用邮箱登录。",
                );
              sessionStorage.setItem(
                "damu-return",
                safeReturn(new URLSearchParams(location.search).get("next")),
              );
              location.assign(oauth + "/" + provider + "/start");
            } catch (error) {
              showError(content, error);
            }
          },
          "button " + (provider === "kakao" ? "kakao" : "ghost"),
        ),
      );
    }
    content.append(social, node("p", "或使用邮箱", "meta"));
  }

  const form = node("form", null, "form");
  if (register || socialRegistration) {
    form.insertAdjacentHTML(
      "beforeend",
      '<label>昵称<input name="nickname" autocomplete="nickname" required minlength="2" maxlength="30"></label>',
    );
  }
  if (!socialRegistration) {
    form.insertAdjacentHTML(
      "beforeend",
      '<label>邮箱<input name="email" type="email" autocomplete="username" required></label>',
    );
    const password = node("label", "密码");
    const input = node("input");
    input.type = "password";
    input.name = "password";
    input.autocomplete = register ? "new-password" : "current-password";
    input.required = true;
    if (register) input.minLength = 8;
    password.append(input);
    form.append(password);
  }
  if (register || socialRegistration) {
    form.insertAdjacentHTML(
      "beforeend",
      '<label class="check"><input type="checkbox" name="ageConfirmed" required>我已满 14 周岁</label><label class="check"><input type="checkbox" name="privacyAcknowledged" required><span>我已阅读并确认<a href="https://www.damumu.com/privacy.html" target="_blank" rel="noopener">隐私政策</a></span></label>',
    );
  }
  const submit = node(
    "button",
    register || socialRegistration ? "创建账号" : "登录",
    "button primary",
  );
  submit.type = "submit";
  form.append(submit);
  content.append(form);
  if (!socialRegistration)
    content.append(
      button(
        register ? "已有账号？登录" : "还没有账号？注册",
        () =>
          location.assign(
            (register ? "/login" : "/register") + location.search,
          ),
        "text-button",
      ),
    );
  handleForm(form, content, async (values) => {
    if (register || socialRegistration) {
      if (!options.privacyVersion)
        options = await request(oauth + "/options", { sameOrigin: true });
      values.ageConfirmed = Boolean(values.ageConfirmed);
      values.privacyAcknowledged = Boolean(values.privacyAcknowledged);
      values.privacyVersion = options.privacyVersion;
    }
    const result = socialRegistration
      ? await request(oauth + "/complete", { data: values, sameOrigin: true })
      : await request(register ? "/auth/register" : "/auth/login", {
          data: values,
        });
    finishLogin(result);
  });
}

async function showActivity(id) {
  const content = show("活动详情", "activity-page");
  const marker = dialogRequest;
  const loading = node("p", "正在加载活动详情…", "meta");
  content.append(loading);
  try {
    const { item, schedules } = await request(
      "/events/" + encodeURIComponent(id),
      { auth: true },
    );
    if (marker !== dialogRequest) return;
    loading.remove();
    $("h1", content).textContent = item.title;
    document.title = item.title + " · 搭慕 DAMU";
    const layout = node("div", null, "invitation");
    const story = node("div", null, "invitation-story");
    const details = node("aside", null, "invitation-summary");
    layout.append(story, details);
    content.append(layout);
    story.append(cover(item, "detail-cover"));
    const schedule =
      schedules?.find((entry) => entry.status === "scheduled") ??
      schedules?.[0];
    details.append(
      node(
        "p",
        [item.category_name, time(schedule?.starts_at), area(item)]
          .filter(Boolean)
          .join(" · "),
        "meta",
      ),
    );
    details.append(
      node(
        "p",
        "组织者 " + (item.organizer_name || "搭慕用户") + " · " + cost(item),
        "meta",
      ),
    );
    story.append(
      node("h2", "活动介绍"),
      node("p", item.description || "组织者还未填写活动介绍。", "detail-copy"),
    );
    const membership = item.viewer_membership_status;
    const owns = session?.user.id === item.organizer_user_id;
    const approved = ["approved", "attended"].includes(membership);
    if ((owns || approved) && (item.place_name || item.address_public)) {
      details.append(
        node(
          "p",
          [item.place_name, item.address_public].filter(Boolean).join(" · "),
          "notice",
        ),
      );
    } else if (!owns && !approved) {
      details.append(node("p", "报名通过后可查看具体集合点。", "notice"));
    }
    const labels = {
      applied: "已申请 · 等待审核",
      approved: "报名已通过",
      attended: "已参加",
      waitlisted: "候补中",
      rejected: "报名未通过",
      withdrawn: "已退出",
    };
    if (membership && !owns)
      details.append(node("p", labels[membership] ?? "已有报名记录", "meta"));
    const active =
      ["published", "full"].includes(item.status) &&
      (!schedule?.ends_at || Date.parse(schedule.ends_at) > Date.now());
    const actions = node("div", null, "detail-actions");
    if (owns)
      actions.append(
        actionLink("管理报名", "/organizer/activities/" + id, "button primary"),
      );
    if (item.organizer_user_id)
      details.append(
        actionLink(
          "查看组织者",
          "/people/" + item.organizer_user_id,
          "text-button",
        ),
      );
    if (active && !owns && !membership) {
      actions.append(
        button(
          item.approval_mode === "manual" ? "申请参加" : "报名参加",
          () => requireLogin(() => showJoin(id)),
          "button primary",
        ),
      );
    }
    if (
      active &&
      !owns &&
      ["approved", "applied", "waitlisted"].includes(membership)
    ) {
      actions.append(
        button("退出活动", async (event) => {
          if (!window.confirm("确定退出这个活动？")) return;
          const action = event.currentTarget;
          action.disabled = true;
          try {
            await request("/events/" + encodeURIComponent(id) + "/leave", {
              method: "POST",
              auth: true,
            });
            showActivity(id);
          } catch (error) {
            showError(content, error);
          } finally {
            action.disabled = false;
          }
        }),
      );
    }
    details.append(actions);
  } catch (error) {
    if (marker === dialogRequest) {
      loading.remove();
      showError(content, error);
    }
  }
}

function showJoin(id) {
  const content = show("报名参加", "reading", true);
  const form = node("form", null, "form");
  form.innerHTML =
    '<label>参加人数<input name="partySize" type="number" value="1" min="1" max="20" required></label><label>给组织者的话（选填）<textarea name="note" maxlength="300"></textarea></label><button class="button primary" type="submit">确认报名</button>';
  content.append(form);
  handleForm(form, content, async (values) => {
    await request("/events/" + encodeURIComponent(id) + "/join", {
      auth: true,
      data: {
        partySize: Number(values.partySize),
        note: values.note.trim() || null,
        shareContact: false,
      },
    });
    showActivity(id);
  });
}

async function showMine() {
  const content = show("我的活动", "workspace-page");
  const marker = dialogRequest;
  try {
    const activities = await request("/me/activities", { auth: true });
    if (marker !== dialogRequest) return;
    for (const own of [false, true]) {
      content.append(node("h2", own ? "我发起的" : "我报名的"));
      const list = node("ul", null, "detail-list");
      for (const item of activities.filter(
        (entry) => (entry.organizer_user_id === session.user.id) === own,
      )) {
        const entry = node("li");
        entry.append(
          actionLink(item.title, eventLink(item.id), "text-button"),
          node(
            "p",
            [
              time(item.starts_at),
              area(item),
              membershipLabel(item.membership_status),
            ]
              .filter(Boolean)
              .join(" · "),
            "meta",
          ),
        );
        if (own)
          entry.append(
            actionLink(
              "管理活动",
              "/organizer/activities/" + item.id,
              "button ghost",
            ),
          );
        list.append(entry);
      }
      content.append(
        list.children.length ? list : node("p", "暂无记录。", "meta"),
      );
    }
  } catch (error) {
    if (marker === dialogRequest) showError(content, error);
  }
}

async function showMessages() {
  const content = show("消息", "workspace-page");
  const marker = dialogRequest;
  try {
    const conversations = await request("/conversations", { auth: true });
    if (marker !== dialogRequest) return;
    const list = node("ul", null, "detail-list");
    for (const conversation of conversations) {
      const entry = node("li");
      const unread = conversation.unread_count
        ? " · " + conversation.unread_count + " 条未读"
        : "";
      entry.append(
        button(
          conversation.display_title + unread,
          () =>
            location.assign("/messages/" + encodeURIComponent(conversation.id)),
          "text-button",
        ),
        node("p", conversation.last_message_body || "暂无文字消息", "meta"),
      );
      list.append(entry);
    }
    content.append(
      list.children.length ? list : node("p", "还没有会话。", "meta"),
    );
  } catch (error) {
    if (marker === dialogRequest) showError(content, error);
  }
}

async function showConversation(conversation, conversations) {
  const content = show(conversation.display_title, "chat-page");
  const layout = node("div", null, "chat-layout");
  const inbox = node("nav", null, "chat-sidebar");
  inbox.setAttribute("aria-label", "会话列表");
  for (const item of conversations) {
    const link = actionLink(
      item.display_title,
      "/messages/" + item.id,
      "text-button",
    );
    if (item.id === conversation.id) link.setAttribute("aria-current", "page");
    inbox.append(link);
  }
  const thread = node("div", null, "chat-thread");
  layout.append(inbox, thread);
  content.append(layout);
  const marker = dialogRequest;
  const base = "/conversations/" + encodeURIComponent(conversation.id);
  const messages = node("ol", null, "detail-list");
  const older = button("加载更早消息", () => loadMessages(true));
  older.hidden = true;
  thread.append(
    actionLink("返回消息", "/messages", "text-button"),
    older,
    messages,
  );
  let nextCursor;
  async function loadMessages(prepend = false) {
    older.disabled = true;
    try {
      const params =
        prepend && nextCursor
          ? "?cursor=" + encodeURIComponent(nextCursor)
          : "";
      const page = await request(base + "/messages" + params, { auth: true });
      if (marker !== dialogRequest) return;
      const entries = [...page.items].reverse().map((message) => {
        const entry = node("li");
        entry.append(
          node(
            "p",
            [message.sender_name, time(message.created_at)]
              .filter(Boolean)
              .join(" · "),
            "meta",
          ),
          node(
            "p",
            message.recalled_at
              ? "消息已撤回"
              : message.body || "附件请在搭慕 App 内查看",
            "detail-copy",
          ),
        );
        return entry;
      });
      if (prepend) messages.prepend(...entries);
      else messages.replaceChildren(...entries);
      nextCursor = page.hasMore ? page.nextCursor : null;
      older.hidden = !nextCursor;
      if (!prepend && page.items[0]) {
        await request(base + "/read", {
          auth: true,
          data: { messageId: page.items[0].id },
        });
      }
    } catch (error) {
      if (marker === dialogRequest) showError(content, error);
    } finally {
      older.disabled = false;
    }
  }
  if (conversation.status === "active") {
    const form = node("form", null, "form");
    form.innerHTML =
      '<label>发送文字消息<textarea name="body" maxlength="4000" required></textarea></label><button class="button primary" type="submit">发送</button>';
    thread.append(form);
    handleForm(form, content, async (values) => {
      const body = values.body.trim();
      if (!body) throw new Error("请输入消息。");
      await request(base + "/messages", {
        auth: true,
        data: {
          messageType: "text",
          body,
          clientMessageId: crypto.randomUUID(),
        },
      });
      form.reset();
      await loadMessages();
    });
  }
  await loadMessages();
}

function showPublish() {
  const content = show("发起活动", "editor-page");
  const form = node("form", null, "form");
  form.innerHTML = `
    <label>活动名称<input name="title" required maxlength="80"></label>
    <label>活动介绍<textarea name="description" required maxlength="3000"></textarea></label>
    <div class="form-row"><label>活动分类<select name="categoryId" required></select></label><label id="custom-label" hidden>自定义分类<input name="customSubcategory" maxlength="15"></label></div>
    <div class="form-row"><label>市／道<select name="cityCode" required></select></label><label>市／郡／区<select name="districtCode" required disabled></select></label></div>
    <label id="publish-ward" hidden>下辖区<select name="wardCode" disabled></select></label>
    <div class="form-row"><label>开始时间（韩国）<input name="startsAt" type="datetime-local" required></label><label>结束时间（韩国）<input name="endsAt" type="datetime-local" required></label></div>
    <div class="form-row"><label>人数上限（含组织者）<input name="capacity" type="number" value="6" min="2" max="100" required></label><label>预计线下人均费用（₩）<input name="price" type="number" value="0" min="0" required></label></div>
    <label>集合点（报名通过后可见）<input name="place" required maxlength="100"></label>
    <label>报名方式<select name="approvalMode"><option value="manual">组织者审核</option><option value="auto">直接加入</option></select></label>
    <button class="button primary" type="submit">发布活动</button>`;
  content.append(form);
  const publishCity = $('[name="cityCode"]', form);
  const publishDistrict = $('[name="districtCode"]', form);
  const publishWard = $('[name="wardCode"]', form);
  const publishWardLabel = $("#publish-ward", form);
  const publishCategory = $('[name="categoryId"]', form);
  const custom = $('[name="customSubcategory"]', form);
  fillSelect(
    publishCity,
    regions.filter((entry) => entry.level === 1),
    "选择市／道",
    "code",
  );
  fillSelect(
    publishCategory,
    categories.filter((entry) => entry.level === 2),
    "选择分类",
    "id",
  );
  publishCategory.addEventListener("change", () => {
    const required = Boolean(
      categories.find((entry) => entry.id === publishCategory.value)
        ?.requires_custom_label,
    );
    custom.required = required;
    $("#custom-label", form).hidden = !required;
    if (!required) custom.value = "";
  });
  publishCity.addEventListener("change", () => {
    publishDistrict.value = "";
    fillSelect(
      publishDistrict,
      regionChildren(publishCity.value, 2),
      "选择市／郡／区",
      "code",
    );
    publishDistrict.disabled = !publishCity.value;
    updateWard(publishWard, publishWardLabel, "");
  });
  publishDistrict.addEventListener("change", () => {
    updateWard(
      publishWard,
      publishWardLabel,
      publishDistrict.value,
      "不指定下辖区",
    );
  });
  handleForm(form, content, async (values) => {
    const startsAt = new Date(values.startsAt + ":00+09:00");
    const endsAt = new Date(values.endsAt + ":00+09:00");
    if (endsAt <= startsAt) throw new Error("结束时间必须晚于开始时间。");
    const amount = Number(values.price);
    const item = await request("/events", {
      auth: true,
      data: {
        categoryId: values.categoryId,
        title: values.title.trim(),
        description: values.description.trim(),
        cityCode: values.cityCode,
        districtCode: values.wardCode || values.districtCode,
        startsAt: startsAt.toISOString(),
        endsAt: endsAt.toISOString(),
        minParticipants: 2,
        capacity: Number(values.capacity),
        approvalMode: values.approvalMode,
        visibility: "public",
        priceMin: amount,
        priceMax: amount,
        priceCurrency: "KRW",
        beginnerFriendly: false,
        place: { name: values.place.trim() },
        customSubcategory: values.customSubcategory.trim() || null,
        languageCodes: ["zh"],
      },
    });
    location.assign(eventLink(item.id));
  });
}

async function finishSocial() {
  const content = show("正在登录");
  const marker = dialogRequest;
  try {
    const result = await request(oauth + "/complete", {
      data: {},
      sameOrigin: true,
    });
    if (marker !== dialogRequest) return;
    if (result.registrationRequired) {
      options.privacyVersion = result.privacyVersion;
      showLogin(false, true);
    } else finishLogin(result);
  } catch (error) {
    if (marker === dialogRequest) showLogin(false, false, error.message);
  }
}

function membershipLabel(value) {
  return (
    {
      applied: "待审核",
      approved: "已通过",
      attended: "已参加",
      waitlisted: "候补",
      rejected: "未通过",
      withdrawn: "已退出",
    }[value] ?? ""
  );
}

async function showOrganizer(id) {
  const content = show("组织者工作台", "workspace-page");
  const marker = dialogRequest;
  const base = "/events/" + encodeURIComponent(id);
  try {
    const [event, members] = await Promise.all([
      request(base, { auth: true }),
      request(base + "/members", { auth: true }),
    ]);
    if (marker !== dialogRequest) return;
    content.append(
      node("h2", event.item.title),
      actionLink("查看活动", eventLink(id)),
      actionLink("编辑活动", "/organizer/activities/" + id + "/edit"),
    );
    const list = node("ul", null, "detail-list");
    for (const member of members.filter(
      (entry) => entry.user_id !== session.user.id,
    )) {
      const row = node("li");
      row.append(
        node("strong", member.nickname ?? "搭慕用户"),
        node(
          "p",
          [
            membershipLabel(member.status),
            member.party_size + " 人",
            member.application_note,
          ]
            .filter(Boolean)
            .join(" · "),
          "meta",
        ),
      );
      if (["applied", "waitlisted"].includes(member.status)) {
        const actions = node("div", null, "detail-actions");
        async function review(approved, reason) {
          await request(
            base +
              "/members/" +
              encodeURIComponent(member.user_id) +
              (approved ? "/approve" : "/reject"),
            {
              method: "POST",
              auth: true,
              data: approved ? undefined : { reason },
            },
          );
          showOrganizer(id);
        }
        actions.append(
          button(
            "通过",
            async (event) => {
              const trigger = event.currentTarget;
              trigger.disabled = true;
              try {
                await review(true);
              } catch (error) {
                showError(content, error);
              } finally {
                trigger.disabled = false;
              }
            },
            "button primary",
          ),
          button("拒绝", () =>
            reasonDialog("拒绝报名", (reason) => review(false, reason)),
          ),
        );
        row.append(actions);
      }
      list.append(row);
    }
    content.append(
      node("h2", "报名名单"),
      list.children.length ? list : node("p", "还没有人报名。", "meta"),
    );
    if (["published", "full"].includes(event.item.status)) {
      content.append(
        button("取消活动", () =>
          reasonDialog("取消活动", async (reason) => {
            await request(base + "/cancel", { auth: true, data: { reason } });
            showOrganizer(id);
          }),
        ),
      );
    }
  } catch (error) {
    if (marker === dialogRequest) showError(content, error);
  }
}

function reasonDialog(title, action) {
  const content = show(title, "reading", true);
  const form = node("form", null, "form");
  form.innerHTML =
    '<label>填写原因<textarea name="reason" minlength="2" maxlength="300" required></textarea></label><button class="button primary" type="submit">确认</button>';
  content.append(form);
  handleForm(form, content, (values) => action(values.reason.trim()));
}

async function showEdit(id) {
  const content = show("编辑活动", "editor-page");
  const marker = dialogRequest;
  const base = "/events/" + encodeURIComponent(id);
  try {
    const { item } = await request(base, { auth: true });
    if (marker !== dialogRequest) return;
    if (item.organizer_user_id !== session.user.id)
      throw new Error("只有组织者可以编辑。");
    const form = node("form", null, "form");
    form.innerHTML =
      '<label>活动名称<input name="title" required maxlength="80"></label><label>活动介绍<textarea name="description" required maxlength="3000"></textarea></label><button type="submit" class="button primary">保存</button>';
    form.elements.title.value = item.title ?? "";
    form.elements.description.value = item.description ?? "";
    content.append(
      actionLink("返回工作台", "/organizer/activities/" + id),
      form,
    );
    handleForm(form, content, async (values) => {
      await request(base, {
        method: "PATCH",
        auth: true,
        data: {
          title: values.title.trim(),
          description: values.description.trim(),
          rowVersion: item.row_version,
        },
      });
      location.assign("/organizer/activities/" + id);
    });
  } catch (error) {
    if (marker === dialogRequest) showError(content, error);
  }
}
async function showSettings() {
  const content = show("个人设置", "account-page");
  const form = node("form", null, "form");
  form.innerHTML =
    '<label>昵称<input name="nickname" required minlength="2" maxlength="30"></label><button type="submit" class="button primary">保存昵称</button>';
  form.elements.nickname.value = session.user.nickname ?? "";
  content.append(
    form,
    actionLink("查看公开主页", "/people/" + session.user.id),
    button("退出登录", () => {
      setSession(null);
      location.assign("/");
    }),
  );
  handleForm(form, content, async (values) => {
    const updated = await request("/me", {
      method: "PATCH",
      auth: true,
      data: { nickname: values.nickname.trim() },
    });
    setSession({
      ...session,
      user: { ...session.user, nickname: updated.nickname },
    });
    $(".notice", content)?.remove();
    content.append(node("p", "昵称已保存。", "notice"));
  });
}

async function showPerson(id) {
  const content = show("用户主页", "profile-page");
  const marker = dialogRequest;
  try {
    const user = await request(
      "/users/" + encodeURIComponent(id) + "/public-profile",
      { auth: true },
    );
    if (marker !== dialogRequest) return;
    $("h1", content).textContent = user.nickname ?? "搭慕用户";
    const url = uploadedImage(user.avatar_url);
    if (url) {
      const avatar = node("img", null, "profile-avatar");
      avatar.src = url;
      avatar.alt = "";
      content.prepend(avatar);
    }
    content.append(node("p", "获赞 " + (user.like_count ?? 0), "meta"));
  } catch (error) {
    if (marker === dialogRequest) showError(content, error);
  }
}

const guides = [
  {
    slug: "river-walk",
    kind: "outdoors",
    title: "把周末留一段给散步",
    lead: "一场不赶时间的汉江散步，适合一个人出门，也适合和新朋友见面。",
    steps: [
      "选一个双方都熟悉的公共入口，约定出发时间。",
      "先走一小段，走累了就休息，不必把路线排满。",
      "出发前核对天气和交通，遇到大雨就改约室内。",
    ],
  },
  {
    slug: "coffee-meet",
    kind: "food",
    title: "第一次咖啡局，怎么开场",
    lead: "想认识新朋友，可以从一杯咖啡和一个简单话题开始。",
    steps: [
      "约定各自消费，提前说明预算和聚会时长。",
      "选公共场所，把场馆和无障碍需求考虑进去。",
      "准备一个轻松话题，例如最近想去的地方。",
    ],
  },
  {
    slug: "photo-walk",
    kind: "culture",
    title: "在熟悉的街区做一次观察练习",
    lead: "给自己定一个小主题，带着手机在附近走走。",
    steps: [
      "从颜色、店招或街角光影里选一个主题。",
      "拍摄人物前先征得同意，避免打扰他人。",
      "回家选三张照片，写下你为什么停下来。",
    ],
  },
];
function showGuides(slug) {
  const guide = guides.find((entry) => entry.slug === slug);
  if (slug && !guide) return showNotFound();
  const content = show(
    guide?.title ?? "周末指南",
    guide ? "guide-article" : "workspace-page",
  );
  content.append(
    node("p", guide?.lead ?? "搭慕编辑部 · 给想出门的人一些灵感。", "meta"),
  );
  if (guide) {
    content.append(cover({ cover_category_code: guide.kind }, "detail-cover"));
    const list = node("ol", null, "guide-steps");
    for (const step of guide.steps) list.append(node("li", step));
    content.append(
      list,
      actionLink("发现活动", "/explore"),
      actionLink("返回指南", "/guides", "text-button"),
    );
  } else {
    const grid = node("div", null, "cards guide-grid");
    for (const entry of guides) {
      const item = node("article", null, "card");
      const picture = actionLink("", "/guides/" + entry.slug, "cover");
      picture.setAttribute("aria-label", entry.title);
      picture.append(cover({ cover_category_code: entry.kind }));
      item.append(
        picture,
        actionLink(entry.title, "/guides/" + entry.slug, "guide-title"),
        node("p", entry.lead, "meta"),
      );
      grid.append(item);
    }
    content.append(grid);
  }
}
function showNotFound() {
  const content = show("没有找到这个页面");
  content.append(actionLink("返回发现活动", "/explore"));
}
async function route() {
  const path = location.pathname;
  for (const link of document.querySelectorAll(".masthead nav a")) {
    if (link.pathname === path || path.startsWith(link.pathname + "/"))
      link.setAttribute("aria-current", "page");
  }
  const hash = location.hash;
  const legacy = /^#activity\/([0-9a-f-]{36})$/i.exec(hash);
  if (legacy) return location.replace(eventLink(legacy[1]));
  if (hash === "#social-complete" || hash === "#social-error") {
    history.replaceState(null, "", "/auth/complete");
    return hash === "#social-complete"
      ? finishSocial()
      : showLogin(false, false, "第三方授权未完成，请重试或使用邮箱登录。");
  }
  if (path === "/" || path === "/explore") {
    browse.hidden = false;
    if (path === "/explore") {
      $("#filters").append(actionLink("清除筛选", "/explore", "text-button"));
      $(".hero-art").hidden = true;
      $(".hero").classList.add("explore-hero");
      $("#hero-title").textContent = "发现活动";
      $(".intro").textContent = "按地区和兴趣，找一场想参加的活动。";
    } else {
      $("#filters").hidden = true;
      $("#categories").hidden = true;
      $("#gallery-title").textContent = "近期活动";
      $(".toolbar").append(actionLink("查看全部", "/explore"));
      const preview = node("section", null, "gallery home-guides");
      preview.append(
        node("p", "DAMU EDITORIAL", "eyebrow"),
        node("h2", "周末去哪儿？"),
        node("p", "散步、看展，或和新朋友喝一杯咖啡。", "meta"),
        actionLink("浏览周末指南", "/guides"),
      );
      browse.append(preview);
    }
    await setupFeed();
    return;
  }
  const activity = /^\/activities\/([0-9a-f-]{36})$/i.exec(path);
  if (activity) return showActivity(activity[1]);
  if (path === "/login" || path === "/register")
    return showLogin(path === "/register");
  if (path === "/auth/complete") return finishSocial();
  if (path === "/guides" || path.startsWith("/guides/"))
    return showGuides(path.split("/")[2]);
  if (path === "/activities/new")
    return requireLogin(async () => {
      try {
        [regions, categories] = await Promise.all([
          request("/regions"),
          request("/categories"),
        ]);
        showPublish();
      } catch (error) {
        showError(show("发起活动"), error);
      }
    });
  const editor = /^\/organizer\/activities\/([0-9a-f-]{36})\/edit$/i.exec(path);
  if (editor) return requireLogin(() => showEdit(editor[1]));
  if (path === "/help" || path === "/safety") {
    const help = path === "/help";
    const content = show(help ? "使用帮助" : "线下见面安全");
    content.append(
      node(
        "p",
        help
          ? "可以先浏览活动，登录后报名、发起活动或查看消息。"
          : "优先选择公开场所。集合点只向有权限的参与者显示。请提前核对时间、交通与预计花费。",
        "detail-copy",
      ),
      actionLink(
        help ? "查看见面安全" : "查看使用帮助",
        help ? "/safety" : "/help",
      ),
    );
    return;
  }
  if (path === "/privacy")
    return location.replace("https://www.damumu.com/privacy.html");
  const organizer = /^\/organizer\/activities\/([0-9a-f-]{36})$/i.exec(path);
  if (organizer) return requireLogin(() => showOrganizer(organizer[1]));
  const person = /^\/people\/([0-9a-f-]{36})$/i.exec(path);
  if (person) return showPerson(person[1]);
  if (path === "/me/activities") return requireLogin(showMine);
  if (path === "/messages") return requireLogin(showMessages);
  const conversation = /^\/messages\/([0-9a-f-]{36})$/i.exec(path);
  if (conversation)
    return requireLogin(async () => {
      try {
        const list = await request("/conversations", { auth: true });
        const item = list.find((entry) => entry.id === conversation[1]);
        if (item) showConversation(item, list);
        else showNotFound();
      } catch (error) {
        showError(show("消息"), error);
      }
    });
  if (path === "/settings/profile") return requireLogin(showSettings);
  showNotFound();
}

function syncFilters() {
  if (location.pathname !== "/explore") return;
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries({
    q: query,
    city: city.value,
    district: district.value,
    ward: ward.value,
    day: $("#day").value,
    category,
    sort: $("#sort").value,
  }))
    if (value) params.set(key, value);
  history.replaceState(
    null,
    "",
    "/explore" + (params.size ? "?" + params : ""),
  );
}
function refreshFeed() {
  syncFilters();
  loadFeed();
}
function loadDistricts() {
  district.value = "";
  fillSelect(district, regionChildren(city.value, 2), "全部地区", "code");
  district.disabled = !city.value;
}
async function setupFeed() {
  const params = new URLSearchParams(location.search);
  query = params.get("q") ?? "";
  category = params.get("category") ?? "";
  $("#query").value = query;
  $("#day").value = params.get("day") ?? "";
  $("#sort").value = params.get("sort") ?? "recommended";
  const [regionData, categoryData] = await Promise.allSettled([
    request("/regions"),
    request("/categories"),
  ]);
  if (regionData.status === "fulfilled") {
    regions = regionData.value;
    fillSelect(
      city,
      regions.filter((entry) => entry.level === 1),
      "全部市／道",
      "code",
    );
    city.value = params.get("city") ?? "";
    loadDistricts();
    district.value = params.get("district") ?? "";
    updateWard(ward, $("#ward-filter"), district.value);
    ward.value = params.get("ward") ?? "";
  }
  if (categoryData.status === "fulfilled") categories = categoryData.value;
  renderCategories();
  loadFeed();
}

$("#search").addEventListener("submit", (event) => {
  event.preventDefault();
  query = $("#query").value.trim();
  if (location.pathname === "/")
    return location.assign("/explore?" + new URLSearchParams({ q: query }));
  refreshFeed();
});
city.addEventListener("change", () => {
  loadDistricts();
  updateWard(ward, $("#ward-filter"), "");
  refreshFeed();
});
district.addEventListener("change", () => {
  updateWard(ward, $("#ward-filter"), district.value);
  refreshFeed();
});
ward.addEventListener("change", refreshFeed);
$("#sort").addEventListener("change", refreshFeed);
$("#day").addEventListener("change", refreshFeed);
more.addEventListener("click", () => loadFeed(true));
$("#close").addEventListener("click", () => dialog.close());
setSession(session);
route();

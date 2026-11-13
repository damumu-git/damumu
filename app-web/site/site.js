import { createCommunityPages } from "/community-pages.js";
import { createMemberPages } from "/member-pages.js";
import { conversationRoute, createChatPage } from "/chat-page.js";
import { createBrowseFilters } from "/browse-filters.js";
import { dateQuery } from "/seoul-dates.js";
import { setupSchedulePicker } from "/date-picker.js";
import { createDirectContact } from "/direct-contact.js";
import { createActivitySeries } from "/activity-series.js";
import { installSelectMenus } from "/select-menu.js";
const apiRoot = "https://api.damumu.com";
const appStoreLinks = [
  { label: "App Store", url: "" },
  { label: "Google Play", url: "" },
];
const oauth = "/api/v1/auth/web";
const $ = (selector, root = document) => root.querySelector(selector);
const dialog = $("#dialog");
const panel = $("#panel");
const page = $("#page");
const browse = $("#browse");
const cards = $("#cards");
const status = $("#status");
const login = $("#login");
const myMenu = $("#my-menu");
const messagesMenu = $("#messages-menu");
const messageCount = $(".message-count", messagesMenu);
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
let unreadRequest;

function setSession(value) {
  const wasSignedIn = !messagesMenu.hidden;
  session = value;
  if (value) sessionStorage.setItem("damu-session", JSON.stringify(value));
  else sessionStorage.removeItem("damu-session");
  login.hidden = Boolean(value);
  myMenu.hidden = !value;
  messagesMenu.hidden = !value;
  if (!value) myMenu.open = false;
  renderAvatar($(".account-avatar", myMenu), value?.user);
  if (!value) {
    unreadRequest?.abort();
    renderMessageCount(messageCount, 0);
  } else if (!wasSignedIn) refreshUnread();
}

function renderMessageCount(badge, count) {
  badge.hidden = !count;
  badge.textContent = count > 99 ? "99+" : String(count);
  badge.setAttribute("aria-label", count + " 条未读");
}

async function refreshUnread() {
  if (!session) return;
  unreadRequest?.abort();
  const controller = new AbortController();
  unreadRequest = controller;
  try {
    const summary = await request("/unread-summary", { auth: true, signal: controller.signal });
    if (controller.signal.aborted) return;
    renderMessageCount(messageCount, (summary?.message_count ?? 0) +
      (summary?.announcement_count ?? 0) + (summary?.contact_request_count ?? 0));
    document.dispatchEvent(new CustomEvent("damu-unread", { detail: summary }));
  } catch {
    // A later refresh can recover without interrupting the page.
  }
}

async function request(
  path,
  { data, signal, auth = false, sameOrigin = false, method } = {},
) {
  const headers = {};
  const isForm = data instanceof FormData;
  if (data !== undefined && !isForm)
    headers["Content-Type"] = "application/json";
  if (auth && session?.accessToken)
    headers.Authorization = "Bearer " + session.accessToken;
  const response = await fetch((sameOrigin ? "" : apiRoot + "/api/v1") + path, {
    headers,
    signal,
    method: method ?? (data === undefined ? "GET" : "POST"),
    body: isForm ? data : data === undefined ? undefined : JSON.stringify(data),
  });
  if (response.status === 204) return null;
  if (response.status === 429) {
    const retryAfter = response.headers.get("Retry-After");
    const seconds = /^\d+$/.test(retryAfter ?? "") ? Number(retryAfter) : 0;
    throw new Error(seconds > 0
      ? `操作过于频繁，请在 ${seconds} 秒后再试。`
      : "操作过于频繁，请稍后再试。");
  }
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

function categoryChildren(parent) {
  return categories.filter((entry) => entry.level === 2 && entry.parent_id === parent);
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
function renderAvatar(container, user) {
  container.textContent = Array.from(user?.nickname?.trim() || "搭")[0];
  const url = uploadedImage(user?.avatarImageUrl) ?? uploadedImage(user?.avatarUrl);
  if (url) {
    const image = node("img");
    image.alt = "";
    image.addEventListener("error", () => image.remove(), { once: true });
    image.src = url;
    container.append(image);
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
  const candidates = [uploadedImage(item.cover_url), uploadedImage(item.category_cover_url), specific, fallback].filter(
    Boolean,
  );
  image.addEventListener("error", () => {
    if (candidates.length) image.src = candidates.shift();
  });
  image.src = candidates.shift();
  return image;
}

function libraryRow(item, { href, categoryName, state, summary, action }) {
  const entry = node("li", null, "library-row");
  const link = actionLink("", href, "library-item-link");
  const thumbnail = node("span", null, "library-thumbnail");
  thumbnail.append(cover(item));
  const body = node("div", null, "library-body");
  const labels = node("div", null, "library-labels");
  if (categoryName) labels.append(node("span", categoryName, "library-category"));
  if (state) labels.append(node("span", state, "library-state"));
  const details = [item.starts_at && time(item.starts_at), area(item)].filter(Boolean);
  body.append(node("h3", item.title));
  if (labels.childElementCount) body.prepend(labels);
  if (details.length) body.append(node("p", details.join(" · "), "library-meta"));
  if (summary?.trim()) body.append(node("p", summary, "library-summary"));
  link.append(thumbnail, body);
  entry.append(link);
  if (action) {
    action.classList.add("library-action");
    entry.append(action);
  }
  return entry;
}

function libraryEventState(item, now = Date.now()) {
  const status = item.event_status ?? item.status;
  if (status === "cancelled") return "已取消";
  if (status === "completed" || Date.parse(item.ends_at) <= now) return "已结束";
  if (status === "full") return "已满员";
  return "";
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

function renderCategories(focusLevel) {
  const selected = categories.find((entry) => entry.id === category);
  const major = selected?.level === 2 ? selected.parent_id : selected?.id ?? "";
  const majors = categories.filter((entry) => entry.level === 1);
  const minors = major ? categoryChildren(major) : [];
  const groups = $("#categories");
  const rows = [];
  let nextFocus;
  function categoryRow(title, options, active) {
    const group = node("div", null, "category-group");
    const row = node("div", null, "categories");
    row.setAttribute("role", "group");
    row.setAttribute("aria-label", title);
    for (const entry of options) {
      const item = button(entry.name_zh_cn, () => {
        category = entry.id;
        renderCategories(title);
        refreshFeed();
      });
      const pressed = active === entry.id;
      item.setAttribute("aria-pressed", String(pressed));
      if (focusLevel === title && pressed) nextFocus = item;
      row.append(item);
    }
    group.append(node("span", title, "category-group-label"), row);
    return group;
  }
  if (majors.length) rows.push(categoryRow("大分类", [{ id: "", name_zh_cn: "全部大类" }, ...majors], major));
  if (minors.length) rows.push(categoryRow("小分类", [{ id: major, name_zh_cn: "全部小类" }, ...minors], category));
  groups.replaceChildren(...rows);
  nextFocus?.focus({ preventScroll: true });
}

async function loadFeed(append = false) {
  feedRequest?.abort();
  const controller = new AbortController();
  feedRequest = controller;
  const params = new URLSearchParams({
    limit: location.pathname === "/" ? "8" : "20",
  });
  const { city, district, ward } = browseFilters.values();
  const range = browseFilters.range();
  const following = location.pathname === "/explore" && new URLSearchParams(location.search).get("feed") === "following";
  if (following) params.set("following", "true");
  for (const [key, value] of Object.entries({
    city,
    district: ward || district,
    sort: $("#sort").value,
    q: query,
    categoryId: category,
    cursor: append ? cursor : null,
    ...(range ? dateQuery(range) : {}),
  }))
    if (value) params.set(key, value);
  const maxPrice = $("#max-price").value;
  if (maxPrice) params.set("maxPrice", maxPrice);
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
      auth: following,
    });
    if (feedRequest !== controller) return;
    cards.append(...page.items.map(card));
    feedCount += page.items.length;
    cursor = page.hasMore ? page.nextCursor : null;
    status.textContent = feedCount
      ? "已展示 " + feedCount + " 场活动"
      : following
        ? "你关注的人暂时没有符合筛选条件的活动。可以调整筛选，或到活动详情关注组织者。"
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
    if (submit.disabled) return;
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

const activityActionIcons = {
  join: "M12 5v14M5 12h14",
  manage: "M9 6h11M9 12h11M9 18h11M4 6h1M4 12h1M4 18h1",
  leave: "M10 5H5v14h5m3-11 4 4-4 4m-4-4h8",
  bookmark: "M6 4h12v16l-6-4-6 4z",
  feedback: "m12 3 2.7 5.5 6.1.9-4.4 4.3 1 6.1-5.4-2.9-5.4 2.9 1-6.1L3.2 9.4l6.1-.9z",
  report: "M5 21V4m0 1c4-4 7 3 13 0v10c-6 3-9-4-13 0",
  inquiry: "M4 5h16v12H9l-5 3zM8 9h8m-8 4h5",
};

function activityAction(control, kind) {
  const namespace = "http://www.w3.org/2000/svg";
  const icon = document.createElementNS(namespace, "svg");
  icon.setAttribute("viewBox", "0 0 24 24");
  icon.setAttribute("aria-hidden", "true");
  icon.setAttribute("focusable", "false");
  const path = document.createElementNS(namespace, "path");
  path.setAttribute("d", activityActionIcons[kind]);
  icon.append(path);
  control.classList.add("activity-action", "activity-action-" + kind);
  control.prepend(icon);
  return control;
}

async function showActivity(id) {
  const content = show("活动详情", "activity-page");
  const marker = dialogRequest;
  const loading = node("p", "正在加载活动详情…", "meta");
  content.append(loading);
  try {
    const { item, schedules, customFeedbackTags } = await request(
      "/events/" + encodeURIComponent(id),
      { auth: true },
    );
    if (marker !== dialogRequest) return;
    loading.remove();
    $("h1", content).textContent = item.title;
    document.title = item.title + " · 搭慕 DAMU";
    const layout = node("div", null, "invitation");
    const details = node("section", null, "activity-section");
    layout.append(cover(item, "detail-cover"), details);
    content.append(layout);
    const schedule =
      schedules?.find((entry) => entry.status === "scheduled") ??
      schedules?.[0];
    const organizer = item.organizer_name || "搭慕用户";
    const facts = node("dl", null, "activity-facts");
    const starts = time(schedule?.starts_at);
    const ends = schedule?.ends_at ? time(schedule.ends_at) : "";
    const addFact = (label, value) => {
      if (!value) return;
      const row = node("div");
      const description = node("dd");
      description.append(value);
      row.append(node("dt", label), description);
      facts.append(row);
    };
    addFact("分类", item.category_name);
    addFact("时间", [starts, ends].filter(Boolean).join(" 至 "));
    addFact("地区", area(item));
    addFact("人均费用", cost(item));
    const identity = item.organizer_user_id
      ? actionLink(
          "",
          "/people/" + encodeURIComponent(item.organizer_user_id),
          "activity-organizer",
        )
      : node("span", null, "activity-organizer");
    const organizerAvatar = node("span", null, "account-avatar");
    organizerAvatar.setAttribute("aria-hidden", "true");
    renderAvatar(organizerAvatar, {
      nickname: organizer,
      avatarImageUrl: item.organizer_avatar,
    });
    identity.append(organizerAvatar, node("span", organizer));
    addFact("组织者", identity);
    details.append(node("h2", "活动信息"), facts);
    const membership = item.viewer_membership_status;
    const owns = session?.user.id === item.organizer_user_id;
    const approved = ["approved", "attended"].includes(membership);
    if ((owns || approved) && (item.place_name || item.address_public)) {
      addFact(
        "集合点",
        [item.place_name, item.address_public].filter(Boolean).join(" · "),
      );
    } else if (!owns && !approved) {
      details.append(node("p", "报名通过后可查看具体集合点。", "notice"));
    }
    if (item.description?.trim()) {
      const introduction = node("section", null, "activity-section");
      introduction.append(
        node("h2", "活动介绍"),
        node("p", item.description, "detail-copy"),
      );
      layout.append(introduction);
    }
    if (customFeedbackTags?.length) {
      const feedback = node("section", null, "activity-section");
      const labels = node("ul", null, "feedback-chips feedback-summary");
      for (const { label, count } of customFeedbackTags)
        labels.append(node("li", label + " · " + count, "button ghost"));
      feedback.append(node("h2", "参与者的评价标签"), labels);
      layout.append(feedback);
    }
    const participation = node("section", null, "activity-section");
    participation.append(node("h2", "活动参与"));
    const labels = {
      applied: "已申请 · 等待审核",
      approved: "报名已通过",
      attended: "已参加",
      waitlisted: "候补中",
      rejected: "报名未通过",
      withdrawn: "已退出",
    };
    if (membership && !owns)
      participation.append(
        node("p", labels[membership] ?? "已有报名记录", "meta"),
      );
    const active =
      ["published", "full"].includes(item.status) &&
      (!schedule?.ends_at || Date.parse(schedule.ends_at) > Date.now());
    const actions = node("div", null, "activity-actions");
    if (owns) {
      const manage = actionLink(
        "管理报名", "/organizer/activities/" + id, "button primary",
      );
      actions.append(activityAction(manage, "manage"));
    }
    if (active && !owns && !membership) {
      const join = button(
        item.approval_mode === "manual" ? "申请参加" : "报名参加",
        () => requireLogin(() => showJoin(id)),
        "button primary",
      );
      actions.append(activityAction(join, "join"));
    }
    if (active && !owns && item.visibility === "public") {
      actions.append(activityAction(button("咨询组织者", () => directContact.compose("inquiry", id)), "inquiry"));
    }
    if (
      active &&
      !owns &&
      ["approved", "applied", "waitlisted"].includes(membership)
    ) {
      const leave = button("退出活动", async (event) => {
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
      });
      actions.append(activityAction(leave, "leave"));
    }
    actions.append(
      activityAction(memberPages.bookmark("activity", id), "bookmark"),
      activityAction(actionLink("活动后评价", eventLink(id) + "/feedback"), "feedback"),
    );
    if (!owns) {
      const report = button("举报活动", () =>
        requireLogin(() =>
          showReport("activity", id, item.organizer_user_id ?? null),
        ),
      );
      actions.append(activityAction(report, "report"));
    }
    participation.append(actions);
    layout.append(participation);
    activitySeries.activityLinks(id, participation);
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
  const content = show("我的活动", "workspace-page library-page");
  const marker = dialogRequest;
  const statuses = {
    all: "全部",
    upcoming: "进行中与待开始",
    ended: "已结束",
    cancelled: "已取消",
  };
  const requestedStatus = new URLSearchParams(location.search).get("status");
  const status = Object.hasOwn(statuses, requestedStatus) ? requestedStatus : "all";
  const filters = node("nav", null, "activity-status-filters");
  filters.setAttribute("aria-label", "活动状态");
  for (const [value, label] of Object.entries(statuses)) {
    const link = actionLink(
      label,
      value === "all" ? location.pathname : `${location.pathname}?status=${value}`,
      value === status ? "button primary" : "button ghost",
    );
    if (value === status) link.setAttribute("aria-current", "page");
    filters.append(link);
  }
  content.append(filters);
  try {
    const activities = await request("/me/activities", { auth: true });
    if (marker !== dialogRequest) return;
    const now = Date.now();
    const filtered = activities.filter((item) => {
      if (status === "all") return true;
      if (item.event_status === "cancelled") return status === "cancelled";
      const ended = libraryEventState(item, now) === "已结束";
      return status === (ended ? "ended" : "upcoming");
    });
    for (const own of [false, true]) {
      const section = node("section", null, "library-section");
      section.append(node("h2", own ? "我发起的" : "我报名的"));
      const list = node("ul", null, "library-list");
      for (const item of filtered.filter(
        (entry) => (entry.organizer_user_id === session.user.id) === own,
      )) {
        const state = [libraryEventState(item, now), !own && membershipLabel(item.membership_status)]
          .filter(Boolean).join(" · ");
        list.append(libraryRow(item, {
          href: eventLink(item.id),
          categoryName: item.category_name,
          state,
          action: own ? actionLink("管理活动", "/organizer/activities/" + item.id) : null,
        }));
      }
      section.append(
        list.children.length ? list : node("p", "暂无记录。", "meta"),
      );
      content.append(section);
    }
  } catch (error) {
    if (marker === dialogRequest) showError(content, error);
  }
}

async function uploadCover(file) {
  if (!file?.size) return null;
  if (file.size > 15 * 1024 * 1024)
    throw new Error("请选择小于 15 MB 的图片。");
  const bitmap = await createImageBitmap(file);
  const canvas = node("canvas");
  canvas.width = 1280;
  canvas.height = 960;
  try {
    const context = canvas.getContext("2d", { alpha: false });
    const scale = Math.max(
      canvas.width / bitmap.width,
      canvas.height / bitmap.height,
    );
    const width = bitmap.width * scale;
    const height = bitmap.height * scale;
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(
      bitmap,
      (canvas.width - width) / 2,
      (canvas.height - height) / 2,
      width,
      height,
    );
  } finally {
    bitmap.close();
  }
  const jpeg = await new Promise((resolve) =>
    canvas.toBlob(resolve, "image/jpeg", 0.82),
  );
  if (!jpeg || jpeg.size > 1536000)
    throw new Error("图片压缩后仍超过 1.5 MB。");
  const form = new FormData();
  form.append("cover", jpeg, "cover.jpg");
  return (await request("/events/covers", { auth: true, data: form }))
    .coverMediaId;
}

function showPublish(template, seriesId) {
  const content = show("发起活动", "editor-page");
  const form = node("form", null, "form");
  form.innerHTML = `
    <label class="cover-picker">
      <span id="cover-heading">活动封面（选填）</span>
      <span class="cover-picker-tile">
        <span class="cover-camera" aria-hidden="true"></span>
        <span aria-hidden="true">选图片</span>
        <input name="cover" type="file" accept="image/jpeg,image/png,image/webp" aria-labelledby="cover-heading">
      </span>
      <span class="cover-file-name meta" role="status" hidden></span>
    </label>
    <label>活动名称<input name="title" required maxlength="80"></label>
    <label>活动介绍（选填）<textarea name="description" maxlength="3000"></textarea></label>
    <div class="form-row"><label>大分类<select name="majorCategory" required></select></label><label>小分类<select name="categoryId" required disabled></select></label></div>
    <label id="custom-label" hidden>自定义小分类<input name="customSubcategory" maxlength="15"></label>
    <div class="form-row publish-regions"><label>市／道<select name="cityCode" required></select></label><label>市／郡／区<select name="districtCode" required disabled></select></label><label>下辖区<select name="wardCode" disabled></select></label></div>
    <div class="form-row">
      <div class="schedule-field"><span id="start-label">开始时间（韩国）</span><button type="button" class="schedule-trigger" data-schedule="startsAt" aria-labelledby="start-label start-value"><span class="schedule-icon" aria-hidden="true"></span><span id="start-value" class="schedule-value">选择日期和时间</span></button><input type="hidden" name="startsAt"></div>
      <div class="schedule-field"><span id="end-label">结束时间（韩国）</span><button type="button" class="schedule-trigger" data-schedule="endsAt" aria-labelledby="end-label end-value"><span class="schedule-icon" aria-hidden="true"></span><span id="end-value" class="schedule-value">选择日期和时间</span></button><input type="hidden" name="endsAt"></div>
    </div>
    <div class="form-row"><label>人数上限（含组织者）<input name="capacity" type="number" value="6" min="2" max="100" required></label><label>预计线下人均费用（₩）<input name="price" type="text" inputmode="numeric" value="0" required></label></div>
    <label>集合点（报名通过后可见）<input name="place" required maxlength="100"></label>
    <label>报名方式<select name="approvalMode"><option value="manual">组织者审核</option><option value="auto">直接加入</option></select></label>
    <button class="button primary" type="submit">发布活动</button>`;
  const layout = node("div", null, "publish-layout");
  const preview = node("aside", null, "invitation-summary");
  const previewTitle = node("h2", "活动卡片预览");
  const previewCover = cover({}, "detail-cover");
  const previewMeta = node("p", "选择分类与地区后显示在这里。", "meta");
  preview.append(previewCover, previewTitle, previewMeta);
  layout.append(form, preview);
  content.append(layout);
  setupSchedulePicker(form, content, { node, button });
  const price = form.elements.price;
  const majorCategory = form.elements.majorCategory;
  const publishCategory = form.elements.categoryId;
  const custom = form.elements.customSubcategory;
  const publishCity = form.elements.cityCode;
  const publishDistrict = form.elements.districtCode;
  const publishWard = form.elements.wardCode;
  const numberValue = (value) => Number(value.replaceAll(",", ""));
  const formatWon = (value) => value.replace(/[^0-9]/g, "").replace(/^0+(?=\d)/, "").replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  price.addEventListener("input", () => {
    const before = price.value;
    const formatted = formatWon(before);
    if (formatted === before) return;
    let digitsAfter = before.slice(price.selectionEnd).replace(/\D/g, "").length;
    let caret = formatted.length;
    while (caret && digitsAfter) {
      caret--;
      if (formatted[caret] !== ",") digitsAfter--;
    }
    price.value = formatted;
    price.setSelectionRange(caret, caret);
  });
  let objectUrl;
  let selectedPicture;
  const fileName = $(".cover-file-name", form);
  function updatePreview() {
    const picture = form.elements.cover.files[0];
    if (picture !== selectedPicture) {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      selectedPicture = picture;
      objectUrl = picture ? URL.createObjectURL(picture) : null;
      fileName.textContent = picture?.name ?? "";
      fileName.hidden = !picture;
    }
    const selected = categories.find(
      (item) => item.id === form.elements.categoryId.value,
    );
    const code = selected?.code;
    const major = categories.find((item) => item.id === majorCategory.value);
    previewCover.src =
      objectUrl ||
      uploadedImage(selected?.cover_image_url || major?.cover_image_url) ||
      (code && /^[a-z0-9_]+$/.test(code)
        ? "/assets/covers/sub/" + code + ".webp"
        : "/assets/covers/other.webp");
    previewTitle.textContent =
      form.elements.title.value.trim() || "活动卡片预览";
    previewMeta.textContent = [
      categories.find((item) => item.id === majorCategory.value)?.name_zh_cn,
      selected?.requires_custom_label ? custom.value.trim() || selected.name_zh_cn : selected?.name_zh_cn,
      ...[publishCity, publishDistrict, publishWard].map((field) => region(field.value)?.name_zh_cn),
      cost({ price_amount: numberValue(price.value) }),
    ]
      .filter(Boolean)
      .join(" · ");
  }
  previewCover.addEventListener("error", () => {
    if (!previewCover.src.endsWith("/assets/covers/other.webp"))
      previewCover.src = "/assets/covers/other.webp";
  });
  form.addEventListener("input", updatePreview);
  form.addEventListener("change", updatePreview);
  fillSelect(
    publishCity,
    regions.filter((entry) => entry.level === 1),
    "选择市／道",
    "code",
  );
  fillSelect(
    majorCategory,
    categories.filter((entry) => entry.level === 1),
    "选择大分类",
    "id",
  );
  function syncCustomCategory() {
    const required = Boolean(
      categories.find((entry) => entry.id === publishCategory.value)
        ?.requires_custom_label,
    );
    custom.required = required;
    $("#custom-label", form).hidden = !required;
    if (!required) custom.value = "";
  }
  function fillMinorCategories() {
    const options = categoryChildren(majorCategory.value);
    publishCategory.value = "";
    fillSelect(publishCategory, options, majorCategory.value ? "选择小分类" : "先选择大分类", "id");
    publishCategory.disabled = !options.length;
    syncCustomCategory();
  }
  function fillWards() {
    const options = regionChildren(publishDistrict.value, 3);
    const placeholder = !publishDistrict.value ? "先选择市／郡／区"
      : options.length ? "整个市／郡／区" : "本地区无下辖区";
    publishWard.value = "";
    fillSelect(publishWard, options, placeholder, "code");
    publishWard.disabled = !options.length;
  }
  fillMinorCategories();
  fillSelect(publishDistrict, [], "先选择市／道", "code");
  fillWards();
  majorCategory.addEventListener("change", fillMinorCategories);
  publishCategory.addEventListener("change", syncCustomCategory);
  publishCity.addEventListener("change", () => {
    publishDistrict.value = "";
    fillSelect(
      publishDistrict,
      regionChildren(publishCity.value, 2),
      publishCity.value ? "选择市／郡／区" : "先选择市／道",
      "code",
    );
    publishDistrict.disabled = !publishCity.value;
    fillWards();
  });
  publishDistrict.addEventListener("change", fillWards);
  if (template) {
    form.elements.title.value = template.title;
    form.elements.description.value = template.description;
    form.elements.capacity.value = template.capacity;
    const previousPrice = Number(template.price_amount ?? 0);
    price.value = Number.isSafeInteger(previousPrice) && previousPrice >= 0 ? formatWon(String(previousPrice)) : "";
    form.elements.approvalMode.value = template.approval_mode;
    majorCategory.value = categories.find((entry) => entry.id === template.category_id)?.parent_id ?? "";
    fillMinorCategories();
    publishCategory.value = template.category_id;
    syncCustomCategory();
    custom.value = template.custom_subcategory ?? "";
    publishCity.value = template.city_code;
    publishCity.dispatchEvent(new Event("change"));
    publishDistrict.value = template.municipality_code ?? template.district_code;
    publishDistrict.dispatchEvent(new Event("change"));
    if (template.municipality_code) publishWard.value = template.district_code;
    updatePreview();
  }
  handleForm(form, content, async (values) => {
    if (!values.categoryId) throw new Error("请选择活动小分类。");
    if (!values.districtCode) throw new Error("请选择市／郡／区。");
    if (!values.startsAt || !values.endsAt) throw new Error("请选择活动的开始和结束日期与时间。");
    const startsAt = new Date(values.startsAt + ":00+09:00");
    const endsAt = new Date(values.endsAt + ":00+09:00");
    if (endsAt <= startsAt) throw new Error("结束时间必须晚于开始时间。");
    const amount = numberValue(values.price);
    if (!Number.isSafeInteger(amount) || amount < 0 || amount > 9_999_999_999)
      throw new Error("请输入 0 至 9,999,999,999 之间的韩元整数金额。");
    const coverMediaId = await uploadCover(values.cover);
    let item;
    try {
      item = await request("/events", {
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
          coverMediaId,
          place: { name: values.place.trim() },
          customSubcategory: values.customSubcategory.trim() || null,
          languageCodes: ["zh"],
        },
      });
    } catch (error) {
      if (coverMediaId)
        await request("/events/covers/" + coverMediaId, {
          auth: true,
          method: "DELETE",
        }).catch(() => {});
      throw error;
    }
    if (seriesId) {
      try {
        await request("/series/" + seriesId + "/events/" + item.id, { auth: true, method: "PUT" });
      } catch {
        window.alert("活动已发布。请从系列管理页手动加入活动。");
      }
    }
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
      actionLink("活动签到", "/organizer/activities/" + id + "/check-in"),
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
      '<label>活动名称<input name="title" required maxlength="80"></label><label>活动介绍（选填）<textarea name="description" maxlength="3000"></textarea></label><button type="submit" class="button primary">保存</button>';
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
  const content = show("个人资料", "settings-page personal-page");
  const user = session.user;
  content.append(memberPages.accountLinks());
  const marker = dialogRequest;
  const loading = node("p", "正在加载个人资料…", "meta");
  content.append(loading);
  const [account, profile, member] = await Promise.all([
    request("/me", { auth: true }).catch(() => null),
    request("/users/" + encodeURIComponent(user.id) + "/public-profile", { auth: true })
      .catch(() => null),
    request("/me/member-profile", { auth: true }).catch(() => null),
    regions.length ? Promise.resolve() : request("/regions")
      .then((catalog) => { regions = catalog; }).catch(() => {}),
  ]);
  if (marker !== dialogRequest) return;
  loading.remove();
  if (session?.user.id !== user.id) {
    showError(content, new Error("请重新登录后查看个人资料。"));
    return;
  }
  if (account) {
    const { nickname, avatarUrl, avatarImageUrl } = account;
    setSession({ ...session, user: { ...user, nickname, avatarUrl, avatarImageUrl } });
  }
  const info = node("section", null, "personal-card");
  const identity = node("div", null, "personal-identity");
  const avatar = node("div", null, "account-avatar");
  avatar.setAttribute("aria-hidden", "true");
  renderAvatar(avatar, session.user);
  identity.append(avatar, node("h2", session.user.nickname || "搭慕用户"));
  info.append(identity);
  const stats = node("dl", null, "personal-stats");
  for (const [label, count] of [
    ["已报名", account?.joined_count],
    ["已组织", account?.organized_count],
    ["已到场", account?.attended_count],
    ["获赞", profile?.like_count],
  ]) {
    const entry = node("div");
    entry.append(node("dt", label), node("dd", count ?? "—"));
    stats.append(entry);
  }
  info.append(stats);
  const fields = node("dl", null, "activity-facts");
  const memberFields = new Map();
  const joined = new Date(account?.created_at ?? "");
  const joinedOn = Number.isFinite(joined.valueOf())
    ? new Intl.DateTimeFormat("zh-CN", { dateStyle: "long", timeZone: "Asia/Seoul" }).format(joined)
    : "";
  for (const [label, value] of [
    ["注册邮箱", account?.email ?? user.email],
    ["加入日期", joinedOn],
    ["公开简介", member?.bio ?? profile?.bio],
    ["常驻区域", member && [member.home_parent_name, member.home_region_name].filter(Boolean).join(" · ")],
  ]) {
    const entry = node("div");
    const description = node("dd", value || "—");
    memberFields.set(label, description);
    entry.append(node("dt", label), description);
    fields.append(entry);
  }
  info.append(fields);
  const layout = node("div", null, "settings-layout");
  const summary = node("aside", null, "settings-summary");
  const editor = node("div", null, "settings-editor");
  summary.append(info);
  layout.append(summary, editor);
  content.append(layout);

  const form = node("form", null, "form");
  form.innerHTML =
    '<h2>编辑昵称</h2><label>昵称<input name="nickname" required minlength="2" maxlength="30"></label><button type="submit" class="button primary">保存昵称</button>';
  form.elements.nickname.value = session.user.nickname ?? "";
  const shortcuts = node("div", null, "section-nav personal-shortcuts");
  shortcuts.append(
    actionLink("我的关注", "/me/following"),
    actionLink("我的收藏", "/me/saved"),
    actionLink("查看公开主页", "/people/" + user.id),
    button("退出登录", () => {
      setSession(null);
      location.assign("/");
    }),
  );
  summary.append(shortcuts);
  editor.append(form);
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
    $("h2", identity).textContent = updated.nickname;
    renderAvatar(avatar, session.user);
    $(".notice", content)?.remove();
    form.append(node("p", "昵称已保存。", "notice"));
  });
  if (member) {
    const details = node("form", null, "form");
    details.innerHTML = '<h2>公开主页资料</h2><label>简介（选填）<textarea name="bio" maxlength="300" rows="3"></textarea></label><label>常驻市／道（选填）<select name="city"></select></label><label>常驻市／郡／区（选填）<select name="district"></select></label><label class="check profile-visibility"><input type="checkbox" name="show">在公开主页显示常驻区域</label><p class="meta" role="status"></p><button type="submit" class="button primary">保存公开资料</button>';
    const { bio, city, district, show: visible } = details.elements;
    const regionStatus = $("[role=status]", details);
    const selected = regions.find((region) => region.code === member.home_region_code);
    bio.value = member.bio ?? "";
    city.append(new Option("不填写", ""));
    for (const region of regions.filter((item) => item.level === 1))
      city.append(new Option(region.name_zh_cn, region.code));
    city.value = selected?.parent_code ?? selected?.code ?? "";
    function syncRegion() {
      district.replaceChildren(new Option("仅填写市／道", ""));
      for (const region of regions.filter((item) => item.level === 2 && item.parent_code === city.value))
        district.append(new Option(region.name_zh_cn, region.code));
      district.disabled = !city.value || district.options.length === 1;
      visible.disabled = !city.value;
      if (visible.disabled) visible.checked = false;
    }
    syncRegion();
    if (selected?.level === 2) district.value = selected.code;
    visible.checked = !!city.value && member.show_home_region;
    city.addEventListener("change", syncRegion);
    regionStatus.textContent = visible.checked ? "当前公开可见。" : "关闭时仅自己可见。";
    if (!regions.length) {
      city.disabled = true;
      regionStatus.textContent = "地区列表暂时无法加载。仍可更新简介。";
    }
    form.after(details);
    handleForm(details, details, async (values) => {
      const updated = await request("/me/member-profile", { method: "PUT", auth: true, data: {
        bio: values.bio,
        homeRegionCode: regions.length ? district.value || city.value || null : member.home_region_code,
        showHomeRegion: regions.length ? visible.checked : member.show_home_region,
      }});
      regionStatus.textContent = !updated.home_region_code ? "已保存 · 未填写常驻区域"
        : updated.show_home_region ? "已保存 · 常驻区域公开可见" : "已保存 · 常驻区域仅自己可见";
      memberFields.get("公开简介").textContent = updated.bio || "—";
      if (regions.length) {
        const label = [city.value && city.selectedOptions[0].text, district.value && district.selectedOptions[0].text]
          .filter(Boolean).join(" · ");
        memberFields.get("常驻区域").textContent = label || "—";
      }
    });
  } else {
    content.append(node("p", "公开主页资料暂时无法加载。", "meta"));
  }
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
    const heading = $("h1", content);
    heading.textContent = user.nickname ?? "搭慕用户";
    const layout = node("div", null, "public-profile-layout");
    const identity = node("section", null, "activity-section public-profile-summary");
    const timeline = node("div", null, "public-profile-activity");
    layout.append(identity, timeline);
    content.append(layout);
    const url = uploadedImage(user.avatar_url);
    if (url) {
      const avatar = node("img", null, "profile-avatar");
      avatar.src = url;
      avatar.alt = "";
      identity.append(avatar);
    }
    identity.append(heading, node("p", "获赞 " + (user.like_count ?? 0), "meta"));
    if (user.bio) identity.append(node("p", user.bio, "detail-copy"));
    if (user.home_region_name)
      identity.append(node("p", "常驻 · " + [user.home_parent_name, user.home_region_name].filter(Boolean).join(" · "), "profile-region"));
    const tags = node("div", null, "profile-tags");
    for (const tag of user.positive_tags ?? []) {
      const label = {
        reliable: "值得信赖",
        friendly: "友善",
        respectful: "尊重他人",
        helpful: "乐于助人",
        newcomer_friendly: "新手友好",
        well_organized: "组织有序",
        clear_communication: "沟通清晰",
      }[tag.tag_code];
      if (label) tags.append(node("span", label + " ×" + tag.count));
    }
    if (tags.children.length) identity.append(tags);
    const actions = node("div", null, "section-nav");
    if (id !== session?.user.id) {
      const contactActions = node("span", null, "contact-profile-actions");
      const refresh = () => directContact.profileActions(id, content, contactActions);
      actions.append(communityPages.followButton(id, refresh), contactActions);
      if (session) refresh();
    }
    if (id !== session?.user.id)
      actions.append(
        button(
          "屏蔽用户",
          () =>
            requireLogin(async () => {
              try {
                await request("/blocks/" + encodeURIComponent(id), {
                  auth: true,
                  data: { reasonCode: "user_requested" },
                });
                content.append(
                  node("p", "已屏蔽，可在隐私设置中解除。", "notice"),
                );
              } catch (error) {
                showError(content, error);
              }
            }),
          "text-button",
        ),
      );
    if (id !== session?.user.id)
      actions.append(
        button(
          "举报用户",
          () => requireLogin(() => showReport("user", id, id)),
          "text-button",
        ),
      );
    if (actions.children.length) identity.append(actions);
    timeline.append(node("h2", "公开发起的活动"));
    if (user.activities?.length) {
      const grid = node("div", null, "cards");
      grid.append(...user.activities.map(card));
      timeline.append(grid);
    } else timeline.append(node("p", "暂时没有公开活动。", "meta"));
    activitySeries.organizer(id, timeline);
  } catch (error) {
    if (marker === dialogRequest) showError(content, error);
  }
}

function guideCard(guide) {
  const item = node("article", null, "card");
  const href = "/guides/" + encodeURIComponent(guide.slug);
  const picture = actionLink("", href, "cover");
  picture.setAttribute("aria-label", guide.title);
  picture.append(cover({ cover_category_code: guide.cover_category }));
  item.append(
    picture,
    actionLink(guide.title, href, "guide-title"),
    node("p", guide.summary, "meta"),
  );
  return item;
}
async function loadGuideCards(content, featured, filters = {}) {
  const grid = node("div", null, "cards guide-grid");
  content.append(grid);
  try {
    const entries = await request(
      "/guides?" +
        new URLSearchParams({ featured: String(featured), ...filters }),
    );
    grid.replaceChildren(...entries.map(guideCard));
    if (!entries.length) grid.append(node("p", "暂无已发布指南。", "meta"));
  } catch (error) {
    showError(grid, error);
  }
}
async function showGuides(slug) {
  const content = show(
    slug ? "周末指南 · 阅读" : "周末指南",
    slug ? "guide-article" : "workspace-page",
  );
  content.classList.add("guide-page");
  if (!slug) {
    content.append(node("p", "搭慕编辑部 · 给想出门的人一些灵感。", "meta"));
    return loadGuideCards(content, false);
  }
  try {
    const guide = await request("/guides/" + encodeURIComponent(slug));
    $("h1", content).textContent = guide.title;
    document.title = guide.title + " · 搭慕 DAMU";
    const layout = node("div", null, "guide-reading-layout");
    const copy = node("article", null, "activity-section guide-reading-copy");
    const sidebar = node("aside", null, "activity-section guide-reading-sidebar");
    copy.append(
      node("p", guide.summary, "meta"),
      cover({ cover_category_code: guide.cover_category }, "detail-cover"),
    );
    for (const paragraph of guide.body
      .split(/\r?\n/)
      .filter((line) => line.trim())) {
      copy.append(node("p", paragraph, "detail-copy"));
    }
    if (guide.source_url) {
      const source = actionLink(
        "查看原始来源",
        guide.source_url,
        "text-button",
      );
      source.rel = "noopener noreferrer";
      source.target = "_blank";
      copy.append(source);
    }
    sidebar.append(node("h2", "周末指南"));
    const actions = node("div", null, "section-nav");
    actions.append(
      memberPages.bookmark("guide", guide.slug),
      actionLink("发现活动", "/explore"),
      actionLink("返回指南", "/guides", "text-button"),
    );
    sidebar.append(actions);
    layout.append(copy, sidebar);
    content.append(layout);
  } catch (error) {
    showError(content, error);
    content.append(actionLink("返回指南", "/guides"));
  }
}

function showReport(targetType, targetId, reportedUserId) {
  const content = show(
    "举报" + (targetType === "activity" ? "活动" : "用户"),
    "reading",
    true,
  );
  const form = node("form", null, "form");
  form.innerHTML =
    '<label>原因<select name="categoryCode" required><option value="">请选择</option><option value="misleading">信息不实</option><option value="harassment">骚扰</option><option value="unsafe">安全问题</option><option value="other">其他</option></select></label><label>说明<textarea name="description" maxlength="500" required></textarea></label><button type="submit" class="button primary">提交举报</button>';
  content.append(form);
  handleForm(form, content, async (values) => {
    if (!values.description.trim()) throw new Error("请填写说明。");
    await request("/reports", {
      auth: true,
      data: {
        targetType,
        targetId,
        reportedUserId,
        categoryCode: values.categoryCode,
        description: values.description.trim(),
      },
    });
    form.replaceWith(node("p", "举报已提交。", "notice"));
  });
}

function showNotFound() {
  const content = show("没有找到这个页面");
  content.append(actionLink("返回发现活动", "/explore"));
}
function showDownload() {
  const content = show("下载搭慕 App", "reading download-page");
  const card = node("section", null, "download-card");
  const logo = node("img", null, "download-logo");
  logo.src = "/assets/logo.png";
  logo.alt = "";
  const copy = node("div");
  const available = appStoreLinks.filter(({ url }) => url);
  const links = node("div", null, "section-nav");
  if (available.length) {
    copy.append(node("p", "选择手机对应的应用商店。"));
    for (const { label, url } of available)
      links.append(actionLink(label, url, "button primary"));
  } else {
    copy.append(node("p", "App 下载暂未开放。你可以先在网页浏览和报名参加活动。"));
    links.append(actionLink("浏览活动", "/explore", "button primary"));
  }
  copy.append(links);
  card.append(logo, copy);
  content.append(card);
}

async function route() {
  const path = location.pathname;
  if (path === "/following") return location.replace("/explore?feed=following");
  for (const link of document.querySelectorAll(".masthead nav a, #my-menu a")) {
    if (link.pathname === path || path.startsWith(link.pathname + "/"))
      link.setAttribute("aria-current", "page");
  }
  if (path === "/download") return showDownload();
  if (path === "/series") return activitySeries.index();
  if (path === "/series/new" || path === "/series/participate")
    return activitySeries.create(path.endsWith("/participate"));
  const series = /^\/series\/([a-z0-9-]+)(\/manage)?$/i.exec(path);
  if (series) return series[2] ? activitySeries.manage(series[1]) : activitySeries.detail(series[1]);
  const recap = /^\/activities\/([0-9a-f-]{36})\/recap(\/edit)?$/i.exec(path);
  if (recap) return recap[2] ? requireLogin(() => activitySeries.recap(recap[1], true)) : activitySeries.recap(recap[1]);
  const share = /^\/activities\/([0-9a-f-]{36})\/share$/i.exec(path);
  if (share) return location.replace(eventLink(share[1]));
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
      const following = new URLSearchParams(location.search).get("feed") === "following";
      if (following && !session) return requireLogin(() => {});
      $("#filters").append(actionLink("清除筛选", following ? "/explore?feed=following" : "/explore", "text-button"));
      const toolbar = $("#gallery .toolbar");
      const actions = node("div", null, "discover-toolbar-actions");
      actions.append(actionLink("活动日历", "/calendar"));
      toolbar.append(actions);
      if (session) {
        const tabs = node("nav", null, "discover-feed-tabs");
        tabs.setAttribute("aria-label", "活动来源");
        for (const [label, href, active] of [["全部活动", "/explore", !following], ["我关注的", "/explore?feed=following", following]]) {
          const tab = actionLink(label, href, "discover-feed-tab");
          if (active) tab.setAttribute("aria-current", "page");
          tabs.append(tab);
        }
        toolbar.after(tabs);
        if (following) {
          actions.append(actionLink("管理关注", "/me/following"));
        }
      }
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
          actionLink("搭慕周末", "/series/damu-weekend"),
      );
      browse.append(preview);
      loadGuideCards(preview, true);
    }
    await setupFeed();
    return;
  }
  const community = communityPages.route(path);
  if (community !== null) return community;
  if (memberPages.pages.has(path)) return memberPages.pages.get(path)();
  const checkIn = /^\/organizer\/activities\/([0-9a-f-]{36})\/check-in$/i.exec(
    path,
  );
  if (checkIn) return memberPages.checkIn(checkIn[1]);
  const feedback = /^\/activities\/([0-9a-f-]{36})\/feedback$/i.exec(path);
  if (feedback) return memberPages.activityFeedback(feedback[1]);
  const topic = /^\/(places|categories)\/([a-z0-9_-]+)$/i.exec(path);
  if (topic) return memberPages.topic(topic[1], topic[2]);
  if (path === "/places" || path === "/categories")
    return memberPages.topic(path.slice(1));
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
        const copy = new URLSearchParams(location.search).get("copy");
        const seriesKey = new URLSearchParams(location.search).get("series");
        const [areaCatalog, categoryCatalog, source, series] = await Promise.all([
          request("/regions"),
          request("/categories"),
          copy
            ? request("/events/" + encodeURIComponent(copy), { auth: true })
            : null,
          seriesKey ? request("/series/" + encodeURIComponent(seriesKey), { auth: true }) : null,
        ]);
        if (source && source.item.organizer_user_id !== session.user.id)
          throw new Error("只能复办自己发起的活动。");
        regions = areaCatalog;
        categories = categoryCatalog;
        if (series && !series.item.can_manage) throw new Error("仅系列管理者可添加活动。");
        showPublish(source?.item, series?.item.id);
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
  if (path === "/terms") {
    const content = show("社区规则");
    content.append(
      node(
        "p",
        "搭慕用于发现和组织线下活动。请准确填写活动内容、报名条件和预计线下人均费用。",
        "detail-copy",
      ),
      node(
        "p",
        "尊重参与者的意愿和隐私。未经允许，不公开他人的联系方式、集合信息或照片。遇到骚扰、虚假活动或安全问题，可在对应页面举报。",
        "detail-copy",
      ),
      node(
        "p",
        "费用由参与者线下处理。搭慕不代收活动费、不提供转账或资金担保。",
        "detail-copy",
      ),
      actionLink("阅读隐私政策", "/privacy"),
    );
    return;
  }
  if (path === "/unavailable") {
    const content = show("服务暂不可用");
    content.append(
      node("p", "请稍后重试。", "meta"),
      actionLink("回到首页", "/"),
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
  if (path === "/messages/requests") return requireLogin(directContact.showRequests);
  if (path === "/messages" || conversationRoute.test(path))
    return requireLogin(showMessages);
  if (path === "/settings/profile") return requireLogin(showSettings);
  showNotFound();
}

function syncFilters() {
  if (location.pathname !== "/explore") return;
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries({
    feed: new URLSearchParams(location.search).get("feed"),
    q: query,
    ...browseFilters.values(),
    maxPrice: $("#max-price").value,
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
async function setupFeed() {
  const params = new URLSearchParams(location.search);
  query = params.get("q") ?? "";
  category = params.get("category") ?? "";
  $("#query").value = query;
  $("#max-price").value = params.get("maxPrice") ?? "";
  $("#sort").value = params.get("sort") ?? "recommended";
  const [regionData, categoryData] = await Promise.allSettled([
    request("/regions"),
    request("/categories"),
  ]);
  if (regionData.status === "fulfilled") regions = regionData.value;
  browseFilters.restore(params, regions);
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
const browseFilters = createBrowseFilters({ node, button, changed: refreshFeed });
document.addEventListener("pointerdown", (event) => {
  if (myMenu.open && !myMenu.contains(event.target)) myMenu.open = false;
});
myMenu.addEventListener("keydown", (event) => {
  if (event.key !== "Escape" || !myMenu.open) return;
  event.preventDefault();
  myMenu.open = false;
  $("summary", myMenu).focus();
});
more.addEventListener("click", () => loadFeed(true));
$("#close").addEventListener("click", () => dialog.close());
const memberPages = createMemberPages({
  show,
  node,
  button,
  actionLink,
  showError,
  handleForm,
  request,
  requireLogin,
  eventLink,
  time,
  libraryRow,
  libraryEventState,
  renderAvatar,
  card,
  setSession,
  session: () => session,
  reasonDialog,
  loadGuideCards,
});
const communityPages = createCommunityPages({
  show,
  node,
  button,
  actionLink,
  showError,
  handleForm,
  request,
  requireLogin,
  eventLink,
  time,
  card,
  area,
  cover,
  session: () => session,
});
const showMessages = createChatPage({
  show,
  node,
  button,
  actionLink,
  handleForm,
  request,
  reasonDialog,
  dialog,
  session: () => session,
  time,
  renderAvatar,
  renderMessageCount,
  refreshUnread,
});
const directContact = createDirectContact({
  show, node, button, actionLink, request, requireLogin, handleForm, showError,
  showReport, renderAvatar, refreshUnread,
});
const activitySeries = createActivitySeries({
  show, node, button, actionLink, request, requireLogin, handleForm, showError,
  session: () => session, cover, card, eventLink, uploadCover, uploadedImage,
});
setSession(session);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) refreshUnread();
});
window.setInterval(() => {
  if (!document.hidden) refreshUnread();
}, 45_000);
installSelectMenus();
route();

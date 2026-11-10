const apiRoot = "https://api.damumu.com";
const oauth = "/api/v1/auth/web";
const $ = (selector, root = document) => root.querySelector(selector);
const dialog = $("#dialog");
const panel = $("#panel");
const cards = $("#cards");
const status = $("#status");
const city = $("#city");
const district = $("#district");
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
let afterLogin;

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

function area(item) {
  return [
    item.city_name ||
      regions.find((region) => region.code === item.city_code)?.name_zh_cn,
    item.district_name ||
      regions.find((region) => region.code === item.district_code)?.name_zh_cn,
  ]
    .filter(Boolean)
    .join(" · ");
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
function cover(item, className = "") {
  const image = node("img", null, className);
  image.alt = "";
  image.loading = "lazy";
  const kind = coverKinds.has(item.cover_category_code)
    ? item.cover_category_code
    : "other";
  const fallback = "/assets/covers/" + kind + ".webp";
  let remote;
  try {
    const url = new URL(item.cover_url ?? "", apiRoot);
    if (url.origin === apiRoot && url.pathname.startsWith("/uploads/"))
      remote = url.href;
  } catch {
    /* Missing or invalid cover */
  }
  image.src = remote ?? fallback;
  if (remote)
    image.addEventListener(
      "error",
      () => {
        image.src = fallback;
      },
      { once: true },
    );
  return image;
}

function eventLink(id) {
  return "#activity/" + encodeURIComponent(id);
}
function card(item) {
  const article = node("article", null, "card");
  const thumbnail = node("a", null, "cover");
  thumbnail.href = eventLink(item.id);
  thumbnail.setAttribute("aria-label", item.title);
  thumbnail.append(cover(item));
  if (item.category_name)
    thumbnail.append(node("span", item.category_name, "tag"));
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
  const params = new URLSearchParams({ limit: "20" });
  for (const [key, value] of Object.entries({
    city: city.value,
    district: district.value,
    sort: $("#sort").value,
    q: query,
    categoryId: category,
    cursor: append ? cursor : null,
  }))
    if (value) params.set(key, value);
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
    if (feedRequest === controller) more.hidden = !cursor;
  }
}

function show(title) {
  dialogRequest++;
  const content = node("section", null, "dialog-body");
  const heading = node("h2", title);
  heading.id = "dialog-title";
  content.append(heading);
  panel.replaceChildren(content);
  if (!dialog.open) dialog.showModal();
  dialog.scrollTop = 0;
  return content;
}

function showError(content, error) {
  const slot = $(".form-error", content) ?? node("p", null, "form-error");
  slot.setAttribute("role", "alert");
  slot.textContent = error.message;
  if (!slot.isConnected) content.append(slot);
}

function requireLogin(action) {
  if (session) action();
  else {
    afterLogin = action;
    showLogin();
  }
}

function finishLogin(result) {
  setSession(result);
  const action = afterLogin;
  afterLogin = null;
  if (action) action();
  else if (location.hash.startsWith("#activity/")) route();
  else dialog.close();
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
              if (location.hash.startsWith("#activity/"))
                sessionStorage.setItem("damu-return", location.hash);
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
        () => showLogin(!register),
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
  const content = show("活动详情");
  const marker = dialogRequest;
  const loading = node("p", "正在加载活动详情…", "meta");
  content.append(loading);
  try {
    const { item, schedules } = await request(
      "/events/" + encodeURIComponent(id),
      { auth: true },
    );
    if (marker !== dialogRequest || !dialog.open) return;
    loading.remove();
    $("h2", content).textContent = item.title;
    content.append(cover(item, "detail-cover"));
    const schedule =
      schedules?.find((entry) => entry.status === "scheduled") ??
      schedules?.[0];
    content.append(
      node(
        "p",
        [item.category_name, time(schedule?.starts_at), area(item)]
          .filter(Boolean)
          .join(" · "),
        "meta",
      ),
    );
    content.append(
      node(
        "p",
        "组织者 " + (item.organizer_name || "搭慕用户") + " · " + cost(item),
        "meta",
      ),
    );
    content.append(
      node("p", item.description || "组织者还未填写活动介绍。", "detail-copy"),
    );
    const membership = item.viewer_membership_status;
    const owns = session?.user.id === item.organizer_user_id;
    const approved = ["approved", "attended"].includes(membership);
    if ((owns || approved) && (item.place_name || item.address_public)) {
      content.append(
        node(
          "p",
          [item.place_name, item.address_public].filter(Boolean).join(" · "),
          "notice",
        ),
      );
    } else if (!owns && !approved) {
      content.append(node("p", "报名通过后可查看具体集合点。", "notice"));
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
      content.append(node("p", labels[membership] ?? "已有报名记录", "meta"));
    const active =
      ["published", "full"].includes(item.status) &&
      (!schedule?.ends_at || Date.parse(schedule.ends_at) > Date.now());
    const actions = node("div", null, "detail-actions");
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
    content.append(actions);
  } catch (error) {
    if (marker === dialogRequest) {
      loading.remove();
      showError(content, error);
    }
  }
}

function showJoin(id) {
  const content = show("报名参加");
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
  const content = show("我的活动");
  const marker = dialogRequest;
  try {
    const activities = await request("/me/activities", { auth: true });
    if (marker !== dialogRequest || !dialog.open) return;
    const list = node("ul", null, "detail-list");
    for (const item of activities) {
      const entry = node("li");
      const link = node("a", item.title);
      link.href = eventLink(item.id);
      entry.append(
        link,
        node(
          "p",
          [time(item.starts_at), area(item)].filter(Boolean).join(" · "),
          "meta",
        ),
      );
      list.append(entry);
    }
    content.append(
      list.children.length ? list : node("p", "还没有活动记录。", "meta"),
    );
  } catch (error) {
    if (marker === dialogRequest) showError(content, error);
  }
}

async function showMessages() {
  const content = show("消息");
  const marker = dialogRequest;
  try {
    const conversations = await request("/conversations", { auth: true });
    if (marker !== dialogRequest || !dialog.open) return;
    const list = node("ul", null, "detail-list");
    for (const conversation of conversations) {
      const entry = node("li");
      const unread = conversation.unread_count
        ? " · " + conversation.unread_count + " 条未读"
        : "";
      entry.append(
        button(
          conversation.display_title + unread,
          () => showConversation(conversation),
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

async function showConversation(conversation) {
  const content = show(conversation.display_title);
  const marker = dialogRequest;
  const base = "/conversations/" + encodeURIComponent(conversation.id);
  const messages = node("ol", null, "detail-list");
  const older = button("加载更早消息", () => loadMessages(true));
  older.hidden = true;
  content.append(
    button("返回消息", showMessages, "text-button"),
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
      if (marker !== dialogRequest || !dialog.open) return;
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
    content.append(form);
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
  const content = show("发起活动");
  const form = node("form", null, "form");
  form.innerHTML = `
    <label>活动名称<input name="title" required maxlength="80"></label>
    <label>活动介绍<textarea name="description" required maxlength="3000"></textarea></label>
    <div class="form-row"><label>活动分类<select name="categoryId" required></select></label><label id="custom-label" hidden>自定义分类<input name="customSubcategory" maxlength="15"></label></div>
    <div class="form-row"><label>城市<select name="cityCode" required></select></label><label>地区<select name="districtCode" required disabled></select></label></div>
    <div class="form-row"><label>开始时间（韩国）<input name="startsAt" type="datetime-local" required></label><label>结束时间（韩国）<input name="endsAt" type="datetime-local" required></label></div>
    <div class="form-row"><label>人数上限（含组织者）<input name="capacity" type="number" value="6" min="2" max="100" required></label><label>预计线下人均费用（₩）<input name="price" type="number" value="0" min="0" required></label></div>
    <label>集合点（报名通过后可见）<input name="place" required maxlength="100"></label>
    <label>报名方式<select name="approvalMode"><option value="manual">组织者审核</option><option value="auto">直接加入</option></select></label>
    <button class="button primary" type="submit">发布活动</button>`;
  content.append(form);
  const publishCity = $('[name="cityCode"]', form);
  const publishDistrict = $('[name="districtCode"]', form);
  const publishCategory = $('[name="categoryId"]', form);
  const custom = $('[name="customSubcategory"]', form);
  fillSelect(
    publishCity,
    regions.filter((entry) => entry.level === 1),
    "选择城市",
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
    fillSelect(
      publishDistrict,
      regions.filter((entry) => entry.parent_code === publishCity.value),
      "选择地区",
      "code",
    );
    publishDistrict.disabled = !publishCity.value;
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
        districtCode: values.districtCode,
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
    location.hash = eventLink(item.id);
    loadFeed();
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
    if (marker !== dialogRequest || !dialog.open) return;
    if (result.registrationRequired) {
      options.privacyVersion = result.privacyVersion;
      showLogin(false, true);
    } else finishLogin(result);
  } catch (error) {
    if (marker === dialogRequest) showLogin(false, false, error.message);
  }
}

function route() {
  const hash = location.hash;
  if (hash === "#social-complete" || hash === "#social-error") {
    const returnTo = sessionStorage.getItem("damu-return");
    sessionStorage.removeItem("damu-return");
    history.replaceState(
      null,
      "",
      returnTo?.startsWith("#activity/") ? returnTo : "/",
    );
    if (hash === "#social-complete") finishSocial();
    else showLogin(false, false, "第三方授权未完成，请重试或使用邮箱登录。");
    return;
  }
  const match = /^#activity\/([0-9a-f-]{36})$/i.exec(hash);
  if (match) showActivity(match[1]);
}

$("#search").addEventListener("submit", (event) => {
  event.preventDefault();
  query = $("#query").value.trim();
  loadFeed();
  $("#gallery").scrollIntoView();
});
city.addEventListener("change", () => {
  fillSelect(
    district,
    regions.filter((entry) => entry.parent_code === city.value),
    "全部地区",
    "code",
  );
  district.disabled = !city.value;
  loadFeed();
});
district.addEventListener("change", () => loadFeed());
$("#sort").addEventListener("change", () => loadFeed());
more.addEventListener("click", () => loadFeed(true));
$("#close").addEventListener("click", () => dialog.close());
dialog.addEventListener("close", () => {
  dialogRequest++;
  afterLogin = null;
  if (location.hash.startsWith("#activity/"))
    history.replaceState(null, "", location.pathname + location.search);
});
$("#login").addEventListener("click", () => {
  if (!session) showLogin();
  else {
    const content = show(session.user.nickname);
    content.append(
      button("退出登录", () => {
        setSession(null);
        dialog.close();
      }),
    );
  }
});
$("#messages").addEventListener("click", () => requireLogin(showMessages));
$("#mine").addEventListener("click", () => requireLogin(showMine));
$("#publish").addEventListener("click", () => requireLogin(showPublish));
window.addEventListener("hashchange", route);
setSession(session);
renderCategories();
request("/regions")
  .then((result) => {
    regions = result;
    fillSelect(
      city,
      regions.filter((entry) => entry.level === 1),
      "全部城市",
      "code",
    );
  })
  .catch(() => {});
request("/categories")
  .then((result) => {
    categories = result;
    renderCategories();
  })
  .catch(() => {});
route();
loadFeed();

const recentDays = 7;
const pageSize = 40;
const historyEdge = 64;
export const conversationRoute = /^\/messages\/([0-9a-f-]{36})$/i;
const messageGroups = [
  ["event", "活动消息", "activity_message_count"],
  ["direct", "一般消息", "general_message_count"],
  ["announcement", "公告", "announcement_count"],
];
const groupHref = (group) => group === "event" ? "/messages" : "/messages?type=" + group;
const listDate = new Intl.DateTimeFormat("zh-CN", {
  timeZone: "Asia/Seoul", month: "numeric", day: "numeric",
  hour: "2-digit", minute: "2-digit", hourCycle: "h23",
});

function previewTime(value) {
  const date = new Date(value);
  return value && Number.isFinite(date.valueOf()) ? listDate.format(date) : "";
}

export function createChatPage({
  show,
  node,
  button,
  actionLink,
  handleForm,
  request,
  reasonDialog,
  dialog,
  session,
  time,
  renderAvatar,
  renderMessageCount,
  refreshUnread,
}) {
  return async function showMessages() {
    const content = show("消息", "chat-page");
    const layout = node("div", null, "chat-layout");
    const sidebar = node("nav", null, "chat-sidebar");
    sidebar.setAttribute("aria-label", "消息列表");
    const heading = node("h2", "消息列表", "chat-list-heading");
    heading.tabIndex = -1;
    const groups = node("div", null, "chat-groups");
    const groupLinks = new Map();
    for (const [group, label] of messageGroups) {
      const link = actionLink(label, groupHref(group), "chat-group");
      const badge = node("span", null, "message-count");
      badge.hidden = true;
      link.append(badge);
      link.addEventListener("click", (event) => navigate(event, groupHref(group)));
      groupLinks.set(group, { link, badge });
      groups.append(link);
    }
    const choices = node("ul", null, "chat-choices");
    const requestsLink = actionLink("联系请求", "/messages/requests", "chat-group chat-requests-link");
    const requestsBadge = node("span", null, "message-count");
    requestsBadge.hidden = true;
    requestsLink.hidden = true;
    requestsLink.append(requestsBadge);
    const listStatus = node("p", "正在加载会话…", "chat-list-status meta");
    listStatus.setAttribute("role", "status");
    sidebar.append(heading, groups, requestsLink, listStatus, choices);
    const panel = node("div", null, "chat-panel");
    const placeholder = node("div", null, "chat-placeholder");
    const prompt = node("p", "选择一个会话查看消息。");
    const back = actionLink("‹ 消息列表", "/messages", "chat-back text-button");
    placeholder.append(back, prompt);
    panel.append(placeholder);
    layout.append(sidebar, panel);
    content.append(layout);

    const rows = new Map();
    const errors = new Map();
    let activeId;
    let threadRequest;
    let listVersion = 0;
    let previousCounts;

    function navigate(event, href) {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      if (location.pathname + location.search === href) return;
      history.pushState(null, "", href);
      selectFromLocation(true);
    }

    function selectFromLocation(focus = false) {
      const params = new URLSearchParams(location.search);
      const conversation = conversationRoute.exec(location.pathname)?.[1].toLowerCase();
      const announcement = params.get("announcement");
      const id = conversation ?? (params.get("type") === "announcement" && announcement
        ? "announcement:" + announcement : null);
      const selected = rows.get(id);
      const requested = params.get("type");
      const group = selected?.group ?? (groupLinks.has(requested) ? requested : "event");
      requestsLink.hidden = group !== "direct";
      for (const [key, { link }] of groupLinks) {
        if (key === group) link.setAttribute("aria-current", "page");
        else link.removeAttribute("aria-current");
      }
      let visibleCount = 0;
      for (const row of rows.values()) {
        row.entry.hidden = row.group !== group;
        if (!row.entry.hidden) visibleCount++;
      }
      listStatus.hidden = visibleCount > 0;
      listStatus.textContent = errors.get(group) ?? "暂无" + messageGroups.find(([key]) => key === group)[1] + "。";
      if (id === activeId && (id === null || selected?.link.hasAttribute("aria-current"))) return;
      const previous = rows.get(activeId);
      previous?.link.removeAttribute("aria-current");
      threadRequest?.abort();
      activeId = id;
      layout.classList.toggle("has-thread", Boolean(id));
      document.title = selected ? selected.item.display_title + " · 消息 · 搭慕 DAMU" : "消息 · 搭慕 DAMU";
      if (!selected) {
        prompt.textContent = id ? "找不到这条消息。" : "选择左侧一项查看详情。";
        panel.replaceChildren(placeholder);
        if (focus) (previous?.link ?? heading).focus({ preventScroll: true });
        return;
      }
      selected.link.setAttribute("aria-current", "page");
      const threadBack = back.cloneNode(true);
      threadBack.href = groupHref(group);
      threadBack.addEventListener("click", (event) => navigate(event, groupHref(group)));
      if (group === "announcement") {
        const title = showAnnouncement(selected, threadBack);
        if (focus) title.focus({ preventScroll: true });
        return;
      }
      threadRequest = new AbortController();
      const threadTitle = renderConversation(selected.item, panel, threadBack, threadRequest.signal, {
        read() {
          renderMessageCount(selected.unread, 0);
          refreshUnread();
        },
        sent(message) {
          selected.preview.textContent = message.body || "暂无文字消息";
          selected.date.textContent = previewTime(message.created_at);
          choices.prepend(selected.entry);
        },
      });
      if (focus) threadTitle.focus({ preventScroll: true });
    }

    function addRow(item, group) {
      const isAnnouncement = group === "announcement";
      const id = isAnnouncement ? "announcement:" + item.id : item.id.toLowerCase();
      const count = isAnnouncement ? Number(!item.read_at) : item.unread_count ?? 0;
      const snippet = (isAnnouncement ? item.body : item.last_message_body) || "暂无文字消息";
      const timestamp = previewTime(isAnnouncement ? item.created_at : item.last_message_at);
      const existing = rows.get(id);
      if (existing) {
        renderMessageCount(existing.unread, count);
        existing.preview.textContent = snippet;
        existing.date.textContent = timestamp;
        choices.append(existing.entry);
        return;
      }
      const href = isAnnouncement
        ? groupHref(group) + "&announcement=" + encodeURIComponent(item.id)
        : "/messages/" + encodeURIComponent(item.id);
      const title = (group === "event" ? item.event_title : group === "direct" ? item.peer_nickname : item.title)
        || item.display_title || "会话";
      const entry = node("li");
      const link = actionLink("", href, "chat-choice " + group);
      if (group !== "event") {
        const avatar = node("span", "告", "chat-avatar " + group);
        avatar.setAttribute("aria-hidden", "true");
        if (group === "direct") renderAvatar(avatar, { nickname: title, avatarImageUrl: item.peer_avatar });
        link.append(avatar);
      }
      const label = node("span", null, "chat-choice-label");
      const preview = node("span", snippet, "chat-choice-preview");
      label.append(node("strong", title));
      if (group === "event") {
        label.append(node("span", time(item.event_starts_at), "chat-choice-preview"));
        const category = [item.event_major_category, item.event_minor_category].filter(Boolean).join(" / ");
        if (category) label.append(node("span", category, "chat-choice-preview"));
      }
      label.append(preview);
      const meta = node("span", null, "chat-choice-meta");
      const date = node("small", timestamp);
      const unread = node("span", null, "message-count");
      renderMessageCount(unread, count);
      meta.append(date, unread);
      link.append(label, meta);
      link.addEventListener("click", (event) => navigate(event, href));
      entry.append(link);
      choices.append(entry);
      rows.set(id, { item: { ...item, display_title: title }, link, entry, preview, date, unread, group });
    }

    function showAnnouncement(row, threadBack) {
      const article = node("article", null, "chat-announcement");
      const title = node("h2", row.item.title);
      title.tabIndex = -1;
      const feedback = node("p", null, "meta");
      feedback.setAttribute("role", "status");
      article.append(threadBack, title, node("p", time(row.item.created_at), "meta"),
        node("p", row.item.body, "detail-copy"), feedback);
      panel.replaceChildren(article);
      if (!row.unread.hidden) {
        request("/me/notifications/" + encodeURIComponent(row.item.id) + "/read", { auth: true, method: "POST" })
          .then(() => {
            renderMessageCount(row.unread, 0);
            refreshUnread();
          })
          .catch((error) => { feedback.textContent = error.message; });
      }
      return title;
    }

    document.addEventListener("damu-unread", (event) => {
      if (!content.isConnected) return;
      const counts = messageGroups.map(([, , field]) => event.detail?.[field] ?? 0);
      const pendingRequests = event.detail?.contact_request_count ?? 0;
      counts[1] += pendingRequests;
      renderMessageCount(requestsBadge, pendingRequests);
      for (const [index, [group]] of messageGroups.entries())
        renderMessageCount(groupLinks.get(group).badge, counts[index]);
      const nextCounts = counts.join(":");
      if (previousCounts !== undefined && previousCounts !== nextCounts) loadRows();
      previousCounts = nextCounts;
    });
    async function loadRows() {
      const version = ++listVersion;
      const params = new URLSearchParams({ limit: 100 });
      const selectedId = conversationRoute.exec(location.pathname)?.[1];
      if (selectedId) params.set("includeId", selectedId);
      const [conversations, announcements] = await Promise.allSettled([
        request("/conversations?" + params, { auth: true }),
        request("/me/notifications?announcementsOnly=true&limit=100", { auth: true }),
      ]);
      if (!content.isConnected || version !== listVersion) return;
      if (conversations.status === "fulfilled") {
        errors.delete("event");
        errors.delete("direct");
        for (const item of conversations.value)
          addRow(item, item.conversation_type === "event" ? "event" : "direct");
      } else {
        for (const group of ["event", "direct"]) errors.set(group, conversations.reason.message);
      }
      if (announcements.status === "fulfilled") {
        errors.delete("announcement");
        for (const item of announcements.value) addRow(item, "announcement");
      } else errors.set("announcement", announcements.reason.message);
      selectFromLocation();
    }
    window.addEventListener("popstate", () => {
      if (content.isConnected) selectFromLocation(true);
    });
    await loadRows();
  };

  function renderConversation(conversation, panel, back, signal, updates) {
    const viewer = session().user;
    const thread = node("section", null, "chat-thread");
    const header = node("header", null, "chat-thread-header");
    const title = node("h2", conversation.display_title);
    title.id = "chat-title";
    title.tabIndex = -1;
    thread.setAttribute("aria-labelledby", title.id);
    const subtitle = conversation.conversation_type === "direct" ? "私信" : "活动群聊";
    header.append(back, title, node("p", conversation.status === "active" ? subtitle : subtitle + " · 只读", "meta"));
    const feedback = node("p", null, "chat-feedback");
    feedback.setAttribute("role", "status");
    header.append(feedback);

    const viewport = node("div", null, "chat-viewport");
    viewport.tabIndex = 0;
    viewport.setAttribute("role", "region");
    viewport.setAttribute("aria-label", "聊天消息，可向上滚动查看历史");
    const history = node("div", null, "chat-history");
    const older = button("加载更早消息", () => loadMessages(true));
    older.hidden = true;
    history.append(older);
    const messages = node("ol", null, "chat-messages");
    const empty = node("p", "正在加载消息…", "chat-empty");
    viewport.append(history, empty, messages);
    thread.append(header, viewport);
    panel.replaceChildren(thread);

    const base = "/conversations/" + encodeURIComponent(conversation.id);
    const visible = new Map();
    let nextPage;
    let loading = false;
    let readMarker;
    let lastTop = 0;

    function setScroll(position) {
      viewport.scrollTop = position;
      lastTop = viewport.scrollTop;
    }

    function showMessage(message) {
      if (visible.has(message.id)) return null;
      const own = message.sender_user_id === viewer.id;
      const entry = node("li", null, own ? "chat-message own" : "chat-message");
      visible.set(message.id, entry);
      const senderName = message.sender_name || (own ? viewer.nickname : "");
      const metadata = [senderName, time(message.created_at)];
      const body = node("div", null, "chat-message-body");
      let avatar;
      if (conversation.conversation_type === "event" && message.sender_user_id &&
          message.message_type !== "event_cancelled") {
        entry.classList.add("with-avatar");
        avatar = node("span", null, "account-avatar chat-sender-avatar");
        avatar.setAttribute("aria-hidden", "true");
        renderAvatar(avatar, {
          nickname: senderName,
          avatarImageUrl: message.sender_avatar || (own ? viewer.avatarImageUrl || viewer.avatarUrl : null),
        });
      }
      body.append(
        node("p", metadata.filter(Boolean).join(" · "), "meta"),
        node("p", message.recalled_at ? "消息已撤回" : message.body || "附件请在搭慕 App 内查看", "chat-bubble"),
      );
      if (message.sender_user_id && !own && !message.recalled_at) {
        body.append(button("举报消息", () => reasonDialog("举报消息", async (description) => {
          await request(base + "/messages/" + encodeURIComponent(message.id) + "/report", {
            auth: true,
            data: { categoryCode: "inappropriate_content", description },
          });
          dialog.close();
          feedback.textContent = "举报已提交。";
        }), "chat-report"));
      }
      entry.append(body);
      if (avatar) {
        if (own) entry.append(avatar);
        else entry.prepend(avatar);
      }
      return entry;
    }

    function readThrough(message) {
      if (!message || readMarker === message.id) return;
      const previous = readMarker;
      readMarker = message.id;
      request(base + "/read", { auth: true, data: { messageId: message.id } })
        .then(updates.read)
        .catch(() => { if (readMarker === message.id) readMarker = previous; });
    }

    function fetchMessages(pagination = { recentDays }) {
      const params = new URLSearchParams({ limit: pageSize, ...pagination });
      return request(base + "/messages?" + params, { auth: true, signal });
    }

    async function loadMessages(historyPage = false) {
      if (loading || (historyPage && !nextPage)) return;
      loading = true;
      feedback.textContent = "";
      older.disabled = true;
      viewport.setAttribute("aria-busy", "true");
      try {
        const result = await fetchMessages(historyPage ? nextPage : undefined);
        if (!thread.isConnected) return;
        const before = viewport.scrollHeight;
        const top = viewport.scrollTop;
        const entries = [...result.items].reverse().map(showMessage).filter(Boolean);
        messages.prepend(...entries);
        nextPage = result.hasMore && (result.nextCursor ? { cursor: result.nextCursor }
          : result.historyBefore ? { before: result.historyBefore } : null);
        if (!nextPage && document.activeElement === older)
          viewport.focus({ preventScroll: true });
        older.hidden = !nextPage;
        empty.hidden = messages.children.length > 0;
        empty.textContent = nextPage ? `最近 ${recentDays} 天没有消息。` : "暂无消息。";
        setScroll(historyPage && top + viewport.clientHeight < before
          ? top + viewport.scrollHeight - before
          : viewport.scrollHeight);
        if (!readMarker) readThrough(result.items[0]);
      } catch (error) {
        if (thread.isConnected) {
          feedback.textContent = error.message;
          if (!historyPage) {
            empty.textContent = "消息加载失败。";
            if (!history.querySelector(".chat-retry")) {
              const retry = button("重新加载", () => { retry.remove(); loadMessages(); }, "button ghost chat-retry");
              history.append(retry);
            }
          }
        }
      } finally {
        loading = false;
        older.disabled = false;
        viewport.removeAttribute("aria-busy");
      }
    }

    viewport.addEventListener("scroll", () => {
      const top = viewport.scrollTop;
      if (top < lastTop && top <= historyEdge) loadMessages(true);
      lastTop = top;
    });
    viewport.addEventListener("wheel", (event) => {
      if (event.deltaY < 0 && viewport.scrollTop <= historyEdge) loadMessages(true);
    }, { passive: true });

    let submit;
    if (conversation.status === "active") {
      const composer = node("div", null, "chat-composer");
      const form = node("form", null, "form");
      form.innerHTML = '<label><span class="sr-only">发送文字消息</span><textarea name="body" placeholder="输入消息…" rows="2" maxlength="4000" required></textarea></label><button class="button primary" type="submit">发送</button>';
      composer.append(form);
      thread.append(composer);
      submit = form.querySelector('button[type="submit"]');
      submit.disabled = true;
      let draft;
      handleForm(form, composer, async (values) => {
        const body = values.body.trim();
        if (!body) throw new Error("请输入消息。");
        if (draft?.body !== body) draft = { body, clientMessageId: crypto.randomUUID() };
        const message = await request(base + "/messages", { auth: true, data: { messageType: "text", ...draft } });
        updates.sent(message);
        if (!thread.isConnected) return;
        draft = null;
        if (form.elements.body.value === values.body) form.elements.body.value = "";
        const entry = showMessage(message);
        if (entry) messages.append(entry);
        empty.hidden = true;
        setScroll(viewport.scrollHeight);
        try {
          const latest = await fetchMessages();
          if (!thread.isConnected || !latest.items.some((item) => item.id === message.id)) return;
          const atBottom = viewport.scrollHeight - viewport.scrollTop - viewport.clientHeight < historyEdge;
          let newer = null;
          for (const item of latest.items) {
            const existing = visible.get(item.id);
            if (existing) newer = existing;
            else {
              const entry = showMessage(item);
              messages.insertBefore(entry, newer);
              newer = entry;
            }
          }
          if (atBottom) setScroll(viewport.scrollHeight);
          readThrough(latest.items[0]);
        } catch (error) {
          if (thread.isConnected) feedback.textContent = "消息已发送，刷新失败。";
        }
      });
    }
    loadMessages().finally(() => { if (submit) submit.disabled = false; });
    return title;
  }
}

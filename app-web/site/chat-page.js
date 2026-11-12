const recentDays = 7;
const pageSize = 40;
const historyEdge = 64;
export const conversationRoute = /^\/messages\/([0-9a-f-]{36})$/i;
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
}) {
  return async function showMessages() {
    const content = show("消息", "chat-page");
    const layout = node("div", null, "chat-layout");
    const sidebar = node("nav", null, "chat-sidebar");
    sidebar.setAttribute("aria-label", "消息列表");
    const heading = node("h2", "消息列表", "chat-list-heading");
    heading.tabIndex = -1;
    const choices = node("ul", null, "chat-choices");
    const listStatus = node("p", "正在加载会话…", "chat-list-status meta");
    listStatus.setAttribute("role", "status");
    sidebar.append(heading, choices, listStatus);
    const panel = node("div", null, "chat-panel");
    const placeholder = node("div", null, "chat-placeholder");
    const prompt = node("p", "选择一个会话查看消息。");
    const back = actionLink("‹ 消息列表", "/messages", "chat-back text-button");
    back.addEventListener("click", (event) => navigate(event, back.pathname));
    placeholder.append(back, prompt);
    panel.append(placeholder);
    layout.append(sidebar, panel);
    content.append(layout);

    const rows = new Map();
    let activeId = null;
    let threadRequest;

    function navigate(event, href) {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      if (location.pathname === href) return;
      history.pushState(null, "", href);
      selectFromLocation(true);
    }

    function selectFromLocation(focus = false) {
      const id = conversationRoute.exec(location.pathname)?.[1].toLowerCase() ?? null;
      if (id === activeId) return;
      const previous = rows.get(activeId);
      previous?.link.removeAttribute("aria-current");
      threadRequest?.abort();
      activeId = id;
      const selected = rows.get(id);
      layout.classList.toggle("has-thread", Boolean(id));
      document.title = selected ? selected.item.display_title + " · 消息 · 搭慕 DAMU" : "消息 · 搭慕 DAMU";
      if (!selected) {
        prompt.textContent = id ? "找不到这个会话。" : rows.size ? "选择一个会话查看消息。" : "";
        panel.replaceChildren(placeholder);
        if (focus) (previous?.link ?? heading).focus({ preventScroll: true });
        return;
      }
      selected.link.setAttribute("aria-current", "page");
      threadRequest = new AbortController();
      const threadBack = back.cloneNode(true);
      threadBack.addEventListener("click", (event) => navigate(event, threadBack.pathname));
      const threadTitle = renderConversation(selected.item, panel, threadBack, threadRequest.signal, {
        read() { selected.unread.hidden = true; },
        sent(message) {
          selected.preview.textContent = message.body || "暂无文字消息";
          selected.date.textContent = previewTime(message.created_at);
          choices.prepend(selected.entry);
        },
      });
      if (focus) threadTitle.focus({ preventScroll: true });
    }

    try {
      const conversations = await request("/conversations?limit=100", { auth: true });
      if (!content.isConnected) return;
      for (const item of conversations) {
        const entry = node("li");
        const link = actionLink("", "/messages/" + encodeURIComponent(item.id), "chat-choice");
        const isGroup = item.conversation_type === "event";
        const avatar = node("span", isGroup ? "群" : Array.from(item.display_title)[0] || "聊", isGroup ? "chat-avatar group" : "chat-avatar");
        avatar.setAttribute("aria-hidden", "true");
        const label = node("span", null, "chat-choice-label");
        const preview = node("span", item.last_message_body || "暂无文字消息", "chat-choice-preview");
        label.append(node("strong", item.display_title), preview);
        const meta = node("span", null, "chat-choice-meta");
        const date = node("small", previewTime(item.last_message_at));
        const unread = node("small", item.unread_count ? item.unread_count + " 条未读" : "", "chat-unread");
        unread.hidden = !item.unread_count;
        meta.append(date, unread);
        link.append(avatar, label, meta);
        link.addEventListener("click", (event) => navigate(event, link.pathname));
        entry.append(link);
        choices.append(entry);
        rows.set(item.id, { item, link, entry, preview, date, unread });
      }
      listStatus.hidden = rows.size > 0;
      listStatus.textContent = "还没有会话。";
      if (!rows.size) prompt.textContent = "";
      selectFromLocation();
      window.addEventListener("popstate", () => {
        if (content.isConnected) selectFromLocation(true);
      });
    } catch (error) {
      listStatus.textContent = error.message;
      prompt.textContent = "暂时无法加载会话。";
    }
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
      const metadata = [message.sender_name || (own ? viewer.nickname : ""), time(message.created_at)];
      entry.append(
        node("p", metadata.filter(Boolean).join(" · "), "meta"),
        node("p", message.recalled_at ? "消息已撤回" : message.body || "附件请在搭慕 App 内查看", "chat-bubble"),
      );
      if (message.sender_user_id && !own && !message.recalled_at) {
        entry.append(button("举报消息", () => reasonDialog("举报消息", async (description) => {
          await request(base + "/messages/" + encodeURIComponent(message.id) + "/report", {
            auth: true,
            data: { categoryCode: "inappropriate_content", description },
          });
          dialog.close();
          feedback.textContent = "举报已提交。";
        }), "chat-report"));
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

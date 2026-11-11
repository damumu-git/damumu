const recentDays = 7;
const pageSize = 40;
const historyEdge = 64;

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
  return function showConversation(conversation, conversations) {
    const viewer = session().user;
    const content = show("消息", "chat-page");
    document.title = conversation.display_title + " · 消息 · 搭慕 DAMU";
    const layout = node("div", null, "chat-layout");
    const sidebar = node("nav", null, "chat-sidebar");
    sidebar.setAttribute("aria-label", "会话列表");
    const picker = node("details", null, "chat-picker");
    const pickerLabel = node("summary");
    pickerLabel.append(
      node("span", "切换会话", "meta"),
      node("strong", conversation.display_title),
    );
    const choices = node("ul", null, "chat-choices");
    for (const item of conversations) {
      const entry = node("li");
      const link = actionLink(item.display_title, "/messages/" + encodeURIComponent(item.id), "chat-choice");
      if (item.id === conversation.id) link.setAttribute("aria-current", "page");
      else if (item.unread_count) link.append(node("small", item.unread_count + " 条未读"));
      entry.append(link);
      choices.append(entry);
    }
    picker.append(pickerLabel, choices);
    sidebar.append(picker, actionLink("会话列表", "/messages", "text-button"));
    picker.addEventListener("keydown", (event) => {
      if (event.key !== "Escape" || !picker.open) return;
      event.preventDefault();
      picker.open = false;
      pickerLabel.focus();
    });
    content.addEventListener("pointerdown", (event) => {
      if (!picker.contains(event.target)) picker.open = false;
    });

    const thread = node("section", null, "chat-thread");
    const header = node("header", null, "chat-thread-header");
    const title = node("h2", conversation.display_title);
    title.id = "chat-title";
    thread.setAttribute("aria-labelledby", title.id);
    const subtitle = conversation.conversation_type === "direct" ? "私信" : "活动群聊";
    header.append(title, node("p", conversation.status === "active" ? subtitle : subtitle + " · 只读", "meta"));
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
    layout.append(sidebar, thread);
    content.append(layout);

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
        .catch(() => { if (readMarker === message.id) readMarker = previous; });
    }

    function fetchMessages(pagination = { recentDays }) {
      const params = new URLSearchParams({ limit: pageSize, ...pagination });
      return request(base + "/messages?" + params, { auth: true });
    }

    async function loadMessages(historyPage = false) {
      if (loading || (historyPage && !nextPage)) return;
      loading = true;
      feedback.textContent = "";
      older.disabled = true;
      viewport.setAttribute("aria-busy", "true");
      try {
        const result = await fetchMessages(historyPage ? nextPage : undefined);
        if (!content.isConnected) return;
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
        if (content.isConnected) {
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
        draft = null;
        if (form.elements.body.value === values.body) form.elements.body.value = "";
        const entry = showMessage(message);
        if (entry) messages.append(entry);
        empty.hidden = true;
        setScroll(viewport.scrollHeight);
        try {
          const latest = await fetchMessages();
          if (!content.isConnected || !latest.items.some((item) => item.id === message.id)) return;
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
          if (content.isConnected) feedback.textContent = "消息已发送，刷新失败。";
        }
      });
    }
    loadMessages().finally(() => { if (submit) submit.disabled = false; });
  };
}

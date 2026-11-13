export function createFriends({ show, node, button, actionLink, request, handleForm, showError, renderAvatar, refreshUnread }) {
  const requestPath = "/messages/friend-requests";
  const friendsPath = "/me/friends";
  const labels = {
    pending: "待处理", accepted: "已接受", declined: "已拒绝",
    ignored: "已忽略", withdrawn: "已撤回", closed: "已结束",
  };

  async function openChat(id) {
    const thread = await request("/conversations/direct", { auth: true, data: { otherUserId: id } });
    location.assign("/messages/" + encodeURIComponent(thread.id));
  }

  function action(content, label, run, className) {
    return button(label, async (event) => {
      const control = event.currentTarget;
      control.disabled = true;
      try {
        await run();
      } catch (error) {
        showError(content, error);
      } finally {
        control.disabled = false;
      }
    }, className);
  }

  function identity(id, nickname, avatarUrl) {
    const link = actionLink("", "/people/" + encodeURIComponent(id), "activity-organizer");
    const avatar = node("span", null, "account-avatar");
    avatar.setAttribute("aria-hidden", "true");
    renderAvatar(avatar, { nickname, avatarImageUrl: avatarUrl });
    link.append(avatar, node("strong", nickname || "搭慕用户"));
    return link;
  }

  function compose(id, profileContent, actions, refresh) {
    const panel = node("section", null, "activity-section friend-compose");
    const form = node("form", null, "form");
    const field = node("label", "申请说明（选填）");
    const note = node("textarea");
    note.name = "body";
    note.maxLength = 200;
    note.rows = 2;
    field.append(note);
    const send = node("button", "发送好友申请", "button primary");
    send.type = "submit";
    form.append(field, send, button("取消", () => refresh()));
    panel.append(form);
    actions.replaceChildren(panel);
    note.focus();
    handleForm(form, profileContent, async ({ body }) => {
      await request("/friend-requests", { auth: true, data: { userId: id, body } });
      refresh();
    });
  }

  function profileActions(id, content, actions, state, refresh) {
    if (state.is_friend) actions.append(actionLink("已是好友", friendsPath));
    else if (state.friend_request_direction)
      actions.append(actionLink(state.friend_request_direction === "incoming" ? "处理好友申请" : "好友申请已发送", requestPath));
    else if (state.can_request_friend)
      actions.append(button("加好友", () => compose(id, content, actions, refresh), "button primary"));
  }

  async function showFriends() {
    const content = show("我的好友", "workspace-page");
    content.append(actionLink("好友申请", requestPath));
    try {
      const friends = await request("/me/friends", { auth: true });
      if (!content.isConnected) return;
      const field = node("label", "搜索好友", "friend-search");
      const search = node("input");
      search.type = "search";
      search.placeholder = "输入昵称";
      field.append(search);
      const list = node("ul", null, "contact-list");
      const rows = friends.map((friend) => {
        const row = node("li", null, "activity-section friend-row");
        const actions = node("div", null, "detail-actions");
        actions.append(
          action(content, "发消息", () => openChat(friend.id), "button primary"),
          action(content, "解除好友", async () => {
            if (!window.confirm("解除好友后，只有仍符合其他私聊条件才能继续发送消息。确定解除？")) return;
            await request("/me/friends/" + friend.id, { auth: true, method: "DELETE" });
            row.remove();
            render();
          }),
        );
        row.append(identity(friend.id, friend.nickname, friend.avatar_url), actions);
        list.append(row);
        return { row, name: (friend.nickname || "搭慕用户").toLocaleLowerCase() };
      });
      const empty = node("p", null, "meta");
      function render() {
        const query = search.value.trim().toLocaleLowerCase();
        for (const { row, name } of rows) row.hidden = !name.includes(query);
        empty.hidden = Array.from(list.children).some((row) => !row.hidden);
        empty.textContent = query ? "没有匹配的好友。" : "暂无好友。";
      }
      search.addEventListener("input", render);
      content.append(field, list, empty);
      render();
    } catch (error) {
      showError(content, error);
    }
  }

  async function showRequests(previous) {
    const content = previous ?? show("好友申请", "workspace-page");
    const panel = node("div", null, "friend-requests");
    if (!previous) {
      const nav = node("div", null, "section-nav");
      nav.append(actionLink("返回一般消息", "/messages?type=direct"), actionLink("我的好友", friendsPath));
      content.append(nav);
    }
    try {
      const [items, preferences] = await Promise.all([
        request("/friend-requests", { auth: true }),
        request("/me/friends/preferences", { auth: true }),
      ]);
      if (!content.isConnected) return;
      const setting = node("label", null, "contact-preference");
      const checkbox = node("input");
      checkbox.type = "checkbox";
      checkbox.checked = preferences.allow;
      setting.append(checkbox, node("span", "接收好友申请"));
      panel.append(setting);
      checkbox.addEventListener("change", async () => {
        checkbox.disabled = true;
        try {
          await request("/me/friends/preferences", { auth: true, method: "PUT", data: { allow: checkbox.checked } });
        } catch (error) {
          checkbox.checked = !checkbox.checked;
          showError(content, error);
        } finally {
          checkbox.disabled = false;
        }
      });
      for (const incoming of [true, false]) {
        panel.append(node("h2", incoming ? "收到的申请" : "发出的申请"));
        const list = node("ul", null, "contact-list");
        for (const item of items.filter((entry) => entry.incoming === incoming)) {
          const row = node("li", null, "activity-section");
          row.append(identity(item.peer_id, item.peer_nickname, item.peer_avatar),
            node("p", !incoming && item.status === "pending" ? "等待回复" : labels[item.status], "meta"));
          if (item.body) row.append(node("p", item.body, "detail-copy"));
          if (item.status === "pending") {
            const actions = node("div", null, "detail-actions");
            const respond = (label, decision, className) => action(content, label, async () => {
              await request("/friend-requests/" + item.id + "/respond", { auth: true, data: { decision } });
              refreshUnread();
              await showRequests(content);
            }, className);
            if (incoming) {
              actions.append(respond("接受", "accepted", "button primary"), respond("忽略", "ignored"), respond("拒绝", "declined"),
                action(content, "屏蔽", async () => {
                  if (!window.confirm("确定屏蔽这位用户？")) return;
                  await request("/blocks/" + item.peer_id, { auth: true, data: {} });
                  refreshUnread();
                  await showRequests(content);
                }));
            } else actions.append(respond("撤回", "withdrawn"));
            row.append(actions);
          }
          list.append(row);
        }
        panel.append(list.childElementCount ? list : node("p", "暂无申请。", "meta"));
      }
      if (previous) content.querySelector(".friend-requests").replaceWith(panel);
      else content.append(panel);
    } catch (error) {
      showError(content, error);
    }
  }

  return { profileActions, showFriends, showRequests };
}

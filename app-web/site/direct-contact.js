export function createDirectContact({
  show, node, button, actionLink, request, requireLogin, handleForm, showError,
  showReport, renderAvatar, refreshUnread, friends,
}) {
  function compose(kind, eventId, userId) {
    requireLogin(() => {
      const inquiry = kind === "inquiry";
      const content = show(inquiry ? "咨询组织者" : "申请私聊", "reading", true);
      const form = node("form", null, "form");
      const field = node("label", inquiry ? "活动问题" : "打招呼");
      const input = node("textarea");
      input.name = "body";
      input.required = true;
      input.maxLength = 500;
      field.append(input);
      const submit = node("button", "发送", "button primary");
      submit.type = "submit";
      form.append(field, submit);
      content.append(form);
      handleForm(form, content, async (values) => {
        await request("/contact-requests", {
          auth: true,
          data: { kind, eventId, userId, body: values.body },
        });
        form.replaceWith(node("p", "已发送，等待对方回复。", "notice"));
      });
    });
  }

  async function profileActions(id, content, actions) {
    try {
      const state = await request("/contact-requests/options?userId=" + encodeURIComponent(id), { auth: true });
      if (!actions.isConnected) return;
      actions.replaceChildren();
      if (state.can_chat) {
        actions.append(button("发私信", async (event) => {
          const trigger = event.currentTarget;
          trigger.disabled = true;
          try {
            const thread = await request("/conversations/direct", { auth: true, data: { otherUserId: id } });
            location.assign("/messages/" + encodeURIComponent(thread.id));
          } catch (error) {
            showError(content, error);
            trigger.disabled = false;
          }
        }));
      } else if (state.request_event_id) {
        actions.append(button("申请私聊", () => compose("attended", state.request_event_id, id)));
      }
      friends.profileActions(id, content, actions, state, () => profileActions(id, content, actions));
    } catch (error) {
      if (actions.isConnected) showError(content, error);
    }
  }

  async function showRequests() {
    const content = show("联系请求", "workspace-page");
    content.append(actionLink("返回一般消息", "/messages?type=direct"));
    try {
      const [items, preferences] = await Promise.all([
        request("/contact-requests", { auth: true }),
        request("/me/contact-preferences", { auth: true }),
      ]);
      if (!content.isConnected) return;
      const preference = node("label", null, "contact-preference");
      const checkbox = node("input");
      checkbox.type = "checkbox";
      checkbox.checked = preferences.allowAttendedRequests;
      preference.append(checkbox, node("span", "接受同场参加者的私聊请求"));
      content.append(preference);
      checkbox.addEventListener("change", async () => {
        checkbox.disabled = true;
        try {
          await request("/me/contact-preferences", {
            auth: true, method: "PUT", data: { allowAttendedRequests: checkbox.checked },
          });
        } catch (error) {
          checkbox.checked = !checkbox.checked;
          showError(content, error);
        } finally {
          checkbox.disabled = false;
        }
      });
      const list = node("ul", null, "contact-list");
      for (const item of items) {
        const row = node("li", null, "activity-section");
        const avatar = node("span", null, "account-avatar");
        avatar.setAttribute("aria-hidden", "true");
        renderAvatar(avatar, { nickname: item.peer_nickname, avatarImageUrl: item.peer_avatar });
        const identity = node("div", null, "activity-organizer");
        identity.append(avatar, node("strong", item.peer_nickname || "搭慕用户"));
        const type = item.kind === "inquiry" ? "活动咨询" : "私聊请求";
        const status = { pending: item.incoming ? "待处理" : "等待回复", accepted: "已接受", declined: "已结束" };
        row.append(identity, node("p", [type, item.event_title, status[item.status]].filter(Boolean).join(" · "), "meta"),
          node("p", item.body, "detail-copy"));
        const actions = node("div", null, "detail-actions");
        if (item.incoming && item.status === "pending") {
          const respond = async (accept) => {
            for (const action of actions.querySelectorAll("button")) action.disabled = true;
            try {
              const result = await request("/contact-requests/" + item.id + "/respond", {
                auth: true, data: { accept },
              });
              refreshUnread();
              if (result.conversationId)
                location.assign("/messages/" + encodeURIComponent(result.conversationId));
              else showRequests();
            } catch (error) {
              showError(content, error);
              for (const action of actions.querySelectorAll("button")) action.disabled = false;
            }
          };
          actions.append(
            button(item.kind === "inquiry" ? "打开并回复" : "接受", () => respond(true), "button primary"),
            button("拒绝", () => respond(false)),
            button("举报", () => showReport("user", item.peer_id, item.peer_id)),
            button("屏蔽", async () => {
              try {
                await request("/blocks/" + item.peer_id, { auth: true, data: {} });
                refreshUnread();
                showRequests();
              } catch (error) {
                showError(content, error);
              }
            }),
          );
        } else if (item.conversation_id) {
          actions.append(actionLink("打开私信", "/messages/" + encodeURIComponent(item.conversation_id)));
        }
        if (actions.childElementCount) row.append(actions);
        list.append(row);
      }
      content.append(items.length ? list : node("p", "暂无联系请求。", "meta"));
    } catch (error) {
      showError(content, error);
    }
  }
  return { compose, profileActions, showRequests };
}

export function createMemberPages(ui) {
  const {
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
    card,
    setSession,
    session,
    reasonDialog,
    loadGuideCards,
  } = ui;
  const pages = new Map();
  const accountLinks = () => {
    const nav = node("nav", null, "section-nav");
    for (const [name, href] of [
      ["个人资料", "/settings/profile"],
      ["账号", "/settings/account"],
      ["隐私", "/settings/privacy"],
      ["通知偏好", "/settings/notifications"],
    ]) {
      const link = actionLink(name, href, "button ghost");
      if (location.pathname === href) link.setAttribute("aria-current", "page");
      nav.append(link);
    }
    return nav;
  };

  function memberPage(path, title, render) {
    pages.set(path, () =>
      requireLogin(async () => {
        const content = show(title, "workspace-page");
        try {
          await render(content);
        } catch (error) {
          showError(content, error);
        }
      }),
    );
  }

  function bookmark(kind, target) {
    const path = "/me/saved/" + kind + "/" + encodeURIComponent(target);
    let saved = null;
    function update(value) {
      saved = value;
      trigger.setAttribute("aria-pressed", String(saved));
      trigger.textContent = saved ? "已收藏" : "收藏";
      trigger.title = saved ? "取消收藏" : "收藏";
    }
    const trigger = button("收藏", () =>
      requireLogin(async () => {
        trigger.disabled = true;
        try {
          if (saved === null) saved = (await request(path, { auth: true })).saved;
          const result = await request(path, {
            method: saved ? "DELETE" : "PUT",
            auth: true,
          });
          update(result.saved);
        } catch (error) {
          showError(trigger.closest(".page-content"), error);
        } finally {
          trigger.disabled = false;
        }
      }),
    );
    trigger.classList.add("bookmark-button");
    trigger.setAttribute("aria-pressed", "false");
    if (session()) {
      trigger.disabled = true;
      request(path, { auth: true })
        .then((result) => update(result.saved))
        .catch(() => {})
        .finally(() => {
          trigger.disabled = false;
        });
    }
    return trigger;
  }

  function addList(content, entries, render, empty) {
    const list = node("ul", null, "detail-list");
    for (const entry of entries) {
      const row = node("li");
      render(row, entry);
      list.append(row);
    }
    content.append(list.children.length ? list : node("p", empty, "meta"));
  }

  memberPage("/me/saved", "我的收藏", async (content) => {
    content.classList.add("library-page");
    const items = await request("/me/saved", { auth: true });
    const kind = new URLSearchParams(location.search).get("kind");
    const navigation = node("nav", null, "section-nav");
    navigation.setAttribute("aria-label", "收藏类型");
    for (const [label, value] of [["全部", ""], ["活动", "activity"], ["周末指南", "guide"]]) {
      const link = actionLink(label, "/me/saved" + (value ? "?kind=" + value : ""));
      if (value === (kind ?? "")) link.setAttribute("aria-current", "page");
      navigation.append(link);
    }
    content.append(navigation);
    const list = node("ul", null, "library-list");
    for (const item of items.filter((entry) => !kind || entry.kind === kind)) {
      const guide = item.kind === "guide";
      const action = button("取消收藏", async (event) => {
        const trigger = event.currentTarget;
        trigger.disabled = true;
        try {
          await request(
            "/me/saved/" + item.kind + "/" + encodeURIComponent(item.target),
            { method: "DELETE", auth: true },
          );
          pages.get("/me/saved")();
        } catch (error) {
          showError(content, error);
          trigger.disabled = false;
        }
      });
      list.append(libraryRow(
        guide ? { ...item, cover_category_code: item.guide_cover_category } : item,
        {
          href: guide ? "/guides/" + encodeURIComponent(item.target) : eventLink(item.target),
          categoryName: guide ? "周末指南" : item.category_name,
          state: guide ? "" : libraryEventState(item),
          summary: item.summary,
          action,
        },
      ));
    }
    content.append(list.children.length ? list : node("p", "还没有收藏。", "meta"));
  });

  function preferenceKey() {
    return "damu-notifications-unread:" + session().user.id;
  }
  memberPage("/notifications", "通知中心", async (content) => {
    const unread =
      new URLSearchParams(location.search).get("unread") ??
      localStorage.getItem(preferenceKey());
    content.append(
      actionLink("全部通知", "/notifications?unread=0"),
      actionLink("仅看未读", "/notifications?unread=1"),
      button("全部标为已读", async () => {
        try {
          await request("/me/notifications/read-all", {
            method: "POST",
            auth: true,
          });
          pages.get("/notifications")();
        } catch (error) {
          showError(content, error);
        }
      }),
    );
    const items = await request(
      "/me/notifications?unreadOnly=" + (unread === "1"),
      { auth: true },
    );
    addList(
      content,
      items,
      (row, item) => {
        row.append(
          node("strong", item.title),
          node("p", item.body, "detail-copy"),
          node(
            "p",
            time(item.created_at) + (item.read_at ? "" : " · 未读"),
            "meta",
          ),
        );
        let data = item.data;
        try {
          if (typeof data === "string") data = JSON.parse(data);
        } catch {
          data = null;
        }
        const id = data?.conversationId ?? data?.eventId;
        const href =
          typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id)
            ? data.conversationId
              ? "/messages/" + id
              : eventLink(id)
            : null;
        if (href) row.append(actionLink("打开", href));
        if (!item.read_at)
          row.append(
            button("标为已读", async () => {
              try {
                await request("/me/notifications/" + item.id + "/read", {
                  method: "POST",
                  auth: true,
                });
                pages.get("/notifications")();
              } catch (error) {
                showError(content, error);
              }
            }),
          );
      },
      "暂无通知。",
    );
  });

  memberPage("/settings/notifications", "通知偏好", async (content) => {
    content.append(
      accountLinks(),
      node("p", "设置本浏览器打开通知中心时的默认视图。", "meta"),
    );
    const input = node("input");
    input.type = "checkbox";
    input.checked = localStorage.getItem(preferenceKey()) === "1";
    input.addEventListener("change", () =>
      localStorage.setItem(preferenceKey(), input.checked ? "1" : "0"),
    );
    const label = node("label", " 默认仅看未读");
    label.prepend(input);
    content.append(label, actionLink("打开通知中心", "/notifications"));
  });

  memberPage("/settings/account", "账号设置", async (content) => {
    content.append(
      accountLinks(),
      node("p", session().user.email ?? "第三方账号", "meta"),
    );
    content.append(
      actionLink(
        "了解账号注销",
        "https://www.damumu.com/account-deletion.html",
      ),
      button("注销搭慕账号", () =>
        reasonDialog("注销账号", async (confirmation) => {
          if (confirmation !== "注销账号")
            throw new Error("请输入「注销账号」确认。");
          await request("/me", { method: "DELETE", auth: true });
          setSession(null);
          location.assign("/");
        }),
      ),
    );
  });

  memberPage("/settings/privacy", "隐私设置", async (content) => {
    content.append(
      accountLinks(),
      actionLink("阅读隐私政策", "/privacy"),
      node("h2", "已屏蔽用户"),
    );
    const blocked = await request("/me/blocks", { auth: true });
    addList(
      content,
      blocked,
      (row, item) => {
        row.append(
          node("strong", item.nickname),
          button("解除屏蔽", async () => {
            try {
              await request("/blocks/" + item.id, {
                method: "DELETE",
                auth: true,
              });
              pages.get("/settings/privacy")();
            } catch (error) {
              showError(content, error);
            }
          }),
        );
      },
      "还没有屏蔽的用户。",
    );
  });

  memberPage("/me/reports", "举报记录", async (content) => {
    const statuses = {
      submitted: "已提交",
      triaged: "待处理",
      investigating: "处理中",
      resolved: "已处理",
      dismissed: "已驳回",
    };
    addList(
      content,
      await request("/me/reports", { auth: true }),
      (row, item) => {
        row.append(
          node("strong", statuses[item.status] ?? "处理中"),
          node("p", time(item.created_at), "meta"),
        );
      },
      "还没有举报记录。",
    );
  });

  memberPage("/feedback", "反馈与建议", async (content) => {
    const form = node("form", null, "form");
    form.innerHTML =
      '<label>建议内容<textarea name="text" maxlength="1000" required></textarea></label><button type="submit" class="button primary">提交建议</button>';
    content.append(form, actionLink("查看举报记录", "/me/reports"));
    handleForm(form, content, async (values) => {
      await request("/me/suggestions", {
        auth: true,
        data: { text: values.text.trim() },
      });
      pages.get("/feedback")();
    });
    const history = await request("/me/suggestions", { auth: true });
    addList(
      content,
      history,
      (row, item) => {
        row.append(
          node("p", item.body, "detail-copy"),
          node("p", item.reply ?? "等待回复", "meta"),
        );
      },
      "还没有提交过建议。",
    );
  });

  memberPage("/organizer", "组织者总览", async (content) => {
    const items = await request("/me/activities", { auth: true });
    const hosted = items.filter(
      (item) => item.organizer_user_id === session().user.id,
    );
    const pending = hosted.reduce((total, item) => total + item.pending_count, 0);
    content.append(
      actionLink("发起活动", "/activities/new", "button primary"),
      node("p", `${hosted.length} 场活动 · ${pending} 条报名待审核`, "meta"),
    );
    addList(
      content,
      hosted,
      (row, item) => {
        row.append(
          actionLink(
            item.title,
            "/organizer/activities/" + item.id,
            "text-button",
          ),
          node(
            "p",
            `${time(item.starts_at)} · ${item.approved_count} 人已确认 · ${item.pending_count} 条待审核`,
            "meta",
          ),
          actionLink("复办", "/activities/new?copy=" + item.id),
        );
      },
      "还没有发起过活动。",
    );
  });

  function checkIn(id) {
    return requireLogin(async () => {
      const content = show("活动签到", "workspace-page");
      try {
        const items = await request("/events/" + id + "/members", {
          auth: true,
        });
        content.append(actionLink("返回工作台", "/organizer/activities/" + id));
        addList(
          content,
          items.filter(
            (item) =>
              item.user_id !== session().user.id &&
              ["approved", "attended"].includes(item.status),
          ),
          (row, item) => {
            row.append(node("strong", item.nickname ?? "搭慕用户"));
            if (item.status === "attended")
              row.append(node("p", "已签到", "meta"));
            else
              row.append(
                button("确认到场", async (event) => {
                  const trigger = event.currentTarget;
                  trigger.disabled = true;
                  try {
                    await request(
                      "/events/" +
                        id +
                        "/members/" +
                        item.user_id +
                        "/check-in",
                      { method: "POST", auth: true },
                    );
                    checkIn(id);
                  } catch (error) {
                    showError(content, error);
                    trigger.disabled = false;
                  }
                }),
              );
          },
          "暂无可签到的参加者。",
        );
      } catch (error) {
        showError(content, error);
      }
    });
  }

  function activityFeedback(id) {
    return requireLogin(async () => {
      const content = show("活动后评价", "account-page");
      content.append(actionLink("返回活动", eventLink(id)));
      try {
        const eligibility = await request(
          "/feedback/eligibility?targetType=activity&eventId=" + id,
          { auth: true },
        );
        if (!eligibility.eligible)
          return content.append(
            node("p", "只有符合条件的已结束活动参与者可以评价。", "meta"),
          );
        const form = node("form", null, "form feedback-form");
        const choices = {
          punctual: "准时",
          well_organized: "组织有序",
          clear_communication: "沟通清晰",
          welcoming: "氛围友好",
          safe_respectful: "安全且尊重",
          good_value: "费用合理",
          would_join_again: "愿意再参加",
        };
        const presets = node("fieldset");
        presets.append(node("legend", "预设标签（选填，最多一个）"));
        const chips = node("div", null, "feedback-chips");
        let selected = eligibility.likeTag ?? "";
        for (const [code, title] of Object.entries(choices)) {
          const chip = button(title, () => {
            selected = selected === code ? "" : code;
            for (const choice of chips.children)
              choice.setAttribute("aria-pressed", String(choice.dataset.tag === selected));
          });
          chip.dataset.tag = code;
          chip.setAttribute("aria-pressed", String(selected === code));
          chips.append(chip);
        }
        presets.append(chips);
        const custom = node("fieldset");
        custom.append(
          node("legend", "自定义标签（选填，最多两个）"),
          node("p", "每个标签最多 15 字，活动组织者可看到标签内容。", "meta"),
        );
        const inputs = node("div", null, "form-row");
        for (let i = 0; i < 2; i++) {
          const label = node("label", "自定义标签 " + (i + 1));
          const input = node("input");
          input.name = "customTag" + (i + 1);
          input.maxLength = 15;
          input.value = eligibility.customTags?.[i] ?? "";
          label.append(input);
          inputs.append(label);
        }
        custom.append(inputs);
        const submit = node("button", "保存评价", "button primary");
        submit.type = "submit";
        form.append(presets, custom, submit);
        content.append(form);
        handleForm(form, content, async (values) => {
          const customTags = [values.customTag1, values.customTag2]
            .map((tag) => tag.trim()).filter(Boolean);
          if (!selected && !customTags.length) throw new Error("请选择或填写至少一个评价标签。");
          if (new Set(customTags.map((tag) => tag.toLowerCase())).size !== customTags.length)
            throw new Error("两个自定义标签需要不同。");
          await request("/feedback", {
            auth: true,
            data: {
              eventId: id,
              targetType: "activity",
              feedbackType: "like",
              tagCode: selected || null,
              customTags,
            },
          });
          form.replaceWith(node("p", "评价已保存。", "notice"));
        });
      } catch (error) {
        showError(content, error);
      }
    });
  }

  async function topic(kind, slug) {
    const content = show(
      kind === "places" ? "地区专题" : "分类专题",
      "workspace-page",
    );
    try {
      const catalog = await request(
        kind === "places" ? "/regions" : "/categories",
      );
      if (!slug) {
        const links = node("div", null, "section-nav");
        for (const entry of catalog.filter((item) => item.level === 1)) {
          links.append(
            actionLink(
              entry.name_zh_cn,
              "/" + kind + "/" + encodeURIComponent(entry.code),
            ),
          );
        }
        content.append(links);
        return;
      }
      const item = catalog.find(
        (entry) => entry.code?.toLowerCase() === slug.toLowerCase(),
      );
      if (!item) throw new Error("这个专题不存在。");
      content.querySelector("h1").textContent = item.name_zh_cn;
      const params = new URLSearchParams({ limit: "20" });
      if (kind === "categories") {
        if (item.level === 1) {
          const children = catalog.filter(
            (entry) => entry.parent_id === item.id,
          );
          for (const entry of children)
            content.append(
              actionLink(entry.name_zh_cn, "/categories/" + entry.code),
            );
        }
        params.set("categoryId", item.id);
      } else {
        const parent = catalog.find((entry) => entry.code === item.parent_code);
        params.set(
          "city",
          item.level === 1
            ? item.code
            : item.level === 2
              ? item.parent_code
              : (parent?.parent_code ?? ""),
        );
        if (item.level > 1) params.set("district", item.code);
      }
      const result = await request("/activities?" + params);
      const grid = node("div", null, "cards");
      grid.append(...result.items.map(card));
      content.append(
        grid.children.length ? grid : node("p", "暂无活动。", "meta"),
        node("h2", "相关指南"),
      );
      await loadGuideCards(
        content,
        false,
        kind === "places" ? { region: item.code } : { categoryId: item.id },
      );
    } catch (error) {
      showError(content, error);
    }
  }

  return { pages, bookmark, accountLinks, checkIn, activityFeedback, topic };
}

import { datePresets, dateQuery, dateRange, dayInSeoul, shiftDay } from "/seoul-dates.js";

export function createCommunityPages(ui) {
  const {
    show,
    refreshCurrentPage,
    node,
    button,
    actionLink,
    showError,
    handleForm,
    request,
    requireLogin,
    eventLink,
    card,
    area,
    cover,
    prepareCover,
    memberBadge,
    renderAvatar,
    time,
    session,
  } = ui;
  const slots = {
    saturday: "周六方便",
    sunday: "周日方便",
    either: "两天都可以",
  };

  function list(content, rows, render, empty) {
    const result = node("ul", null, "detail-list");
    for (const item of rows) {
      const row = node("li");
      render(row, item);
      result.append(row);
    }
    content.append(rows.length ? result : node("p", empty, "meta"));
  }
  function eventGrid(content, items, empty = "暂无活动。") {
    const grid = node("div", null, "cards");
    grid.append(...items.map(card));
    content.append(items.length ? grid : node("p", empty, "meta"));
  }

  function groupFacts(item) {
    const facts = [
      item.region_name,
      item.capacity ? `${item.member_count} / ${item.capacity} 人` : `${item.member_count} 名成员`,
      item.join_mode === "approval" ? "组主确认后加入" : "自由加入",
    ];
    if (item.min_age && item.max_age) facts.push(`${item.min_age}–${item.max_age} 岁`);
    else if (item.min_age) facts.push(`${item.min_age} 岁起`);
    else if (item.max_age) facts.push(`${item.max_age} 岁及以下`);
    return node("p", facts.filter(Boolean).join(" · "), "meta group-facts");
  }

  function groupTags(item) {
    const tags = node("div", null, "group-tags");
    for (const label of item.categories ?? []) tags.append(node("span", label));
    return tags;
  }

  function groupCard(item) {
    const link = actionLink("", "/groups/" + item.id, "group-card");
    const summary = node("div", null, "group-card-copy");
    summary.append(node("h2", item.title), groupFacts(item));
    if (item.description) summary.append(node("p", item.description, "group-card-description"));
    if (item.categories?.length) summary.append(groupTags(item));
    link.append(cover(item, "group-card-thumbnail"), summary);
    return link;
  }

  async function catalog(kind) {
    const intent = kind === "intents";
    const root = intent ? "/interests" : "/groups";
    const content = show(intent ? "想一起去" : "活动小组", "workspace-page");
    if (intent) {
      content.append(
        node("p", "先征集时段和兴趣，有了正式活动再报名。", "meta"),
        actionLink("发起意向征集", root + "/new", "button primary"),
      );
    } else {
      const header = node("header", null, "group-catalog-header");
      header.append(content.querySelector("h1"), actionLink("创建小组", root + "/new", "button primary"));
      content.append(header);
    }
    try {
      const items = await request("/web/" + kind);
      if (!intent) {
        const groups = node("ul", null, "group-catalog-list");
        groups.setAttribute("role", "list");
        for (const item of items) {
          const row = node("li");
          row.append(groupCard(item));
          groups.append(row);
        }
        content.append(items.length ? groups : node("p", "还没有小组。", "meta"));
        return;
      }
      list(
        content,
        items,
        (row, item) => {
          row.append(
            actionLink(item.title, root + "/" + item.id, "text-button"),
            node("p", item.description, "detail-copy"),
            node(
              "p",
              [item.region_name, item.event_id ? "已有正式活动" : "意向征集"].join(" · "),
              "meta",
            ),
          );
        },
        "还没有征集。可以先写下你想找人一起做的事。",
      );
    } catch (error) {
      showError(content, error);
    }
  }

  function create(kind) {
    return requireLogin(async () => {
      const intent = kind === "intents";
      const content = show(
        intent ? "发起意向征集" : "创建活动小组",
        "editor-page",
      );
      const form = node("form", null, "form");
      form.innerHTML =
        '<label>标题<input name="title" minlength="2" maxlength="100" required></label><label>介绍<textarea name="description" minlength="2" maxlength="1000" required></textarea></label><button type="submit" class="button primary">发布</button>';
      let pendingGroup;
      let coverUpload = Promise.resolve(null);
      try {
        const regions = await request("/regions");
        const field = node("label", intent ? "市／道" : "市／道（选填）");
        const select = node("select");
        select.name = "regionCode";
        select.required = intent;
        select.add(new Option("选择地区", ""));
        for (const item of regions.filter((region) => region.level === 1))
          select.add(new Option(item.name_zh_cn, item.code));
        field.append(select);
        form.prepend(field);
        if (!intent) {
          const categories = (await request("/categories")).filter((category) => category.level === 1);
          const fieldset = node("fieldset", null, "group-categories");
          fieldset.append(node("legend", "小组分类（可多选）"));
          const coverSelect = node("select");
          coverSelect.name = "coverCategoryId";
          function updateCoverOptions() {
            const previous = coverSelect.value;
            coverSelect.replaceChildren(new Option("默认封面", ""));
            for (const input of fieldset.querySelectorAll("input:checked"))
              coverSelect.add(new Option(input.parentElement.textContent, input.value));
            if ([...coverSelect.options].some((option) => option.value === previous)) coverSelect.value = previous;
          }
          for (const category of categories) {
            const label = node("label");
            const checkbox = node("input");
            checkbox.type = "checkbox";
            checkbox.name = "category";
            checkbox.value = category.id;
            checkbox.addEventListener("change", updateCoverOptions);
            label.append(checkbox, category.name_zh_cn);
            fieldset.append(label);
          }
          updateCoverOptions();
          const coverField = node("label", "系统分类封面");
          coverField.append(coverSelect);
          const coverPicker = node("section", null, "group-cover-picker");
          const preview = node("div", null, "group-cover-preview");
          const file = node("input", null, "sr-only");
          file.type = "file";
          file.accept = "image/jpeg,image/png,image/webp";
          file.hidden = true;
          const status = node("p", null, "meta group-cover-status");
          status.setAttribute("role", "status");
          const choose = button("上传封面", () => file.click(), "button primary");
          const icon = node("span", null, "cover-camera");
          icon.setAttribute("aria-hidden", "true");
          const chooseText = node("span", "上传封面");
          choose.replaceChildren(icon, chooseText);
          const clear = button("使用系统封面", () => {
            file.value = "";
            coverUpload = Promise.resolve(null);
            updateCover();
          }, "button");
          const actions = node("div", null, "group-cover-actions");
          actions.append(choose, clear);
          const pickerControls = node("div", null, "group-cover-controls");
          pickerControls.append(coverField, actions, status, file);
          coverPicker.append(preview, pickerControls);

          function updateCover() {
            const category = categories.find((item) => item.id === coverSelect.value);
            const image = cover({
              cover_category_code: category?.code,
              category_cover_url: category?.cover_image_url,
            });
            image.alt = "小组封面预览";
            preview.replaceChildren(image);
            const task = coverUpload;
            clear.hidden = !file.files.length;
            chooseText.textContent = file.files.length ? "更换图片" : "上传封面";
            status.textContent = file.files.length ? "正在准备预览…" : "支持 JPG、PNG、WebP";
            task.then((upload) => {
              if (coverUpload !== task || !upload) return;
              const source = URL.createObjectURL(upload.get("cover"));
              const selected = node("img");
              selected.alt = image.alt;
              selected.addEventListener("load", () => {
                URL.revokeObjectURL(source);
                if (coverUpload !== task) return;
                preview.replaceChildren(selected);
                status.textContent = file.files[0]?.name || "";
              }, { once: true });
              selected.addEventListener("error", () => {
                URL.revokeObjectURL(source);
                if (coverUpload === task) status.textContent = "无法显示预览，请重新选择图片。";
              }, { once: true });
              selected.src = source;
            }).catch((error) => {
              if (coverUpload !== task) return;
              file.value = "";
              coverUpload = Promise.resolve(null);
              updateCover();
              status.textContent = error.message || "无法读取图片，请重新选择。";
            });
          }
          file.addEventListener("change", () => {
            coverUpload = prepareCover(file.files[0]);
            updateCover();
          });
          coverSelect.addEventListener("change", updateCover);
          fieldset.addEventListener("change", updateCover);
          updateCover();
          const config = node("div", null, "form group-settings");
          config.innerHTML = `
            <div class="form-row">
              <label>人数上限（含组主）<input type="number" name="capacity" min="2" max="50" value="50" required></label>
              <label>加入方式<select name="joinMode"><option value="open">自由加入</option><option value="approval">组主确认后加入</option></select></label>
            </div>
            <div class="form-row">
              <label>最低年龄（选填）<input type="number" name="minAge" min="14" max="120"></label>
              <label>最高年龄（选填）<input type="number" name="maxAge" min="14" max="120"></label>
            </div>`;
          form.lastElementChild.before(fieldset, coverPicker, config);
        }
      } catch (error) {
        showError(content, error);
        return;
      }
      content.append(form);
      handleForm(form, content, async (values) => {
        if (intent) {
          const created = await request("/web/intents", { auth: true, data: values });
          location.assign("/interests/" + created.id);
          return;
        }
        const image = await coverUpload;
        if (!pendingGroup) {
          pendingGroup = await request("/web/groups", {
            auth: true,
            data: {
              title: values.title,
              description: values.description,
              regionCode: values.regionCode || null,
              categoryIds: [...form.querySelectorAll("input[name=category]:checked")].map((input) => input.value),
              coverCategoryId: values.coverCategoryId || null,
              capacity: values.capacity ? Number(values.capacity) : null,
              minAge: values.minAge ? Number(values.minAge) : null,
              maxAge: values.maxAge ? Number(values.maxAge) : null,
              joinMode: values.joinMode,
            },
          });
        }
        if (image) {
          try {
            await request("/web/groups/" + pendingGroup.id + "/cover", { auth: true, data: image });
          } catch (error) {
            if (!content.querySelector(".group-cover-recovery")) {
              form.before(actionLink("前往已创建的小组", "/groups/" + pendingGroup.id, "group-cover-recovery"));
              form.querySelector('button[type="submit"]').textContent = "重试上传封面";
            }
            throw error;
          }
        }
        location.assign("/groups/" + pendingGroup.id);
      });
    });
  }

  async function attachEvent(content, endpoint, label, activeOnly, refresh) {
    const activities = await request("/me/activities", { auth: true });
    const own = activities.filter(
      (item) =>
        item.organizer_user_id === session().user.id &&
        (activeOnly
          ? ["published", "full"]
          : ["published", "full", "completed"]
        ).includes(item.event_status),
    );
    if (!own.length)
      return content.append(
        node("p", "请先发起一场公开活动，再回来关联。", "meta"),
        actionLink("发起活动", "/activities/new"),
      );
    const form = node("form", null, "form");
    const field = node("label", "选择自己发起的活动");
    const select = node("select");
    select.name = "eventId";
    for (const item of own) {
      const date = item.starts_at ? new Intl.DateTimeFormat("zh-CN", {
        timeZone: "Asia/Seoul", month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit",
      }).format(new Date(item.starts_at)) : "时间待定";
      const category = [item.major_category_name, item.minor_category_name, item.category_name]
        .find(Boolean);
      select.add(new Option([item.title, date, category, "发布者：" + (session().user.nickname || "我")]
        .filter(Boolean).join(" · "), item.id));
    }
    field.append(select);
    const submit = node("button", label, "button primary");
    submit.type = "submit";
    form.append(field, submit);
    content.append(form);
    handleForm(form, content, async (values) => {
      await request(endpoint, { method: "PUT", auth: true, data: values });
      await refresh();
    });
  }

  async function intentDetail(id, previous) {
    if (previous) return refreshCurrentPage(previous, () => renderIntent(id, true));
    return renderIntent(id, false);
  }

  async function renderIntent(id, deferred) {
    const content = show("意向征集", "guide-article", false, deferred);
    try {
      const { item, votes } = await request("/web/intents/" + id, {
        auth: true,
      });
      content.querySelector("h1").textContent = item.title;
      content.append(
        node("p", item.region_name, "meta"),
        node("p", item.description, "detail-copy"),
      );
      if (item.converted) {
        content.append(node("p", "征集已结束。", "notice"));
        if (item.event_id)
          content.append(
            actionLink(
              "查看正式活动并报名",
              eventLink(item.event_id),
              "button primary",
            ),
          );
        return content;
      }
      content.append(
        node("p", "这是意向征集。提交时段后仍需等正式活动开放报名。", "notice"),
      );
      const options = node("div", null, "section-nav");
      for (const [slot, label] of Object.entries(slots)) {
        const count = votes.find((vote) => vote.slot === slot)?.count ?? 0;
        const choice = button(
          label + " · " + count,
          () =>
            requireLogin(async () => {
              try {
                await request("/web/intents/" + id + "/vote", {
                  method: "PUT",
                  auth: true,
                  data: { slot },
                });
                await intentDetail(id, content);
              } catch (error) {
                showError(content, error);
              }
            }),
          item.viewer_slot === slot ? "button primary" : "button ghost",
        );
        choice.setAttribute("aria-pressed", String(item.viewer_slot === slot));
        options.append(choice);
      }
      content.append(options);
      if (item.viewer_slot)
        content.append(
          button(
            "撤回意向",
            async () => {
              try {
                await request("/web/intents/" + id + "/vote", {
                  method: "DELETE",
                  auth: true,
                });
                await intentDetail(id, content);
              } catch (error) {
                showError(content, error);
              }
            },
            "text-button",
          ),
        );

      if (session()?.user.id === item.owner_id)
        await attachEvent(
          content,
          "/web/intents/" + id + "/event",
          "关联正式活动",
          true,
          () => intentDetail(id, content),
        );
      return content;
    } catch (error) {
      if (deferred) throw error;
      showError(content, error);
    }
  }

  async function groupDetail(id, previous) {
    if (previous) return refreshCurrentPage(previous, () => renderGroup(id, true));
    return renderGroup(id, false);
  }

  async function renderGroup(id, deferred) {
    const content = show("活动小组", "workspace-page", false, deferred);
    try {
      const { item, events, members, applications } = await request("/web/groups/" + id, {
        auth: true,
      });
      content.querySelector("h1").textContent = item.title;
      const endpoint = "/web/groups/" + id;
      const owner = session()?.user.id === item.owner_id;
      const hero = node("section", null, "group-hero");
      const copy = node("div", null, "group-hero-copy");
      const ownerLink = actionLink("组主主页", "/people/" + item.owner_id);
      const host = node("div", null, "group-host");
      host.append(ownerLink, memberBadge(item.owner_level));
      copy.append(groupTags(item), node("p", item.description, "detail-copy"), groupFacts(item), host);
      const actions = node("div", null, "section-nav");
      const change = (path, options) => requireLogin(async () => {
        try {
          await request(endpoint + path, { auth: true, ...options });
          await groupDetail(id, content);
        } catch (error) {
          showError(content, error);
        }
      });
      if (!owner) {
        const label = item.joined ? "退出小组" : item.pending ? "撤回申请" :
          item.join_mode === "approval" ? "申请加入" : "加入小组";
        actions.append(button(label, () => change("/membership", {
          method: item.joined || item.pending ? "DELETE" : "PUT",
        }), "button primary"));
        if (!item.joined)
          copy.append(node("p", item.pending ? "加入申请等待组主确认。" : "加入后，昵称会显示在公开成员名单。", "meta"));
      }
      if (item.conversation_id)
        actions.append(actionLink("打开小组聊天", "/messages/" + item.conversation_id, "button"));
      copy.append(actions);
      hero.append(cover(item), copy);
      content.append(hero);
      if (owner) {
        const management = node("section", null, "group-management");
        management.append(node("h2", "小组管理"));
        if (item.join_mode === "approval") {
          management.append(node("h3", "加入申请"));
          list(management, applications, (row, applicant) => {
            const decide = (accept) => change("/applications/" + applicant.id, { data: { accept } });
            const actions = node("div", null, "section-nav");
            actions.append(button("通过", () => decide(true)), button("拒绝", () => decide(false)));
            row.append(actionLink(applicant.nickname, "/people/" + applicant.id), actions);
          }, "暂无待处理申请。");
        }
        const announcement = node("form", null, "form");
        announcement.innerHTML = '<label>聊天置顶公告<textarea name="body" maxlength="500" required></textarea></label><button type="submit" class="button primary">发布并置顶</button>';
        handleForm(announcement, management, async ({ body }) => {
          await request(endpoint + "/announcements", { auth: true, data: { body } });
          announcement.reset();
          status.textContent = "公告已发布，小组聊天将显示最新公告。";
        });
        const status = node("p", null, "meta");
        status.setAttribute("role", "status");
        management.append(announcement, status);
        content.append(management);
      }
      content.append(node("h2", "即将举办"));
      eventGrid(
        content,
        events.filter((event) => Date.parse(event.starts_at) >= Date.now()),
        "暂无即将举办的活动。",
      );
      content.append(node("h2", "往期活动"));
      eventGrid(
        content,
        events.filter((event) => Date.parse(event.starts_at) < Date.now()),
        "暂无往期活动。",
      );
      content.append(node("h2", "成员"));
      list(
        content,
        members,
        (row, member) => {
          const actions = node("div", null, "section-nav group-member");
          actions.append(actionLink(member.nickname, "/people/" + member.id, "text-button"), memberBadge(member.member_level));
          if (owner && member.id !== item.owner_id)
            actions.append(button("移出小组", () => {
              if (window.confirm("将 " + member.nickname + " 移出小组？"))
                change("/members/" + member.id, { method: "DELETE" });
            }));
          row.append(actions);
        },
        "暂无成员。",
      );
      if (owner)
        await attachEvent(
          content,
          "/web/groups/" + id + "/events",
          "加入小组活动列表",
          false,
          () => groupDetail(id, content),
        );
      return content;
    } catch (error) {
      if (deferred) throw error;
      showError(content, error);
    }
  }

  function followButton(id, onChange) {
    let following = false;
    const trigger = button("关注", () =>
      requireLogin(async () => {
        trigger.disabled = true;
        try {
          const state = await request("/web/follows/" + id, {
            method: following ? "DELETE" : "PUT",
            auth: true,
          });
          update(state.following);
          onChange?.();
        } catch (error) {
          showError(trigger.closest("main, section") ?? trigger.parentElement, error);
        } finally {
          trigger.disabled = false;
        }
      }),
    );
    function update(value) {
      following = value;
      trigger.textContent = following ? "取消关注" : "关注";
      trigger.setAttribute("aria-pressed", String(following));
    }
    if (session())
      request("/web/follows/" + id, { auth: true })
        .then((state) => update(state.following))
        .catch(() => {});
    return trigger;
  }

  async function calendar() {
    const content = show("活动日历", "agenda-page");
    const params = new URLSearchParams(location.search);
    const today = dayInSeoul();
    const selected = params.get("month");
    const month = /^20\d{2}-(0[1-9]|1[0-2])$/.test(selected) ? selected : null;
    const preset = params.get("when");
    let range = dateRange(preset, today) ?? [today, shiftDay(today, 29)];
    const filters = node("nav", null, "agenda-filters");
    filters.setAttribute("aria-label", "日历日期");
    for (const [key, label] of [["", "未来 30 天"], ...Object.entries(datePresets)]) {
      const link = actionLink(label, key ? "/calendar?when=" + key : "/calendar", "filter-pill");
      if (!month && (key ? key === preset : !Object.hasOwn(datePresets, preset)))
        link.setAttribute("aria-current", "page");
      filters.append(link);
    }
    const monthLink = actionLink("按月查看", "/calendar?month=" + (month || today.slice(0, 7)), "filter-trigger");
    if (month) {
      monthLink.classList.add("is-selected");
      monthLink.setAttribute("aria-current", "page");
    }
    filters.append(monthLink);
    content.append(filters);

    if (month) {
      const [year, number] = month.split("-").map(Number);
      const adjacent = (offset) => new Date(Date.UTC(year, number - 1 + offset, 1)).toISOString().slice(0, 7);
      range = [month + "-01", shiftDay(adjacent(1) + "-01", -1)];
      const controls = node("div", null, "agenda-month");
      controls.append(
        actionLink("上个月", "/calendar?month=" + adjacent(-1)),
        node("strong", `${year} 年 ${number} 月`),
        actionLink("下个月", "/calendar?month=" + adjacent(1)),
      );
      content.append(controls);
    }

    const dayNumber = new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Seoul", month: "long", day: "numeric" });
    const weekday = new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Seoul", weekday: "long" });
    const hour = new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Seoul", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
    const results = node("div", null, "agenda-results");
    const state = node("p", "正在查找活动…", "meta");
    state.setAttribute("role", "status");
    const dates = new Map();
    const seen = new Set();
    const categoryNames = request("/categories")
      .then((items) => new Map(items.map((item) => [item.code, item.name_zh_cn])))
      .catch(() => new Map());
    let cursor;
    const more = button("加载更多活动", () => load(cursor));
    more.hidden = true;
    content.append(state, results, more);

    async function load(position) {
      more.disabled = true;
      state.textContent = "正在查找活动…";
      try {
        const query = new URLSearchParams({ ...dateQuery(range), sort: "recommended", limit: "30" });
        if (position) query.set("cursor", position);
        const [page, names] = await Promise.all([request("/activities?" + query), categoryNames]);
        if (!content.isConnected) return;
        for (const event of page.items) {
          const start = new Date(event.starts_at);
          if (!event.starts_at || !Number.isFinite(start.valueOf()) || seen.has(event.id)) continue;
          seen.add(event.id);
          const key = dayInSeoul(start);
          if (!dates.has(key)) {
            const group = node("section", null, "agenda-day");
            group.id = "calendar-" + key;
            const heading = node("h2", null, "agenda-day-heading");
            heading.append(
              node("span", dayNumber.format(start)),
              node("small", key === today ? "今天 · " + weekday.format(start) : weekday.format(start)),
            );
            const entries = node("ul", null, "agenda-events");
            group.append(heading, entries);
            results.append(group);
            dates.set(key, entries);
          }
          const item = node("li", null, "agenda-event");
          const link = actionLink("", eventLink(event.id), "agenda-event-link");
          const copy = node("div", null, "agenda-event-copy");
          copy.append(
            node("strong", event.title),
            node("span", [hour.format(start), area(event)].filter(Boolean).join(" · "), "meta"),
          );
          const major = event.major_category_name || names.get(event.cover_category_code);
          const minor = event.category_name || names.get(event.cover_subcategory_code);
          const labels = (event.cover_category_code === event.cover_subcategory_code && minor
            ? [minor] : [major, minor]).filter(Boolean);
          if (labels.length) {
            const categories = node("span", null, "agenda-event-categories");
            for (const label of labels) categories.append(node("span", label));
            copy.append(categories);
          }
          const image = cover(event, "agenda-cover");
          image.alt = "";
          link.append(image, copy);
          item.append(link);
          if (event.organizer_name) {
            const organizer = event.organizer_user_id
              ? actionLink("", "/people/" + encodeURIComponent(event.organizer_user_id), "agenda-organizer")
              : node("span", null, "agenda-organizer");
            const avatar = node("span", null, "account-avatar");
            avatar.setAttribute("aria-hidden", "true");
            renderAvatar(avatar, { nickname: event.organizer_name, avatarImageUrl: event.organizer_avatar });
            const identity = node("span", null, "agenda-organizer-copy");
            identity.append(node("small", "发布者", "meta"), node("span", event.organizer_name));
            organizer.append(avatar, identity);
            item.append(organizer);
          }
          dates.get(key).append(item);
        }
        cursor = page.hasMore ? page.nextCursor : null;
        more.hidden = !cursor;
        state.textContent = seen.size ? "活动时间按韩国时间显示" : "这段时间还没有公开活动。";
      } catch (error) {
        if (!content.isConnected) return;
        state.replaceChildren(node("span", error.message + " "), button("重试", () => load(position), "text-button"));
      } finally {
        more.disabled = false;
      }
    }
    await load();
  }

  async function mapPage() {
    const content = show("地区地图", "workspace-page");
    content.append(
      node("p", "地图展示行政区范围。加载地图会连接 OpenStreetMap。", "meta"),
    );
    try {
      const regions = await request("/regions");
      const form = node("form", null, "form");
      function selectField(name, text) {
        const label = node("label", text);
        const select = node("select");
        select.name = name;
        label.append(select);
        form.append(label);
        return select;
      }
      const province = selectField("province", "市／道");
      const district = selectField("district", "市／郡／区");
      const ward = selectField("ward", "下辖区");
      function options(select, choices, all) {
        select.replaceChildren(new Option(all, ""));
        for (const region of choices)
          select.add(new Option(region.name_zh_cn, region.code));
        select.disabled = !choices.length;
        select.parentElement.hidden = select.disabled;
      }
      options(
        province,
        regions.filter((entry) => entry.level === 1),
        "请选择市／道",
      );
      province.required = true;
      function districts() {
        options(
          district,
          regions.filter(
            (entry) =>
              entry.level === 2 && entry.parent_code === province.value,
          ),
          "整个市／道",
        );
        wards();
      }
      function wards() {
        options(
          ward,
          regions.filter(
            (entry) =>
              entry.level === 3 && entry.parent_code === district.value,
          ),
          "整个市",
        );
      }
      province.addEventListener("change", districts);
      district.addEventListener("change", wards);
      districts();
      const submit = node("button", "加载地图", "button primary");
      submit.type = "submit";
      form.append(submit);
      const result = node("div");
      content.append(form, result);
      handleForm(form, content, async (values) => {
        const code = values.ward || values.district || values.province;
        const area = await request("/web/map/" + encodeURIComponent(code));
        const url = new URL("https://www.openstreetmap.org/export/embed.html");
        url.searchParams.set(
          "bbox",
          [area.west, area.south, area.east, area.north].join(","),
        );
        url.searchParams.set("layer", "mapnik");
        const frame = node("iframe", null, "area-map");
        frame.title = area.name + "行政区地图";
        frame.referrerPolicy = "no-referrer";
        frame.src = url.href;
        result.replaceChildren(
          frame,
          actionLink("浏览该地区的活动", "/places/" + encodeURIComponent(code)),
        );
      });
    } catch (error) {
      showError(content, error);
    }
  }

  function route(path) {
    if (path === "/interests") return catalog("intents");
    if (path === "/interests/new") return create("intents");
    if (path === "/groups") return catalog("groups");
    if (path === "/groups/new") return create("groups");
    if (path === "/calendar") return calendar();
    if (path === "/map") return mapPage();
    const item = /^\/(interests|groups)\/([0-9a-f-]{36})$/i.exec(path);
    if (item)
      return item[1] === "interests"
        ? intentDetail(item[2])
        : groupDetail(item[2]);
    return null;
  }

  return { route, followButton };
}

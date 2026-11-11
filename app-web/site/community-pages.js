export function createCommunityPages(ui) {
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
    card,
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

  async function catalog(kind) {
    const intent = kind === "intents";
    const root = intent ? "/interests" : "/groups";
    const content = show(intent ? "想一起去" : "活动小组", "workspace-page");
    content.append(
      node(
        "p",
        intent
          ? "先征集时段和兴趣，有了正式活动再报名。"
          : "和熟悉的人，反复做喜欢的事。",
        "meta",
      ),
      actionLink(
        intent ? "发起意向征集" : "创建小组",
        root + "/new",
        "button primary",
      ),
    );
    try {
      const items = await request("/web/" + kind);
      list(
        content,
        items,
        (row, item) => {
          row.append(
            actionLink(item.title, root + "/" + item.id, "text-button"),
            node("p", item.description, "detail-copy"),
            node(
              "p",
              intent
                ? [
                    item.region_name,
                    item.event_id ? "已有正式活动" : "意向征集",
                  ].join(" · ")
                : item.member_count + " 名成员",
              "meta",
            ),
          );
        },
        intent ? "还没有征集。可以先写下你想找人一起做的事。" : "还没有小组。",
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
      if (intent) {
        try {
          const regions = await request("/regions");
          const field = node("label", "市／道");
          const select = node("select");
          select.name = "regionCode";
          select.required = true;
          select.add(new Option("选择地区", ""));
          for (const item of regions.filter((region) => region.level === 1))
            select.add(new Option(item.name_zh_cn, item.code));
          field.append(select);
          form.prepend(field);
        } catch (error) {
          showError(content, error);
          return;
        }
      }
      content.append(form);
      handleForm(form, content, async (values) => {
        const created = await request("/web/" + kind, {
          auth: true,
          data: values,
        });
        location.assign((intent ? "/interests/" : "/groups/") + created.id);
      });
    });
  }

  async function attachEvent(content, endpoint, label, activeOnly) {
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
    for (const item of own) select.add(new Option(item.title, item.id));
    field.append(select);
    const submit = node("button", label, "button primary");
    submit.type = "submit";
    form.append(field, submit);
    content.append(form);
    handleForm(form, content, async (values) => {
      await request(endpoint, { method: "PUT", auth: true, data: values });
      location.reload();
    });
  }

  async function intentDetail(id) {
    const content = show("意向征集", "guide-article");
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
        return;
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
                intentDetail(id);
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
                intentDetail(id);
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
        );
    } catch (error) {
      showError(content, error);
    }
  }

  async function groupDetail(id) {
    const content = show("活动小组", "workspace-page");
    try {
      const { item, events, members } = await request("/web/groups/" + id, {
        auth: true,
      });
      content.querySelector("h1").textContent = item.title;
      content.append(
        node("p", item.description, "detail-copy"),
        node("p", item.member_count + " 名成员", "meta"),
      );
      const owner = session()?.user.id === item.owner_id;
      if (!owner && !item.joined)
        content.append(
          node("p", "加入后，昵称会显示在公开小组成员名单。", "meta"),
        );
      if (!owner)
        content.append(
          button(
            item.joined ? "退出小组" : "加入小组",
            () =>
              requireLogin(async () => {
                try {
                  await request("/web/groups/" + id + "/membership", {
                    method: item.joined ? "DELETE" : "PUT",
                    auth: true,
                  });
                  groupDetail(id);
                } catch (error) {
                  showError(content, error);
                }
              }),
            "button primary",
          ),
        );
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
        (row, member) =>
          row.append(
            actionLink(member.nickname, "/people/" + member.id, "text-button"),
          ),
        "暂无成员。",
      );
      if (owner)
        await attachEvent(
          content,
          "/web/groups/" + id + "/events",
          "加入小组活动列表",
          false,
        );
    } catch (error) {
      showError(content, error);
    }
  }

  function followButton(id) {
    let following = false;
    const trigger = button("关注组织者", () =>
      requireLogin(async () => {
        trigger.disabled = true;
        try {
          const state = await request("/web/follows/" + id, {
            method: following ? "DELETE" : "PUT",
            auth: true,
          });
          update(state.following);
        } catch (error) {
          showError(trigger.closest("section"), error);
        } finally {
          trigger.disabled = false;
        }
      }),
    );
    function update(value) {
      following = value;
      trigger.textContent = following ? "取消关注" : "关注组织者";
      trigger.setAttribute("aria-pressed", String(following));
    }
    if (session())
      request("/web/follows/" + id, { auth: true })
        .then((state) => update(state.following))
        .catch(() => {});
    return trigger;
  }

  function following() {
    return requireLogin(async () => {
      const content = show("关注动态", "workspace-page");
      content.append(actionLink("发现活动小组", "/groups"));
      try {
        eventGrid(
          content,
          await request("/web/following", { auth: true }),
          "关注组织者或加入小组后，他们的新活动会显示在这里。",
        );
      } catch (error) {
        showError(content, error);
      }
    });
  }

  async function calendar() {
    const content = show("活动日历", "workspace-page");
    const params = new URLSearchParams(location.search);
    const current = new Intl.DateTimeFormat("sv-SE", {
      timeZone: "Asia/Seoul",
      year: "numeric",
      month: "2-digit",
    }).format();
    const selected = params.get("month");
    const month = /^20[0-9]{2}-(0[1-9]|1[0-2])$/.test(selected)
      ? selected
      : current;
    const [year, number] = month.split("-").map(Number);
    const adjacent = (offset) =>
      new Date(Date.UTC(year, number - 1 + offset, 1))
        .toISOString()
        .slice(0, 7);
    const controls = node("div", null, "section-nav");
    controls.append(
      actionLink("上个月", "/calendar?month=" + adjacent(-1)),
      node("strong", year + " 年 " + number + " 月"),
      actionLink("下个月", "/calendar?month=" + adjacent(1)),
    );
    content.append(controls, node("p", "以韩国时间显示。", "meta"));
    try {
      const from = new Date(month + "-01T00:00:00+09:00");
      const next = new Date(adjacent(1) + "-01T00:00:00+09:00");
      const query = new URLSearchParams({
        from: from.toISOString(),
        to: new Date(next.valueOf() - 1).toISOString(),
        sort: "recommended",
        limit: "60",
      });
      const dates = new Map();
      const dayKey = new Intl.DateTimeFormat("sv-SE", {
        timeZone: "Asia/Seoul",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      });
      const formatter = new Intl.DateTimeFormat("zh-CN", {
        timeZone: "Asia/Seoul",
        month: "long",
        day: "numeric",
        weekday: "long",
      });
      const monthGrid = node("div", null, "calendar-grid");
      const results = node("div");
      content.append(monthGrid, results);
      function renderMonth() {
        monthGrid.replaceChildren(
          ...["一", "二", "三", "四", "五", "六", "日"].map((day) =>
            node("strong", day, "calendar-label"),
          ),
        );
        const leading =
          (new Date(Date.UTC(year, number - 1, 1)).getUTCDay() + 6) % 7;
        for (let i = 0; i < leading; i++)
          monthGrid.append(node("span", null, "calendar-empty"));
        const days = new Date(Date.UTC(year, number, 0)).getUTCDate();
        for (let day = 1; day <= days; day++) {
          const key = month + "-" + String(day).padStart(2, "0");
          const count = dates.get(key)?.length ?? 0;
          const cell = count
            ? actionLink(
                String(day),
                "#calendar-" + key,
                "calendar-day has-events",
              )
            : node("span", day, "calendar-day");
          if (count) cell.append(node("small", count + " 场"));
          monthGrid.append(cell);
        }
      }
      async function load(cursor) {
        if (cursor) query.set("cursor", cursor);
        const page = await request("/activities?" + query);
        for (const event of page.items) {
          const date = dayKey.format(new Date(event.starts_at));
          if (!dates.has(date)) dates.set(date, []);
          dates.get(date).push(event);
        }
        renderMonth();
        results.replaceChildren();
        for (const [date, events] of dates) {
          const heading = node(
            "h2",
            formatter.format(new Date(events[0].starts_at)),
          );
          heading.id = "calendar-" + date;
          results.append(heading);
          list(
            results,
            events,
            (row, event) =>
              row.append(
                actionLink(event.title, eventLink(event.id), "text-button"),
                node("p", time(event.starts_at), "meta"),
              ),
            "",
          );
        }
        if (!dates.size)
          results.append(node("p", "本月暂无可报名活动。", "meta"));
        if (page.hasMore && page.nextCursor)
          results.append(
            button("加载更多", async (event) => {
              const trigger = event.currentTarget;
              trigger.disabled = true;
              try {
                await load(page.nextCursor);
              } catch (error) {
                showError(content, error);
              } finally {
                trigger.disabled = false;
              }
            }),
          );
      }
      await load();
    } catch (error) {
      showError(content, error);
    }
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
    if (path === "/following") return following();
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

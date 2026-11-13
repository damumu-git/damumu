export function createActivitySeries({ show, node, button, actionLink, request, requireLogin, handleForm, showError, session, cover, card, eventLink, uploadCover, uploadedImage }) {
  const link = (item) => "/series/" + encodeURIComponent(item.slug || item.id);
  const endpoint = (id) => "/events/" + encodeURIComponent(id);
  const slots = [["", "暂不登记"], ["saturday", "周六"], ["sunday", "周日"], ["either", "周六或周日均可"]];

  function form(content, html, save) {
    const element = node("form", null, "form");
    element.innerHTML = html + '<button type="submit" class="button primary">保存</button>';
    content.append(element);
    handleForm(element, content, save);
    return element;
  }
  async function regionOptions(select, placeholder) {
    const regions = await request("/regions");
    select.append(new Option(placeholder, ""));
    const names = new Map(regions.map((item) => [item.code, item.name_zh_cn]));
    for (const item of regions)
      select.append(new Option([names.get(item.parent_code), item.name_zh_cn].filter(Boolean).join(" / "), item.code));
  }
  function cards(content, items) {
    const grid = node("div", null, "series-grid");
    for (const item of items) {
      const entry = node("article", null, "activity-section series-card");
      const copy = node("div", null, "series-card-copy");
      if (item.region_name) copy.append(node("p", item.region_name, "meta"));
      copy.append(node("h2", item.title), node("p", item.description, "detail-copy"));
      entry.append(copy, actionLink("查看系列", link(item)));
      grid.append(entry);
    }
    content.append(items.length ? grid : node("p", "这个地区还没有活动系列。", "meta"));
  }
  async function index() {
    const content = show("活动系列", "workspace-page series-page");
    const toolbar = node("div", null, "series-toolbar");
    const actions = node("div", null, "section-nav");
    actions.append(actionLink("搭慕周末", "/series/damu-weekend", "button primary"),
      actionLink("创建活动系列", "/series/new"), actionLink("组织者招募与场地合作", "/series/participate"));
    const label = node("label", "按地区浏览", "series-region");
    const select = node("select");
    label.append(select);
    toolbar.append(actions, label);
    content.append(toolbar);
    const region = new URLSearchParams(location.search).get("region") || "";
    if (region) actions.append(actionLink("查看地区专题", "/places/" + encodeURIComponent(region)));
    try {
      const [, rows] = await Promise.all([regionOptions(select, "全部地区"),
        request("/series" + (region ? "?region=" + encodeURIComponent(region) : ""))]);
      select.value = region;
      select.onchange = () => location.assign("/series" + (select.value ? "?region=" + encodeURIComponent(select.value) : ""));
      cards(content, rows);
    } catch (error) { showError(content, error); }
  }
  function create(proposal) {
    requireLogin(async () => {
      const content = show(proposal ? "组织者招募与场地合作" : "创建活动系列", "editor-page series-page");
      const kind = proposal
        ? '<label>合作类型<select name="kind"><option value="organizer">成为组织者</option><option value="venue">场地合作</option></select></label>'
        : '<label>系列名称<input name="title" required minlength="2" maxlength="100"></label>';
      const editor = form(content, kind + '<label>地区<select name="regionCode" required></select></label><label>介绍<textarea name="description" required minlength="2" maxlength="1000"></textarea></label>',
        async ({ title, description, regionCode, kind }) => {
          const item = await request(proposal ? "/series/proposals" : "/series", {
            auth: true, data: proposal ? { kind, regionCode, body: description } : { title, description, regionCode },
          });
          if (proposal) editor.replaceWith(node("p", "申请已提交。", "notice"));
          else location.assign(link(item));
        });
      try { await regionOptions(editor.elements.regionCode, "请选择地区"); }
      catch (error) { showError(content, error); }
    });
  }
  function eventsSection(content, rows, ended) {
    content.append(node("h2", ended ? "往期活动" : "即将举行"));
    const grid = node("div", null, "cards");
    for (const item of rows.filter((item) => item.ended === ended)) {
      const entry = card(item);
      if (item.has_recap) entry.append(actionLink("查看活动回顾", eventLink(item.id) + "/recap"));
      grid.append(entry);
    }
    content.append(grid.childElementCount ? grid : node("p",
      ended ? "暂无往期活动。" : "下一场暂未确定，欢迎登记方便的时间。", "meta"));
  }
  async function detail(key) {
    const content = show("活动系列", "workspace-page series-page");
    try {
      const { item, events } = await request("/series/" + encodeURIComponent(key), { auth: true });
      if (!content.isConnected) return;
      content.querySelector("h1").textContent = item.title;
      document.title = item.title + " · 搭慕";
      const intro = node("section", null, "activity-section series-intro");
      const summary = node("div", null, "series-intro-summary");
      if (item.region_name) summary.append(node("p", item.region_name, "meta"));
      summary.append(node("p", item.description, "detail-copy"));
      const actions = node("div", null, "section-nav");
      if (item.guide_slug) actions.append(actionLink(item.guide_title, "/guides/" + item.guide_slug));
      if (item.owner_id) actions.append(actionLink("组织者主页", "/people/" + item.owner_id));
      if (item.can_manage) actions.append(actionLink("添加已发布活动", link(item) + "/manage", "button primary"),
        actionLink("发布系列活动", "/activities/new?series=" + item.id));
      if (actions.children.length) summary.append(actions);
      const participation = node("div", null, "series-intro-participation");
      intro.append(summary, participation);
      const interestSummary = (row) => "已有 " + row.interest_count + " 人登记时段" +
        (row.interest_count ? " · 周六 " + row.saturday_count + " · 周日 " + row.sunday_count + " · 均可 " + row.either_count : "");
      const count = node("p", interestSummary(item), "meta");
      if (session()) {
        const editor = form(participation, '<label>方便的周末时段<select name="interestSlot"></select></label><label class="series-subscribe"><input type="checkbox" name="subscribed"> 订阅新活动的站内通知</label>', async (values) => {
          await request("/series/" + item.id + "/membership", { auth: true, method: "PUT",
            data: { subscribed: Boolean(values.subscribed), interestSlot: values.interestSlot || null } });
          const updated = await request("/series/" + encodeURIComponent(key), { auth: true });
          count.textContent = interestSummary(updated.item);
          editor.querySelector(".notice")?.remove();
          editor.append(node("p", "订阅与意向已保存。", "notice"));
        });
        for (const [value, label] of slots) editor.elements.interestSlot.append(new Option(label, value));
        editor.elements.interestSlot.value = item.interest_slot || "";
        editor.elements.subscribed.checked = item.subscribed;
      } else participation.append(button("登录后订阅或登记意向", () => requireLogin(() => {})));
      participation.append(count);
      content.append(intro);
      eventsSection(content, events, false);
      eventsSection(content, events, true);
    } catch (error) { showError(content, error); }
  }
  function manage(key) {
    requireLogin(async () => {
      const content = show("添加活动到系列", "editor-page series-page");
      try {
        const [{ item, events }, mine] = await Promise.all([
          request("/series/" + encodeURIComponent(key), { auth: true }),
          request("/me/activities", { auth: true }),
        ]);
        if (!item.can_manage) throw new Error("仅系列管理者可以添加活动。");
        const linked = new Set(events.map((event) => event.id));
        const choices = mine.filter((event) => event.organizer_user_id === session().user.id &&
          ["published", "full", "completed"].includes(event.event_status) && !linked.has(event.id));
        content.append(actionLink("返回系列", link(item)));
        if (!choices.length) {
          content.append(node("p", "暂无可添加活动。", "meta"), actionLink("发布活动", "/activities/new"));
          return;
        }
        const editor = form(content, '<label>已发布活动<select name="eventId" required></select></label>', async ({ eventId }) => {
          await request("/series/" + item.id + "/events/" + eventId, { auth: true, method: "PUT" });
          location.assign(link(item));
        });
        for (const event of choices) editor.elements.eventId.append(new Option(event.title, event.id));
      } catch (error) { showError(content, error); }
    });
  }
  async function recap(id, edit = false) {
    const content = show(edit ? "编辑活动回顾" : "活动回顾", "editor-page series-page");
    try {
      const item = await request(endpoint(id) + "/story");
      const actions = node("div", null, "section-nav");
      actions.append(actionLink("返回活动", eventLink(id)));
      if (item.series_id) actions.append(actionLink("查看系列", "/series/" + (item.series_slug || item.series_id)));
      if (item.next_event_id) actions.append(actionLink("查看下一场", eventLink(item.next_event_id), "button primary"));
      content.append(node("h2", item.title), actions);
      const owns = item.organizer_user_id === session()?.user.id;
      if (edit) {
        if (!owns || !item.ended) throw new Error("仅组织者可编辑已结束的公开活动回顾。");
        const editor = form(content, '<label>回顾正文<textarea name="body" required minlength="2" maxlength="2000"></textarea></label><label>回顾照片（最多三张）<input name="photos" type="file" accept="image/*" multiple></label><label class="series-subscribe"><input type="checkbox" name="clearPhotos"> 移除现有照片</label><label class="series-subscribe"><input type="checkbox" name="photosApproved"> 已获得照片公开使用许可</label><label class="series-subscribe"><input type="checkbox" name="showCover"> 已获得许可，使用已有活动封面</label>', async ({ body, showCover, clearPhotos, photosApproved }) => {
          const files = [...editor.elements.photos.files];
          if (files.length > 3 || (files.length && !photosApproved)) throw new Error("最多选择三张照片，并确认获得公开使用许可。");
          const uploaded = [];
          try {
            for (const file of files) uploaded.push(await uploadCover(file));
            const photoIds = files.length || clearPhotos ? uploaded : (item.recap_photos || []).map((photo) => photo.id);
            await request(endpoint(id) + "/recap", { auth: true, method: "PUT",
              data: { body, showCover: Boolean(showCover), photoIds, photosApproved: Boolean(photosApproved) || !files.length } });
          } catch (error) {
            for (const photo of uploaded) await request("/events/covers/" + photo, { auth: true, method: "DELETE" }).catch(() => {});
            throw error;
          }
          location.assign(eventLink(id) + "/recap");
        });
        editor.elements.body.value = item.recap || "";
        editor.elements.showCover.checked = item.recap_show_cover;
      } else {
        if (item.recap_show_cover && item.recap) content.append(cover(item, "detail-cover"));
        content.append(node("p", item.recap || "组织者暂未发布回顾。", "detail-copy"));
        const photos = node("div", null, "series-grid");
        for (const photo of item.recap_photos || []) {
          const url = uploadedImage(photo.image_url);
          if (!url) continue;
          const image = node("img", null, "detail-cover");
          image.src = url;
          image.alt = "活动回顾照片";
          photos.append(image);
        }
        if (photos.childElementCount) content.append(photos);
        if (owns && item.ended) content.append(actionLink("编辑回顾", eventLink(id) + "/recap/edit"));
      }
    } catch (error) { showError(content, error); }
  }
  async function share(id, title) {
    const url = location.origin + eventLink(id) + "/share";
    try {
      if (navigator.share) return await navigator.share({ title, url });
      await navigator.clipboard.writeText(url);
      window.alert("活动链接已复制。");
    } catch (error) {
      if (error.name !== "AbortError") window.prompt("复制活动链接", url);
    }
  }
  async function activityLinks(id, content) {
    try {
      const item = await request(endpoint(id) + "/story");
      if (!content.isConnected) return;
      const actions = node("div", null, "section-nav");
      actions.append(button("分享活动", () => share(id, item.title)));
      if (item.series_id) actions.append(actionLink(item.series_title, "/series/" + (item.series_slug || item.series_id)));
      if (item.recap) actions.append(actionLink("活动回顾", eventLink(id) + "/recap"));
      if (item.ended && item.organizer_user_id === session()?.user.id)
        actions.append(actionLink("写活动回顾", eventLink(id) + "/recap/edit"),
          actionLink("复办活动", "/activities/new?copy=" + id + (item.series_id ? "&series=" + item.series_id : "")));
      content.append(actions);
    } catch {
      // Private and cancelled activities have no public story.
    }
  }
  async function organizer(id, content) {
    try {
      const items = await request("/series?ownerId=" + encodeURIComponent(id));
      if (!content.isConnected || !items.length) return;
      content.append(node("h2", "组织者的活动系列"));
      cards(content, items);
    } catch {
      // Keep the public profile usable if the series directory is unavailable.
    }
  }
  return { index, create, detail, manage, recap, activityLinks, organizer };
}

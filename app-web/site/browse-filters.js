import { datePresets, dateRange, dayInSeoul, validDay } from "/seoul-dates.js";

import { renderCalendar } from "/date-picker.js";

export function createBrowseFilters({ node, button, changed }) {
  const filters = document.querySelector("#filters");
  const dateLabel = new Intl.DateTimeFormat("zh-CN", { month: "long", day: "numeric", timeZone: "UTC" });
  const dateButtons = [];
  const syncSelects = [];
  const freshRegion = () => ({ city: "", district: "", ward: "" });
  let selected = freshRegion();
  let draft;
  let catalog = [];
  let preset = "";
  let presetRange;
  let day = "";
  let dateMonth;
  let dateDraft;

  function modal(id, title, trigger) {
    const dialog = node("dialog", null, "browse-dialog");
    dialog.id = id;
    dialog.setAttribute("aria-labelledby", id + "-title");
    const header = node("header", null, "browse-dialog-header");
    const heading = node("h3", title);
    heading.id = id + "-title";
    const close = button("×", () => dialog.close(), "browse-close");
    close.setAttribute("aria-label", "关闭" + title);
    header.append(heading, close);
    const body = node("div", null, "browse-dialog-body");
    const footer = node("div", null, "browse-dialog-actions");
    dialog.append(header, body, footer);
    dialog.addEventListener("close", () => trigger.focus({ preventScroll: true }));
    trigger.setAttribute("aria-haspopup", "dialog");
    trigger.setAttribute("aria-controls", id);
    filters.append(dialog);
    return { dialog, body, footer };
  }

  const locationTrigger = button("选择地区", () => {
    draft = { ...selected };
    renderRegions();
    locationPicker.dialog.showModal();
  }, "filter-trigger region-trigger");
  locationTrigger.disabled = true;
  document.querySelector("#region-filter").append(locationTrigger);
  const locationPicker = modal("region-picker", "选择地区", locationTrigger);
  locationPicker.footer.append(
    button("清除地区", () => applyRegion(freshRegion())),
    button("应用地区", () => applyRegion(draft), "button primary"),
  );

  function applyRegion(value) {
    selected = value;
    renderValues();
    locationPicker.dialog.close();
    changed();
  }

  function chooseRegion(key, code) {
    if (draft[key] === code) return;
    draft[key] = code;
    if (key === "city") draft.district = "";
    if (key !== "ward") draft.ward = "";
    renderRegions();
    const sameChoice = Array.from(locationPicker.body.querySelectorAll("[data-region-key]"))
      .find((element) => element.dataset.regionKey === key && element.dataset.code === code);
    sameChoice?.focus();
  }

  function renderRegions() {
    const cities = catalog.filter((item) => item.level === 1);
    const popular = ["首尔", "釜山", "仁川", "京畿道"]
      .map((name) => cities.find((entry) => entry.name_zh_cn.startsWith(name)))
      .filter(Boolean);
    const quick = node("div", null, "popular-regions");
    if (popular.length) quick.append(node("span", "热门地区", "meta"));
    for (const item of popular) {
      const option = button(item.name_zh_cn, () => chooseRegion("city", item.code), "filter-pill");
      option.setAttribute("aria-pressed", String(draft.city === item.code));
      quick.append(option);
    }
    const columns = node("div", null, "region-columns");
    const districts = catalog.filter((item) => item.level === 2 && item.parent_code === draft.city);
    const wards = catalog.filter((item) => item.level === 3 && item.parent_code === draft.district);
    for (const [key, title, options, all, hint] of [
      ["city", "市／道", cities, "全部地区", "暂时无法获取地区"],
      ["district", "市／郡／区", districts, "整个市／道", "先选择市／道"],
      ["ward", "下辖区", wards, "整个市／郡／区", "该地区暂无下辖区可选"],
    ]) {
      if (key === "ward" && !draft.district) continue;
      const column = node("section", null, "region-column");
      column.append(node("h4", title));
      const list = node("div", null, "region-options");
      if (!options.length) list.append(node("p", hint, "meta"));
      for (const option of options.length ? [{ code: "", name_zh_cn: all }, ...options] : []) {
        const item = button(option.name_zh_cn, () => chooseRegion(key, option.code), "filter-option");
        item.setAttribute("aria-pressed", String(draft[key] === option.code));
        item.dataset.regionKey = key;
        item.dataset.code = option.code;
        list.append(item);
      }
      column.append(list);
      columns.append(column);
    }
    locationPicker.body.replaceChildren(quick, columns);
  }

  const dateFilters = document.querySelector("#date-filters");
  for (const [value, title] of Object.entries(datePresets)) {
    const control = button(title, () => selectDate(preset === value ? "" : value), "filter-pill");
    dateButtons.push([value, control]);
    dateFilters.append(control);
  }
  const calendarTrigger = button("选日期", () => {
    dateDraft = day;
    dateMonth = (day || presetRange?.[0] || dayInSeoul()).slice(0, 7);
    renderDate();
    datePicker.dialog.showModal();
  }, "filter-trigger");
  dateFilters.append(calendarTrigger);
  const datePicker = modal("date-picker", "选择日期", calendarTrigger);
  datePicker.dialog.classList.add("date-dialog");
  const dateApply = button("应用日期", () => {
    datePicker.dialog.close();
    selectDate("", dateDraft);
  }, "button primary");
  datePicker.footer.append(
    button("清除日期", () => { datePicker.dialog.close(); selectDate(""); }),
    dateApply,
  );

  function selectDate(value, exact = "") {
    preset = value;
    presetRange = dateRange(value);
    day = exact;
    renderValues();
    changed();
  }

  function renderDate(focus) {
    renderCalendar(datePicker.body, {
      node, button, month: dateMonth, selected: dateDraft, focus,
      navigate(value, target) { dateMonth = value; renderDate(target); },
      choose(value) { dateDraft = value; renderDate(value); },
    });
    dateApply.disabled = !dateDraft;
  }

  for (const select of filters.querySelectorAll("select")) {
    const details = node("details", null, "filter-select");
    const summary = node("summary", null, "filter-trigger");
    const value = node("span");
    summary.append(node("small", select.dataset.label), value);
    const menu = node("div", null, "filter-menu");
    const options = [...select.options].map((option) => {
      const item = button(option.text, () => {
        select.value = option.value;
        select.dispatchEvent(new Event("change"));
        details.open = false;
        summary.focus();
      }, "filter-option");
      menu.append(item);
      return [option, item];
    });
    function sync() {
      value.textContent = select.selectedOptions[0]?.text ?? "";
      for (const [option, item] of options) item.setAttribute("aria-pressed", String(option.selected));
    }
    details.append(summary, menu);
    select.before(details);
    details.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && details.open) { details.open = false; summary.focus(); }
    });
    document.addEventListener("pointerdown", (event) => {
      if (!details.contains(event.target)) details.open = false;
    });
    select.addEventListener("change", () => { sync(); changed(); });
    syncSelects.push(sync);
  }

  function renderValues() {
    const names = Object.values(selected).map((code) => catalog.find((item) => item.code === code)?.name_zh_cn);
    locationTrigger.textContent = names.filter(Boolean).join(" · ") || "全部地区";
    locationTrigger.classList.toggle("is-selected", Boolean(selected.city));
    calendarTrigger.textContent = day ? dateLabel.format(new Date(day + "T00:00:00Z")) : "选日期";
    calendarTrigger.classList.toggle("is-selected", Boolean(day));
    for (const [value, control] of dateButtons) control.setAttribute("aria-pressed", String(preset === value));
  }

  return {
    restore(params, regions) {
      catalog = regions;
      selected = freshRegion();
      for (const [index, key] of ["city", "district", "ward"].entries()) {
        const entry = catalog.find((item) => item.code === params.get(key) && item.level === index + 1);
        if (entry && (!index || entry.parent_code === (index === 1 ? selected.city : selected.district)))
          selected[key] = entry.code;
      }
      const exact = params.get("day");
      day = validDay(exact) ? exact : "";
      const when = params.get("when");
      preset = !day && Object.hasOwn(datePresets, when) ? when : "";
      presetRange = dateRange(preset);
      locationTrigger.disabled = !catalog.length;
      for (const sync of syncSelects) sync();
      renderValues();
    },
    values: () => ({ ...selected, day, when: preset }),
    range: () => day ? [day, day] : presetRange,
  };
}

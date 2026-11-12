import { dayInSeoul, shiftDay, validDay } from "/seoul-dates.js";

export function renderCalendar(container, { node, button, month, selected, focus, navigate, choose }) {
  const [year, number] = month.split("-").map(Number);
  const toolbar = node("div", null, "date-picker-toolbar");
  for (const [offset, label, symbol] of [[-1, "上个月", "‹"], [1, "下个月", "›"]]) {
    const adjacent = new Date(Date.UTC(year, number - 1 + offset, 1)).toISOString().slice(0, 7);
    const control = button(symbol, () => navigate(adjacent, label), "date-arrow");
    control.setAttribute("aria-label", label);
    if (offset > 0) toolbar.append(node("strong", `${year} 年 ${number} 月`));
    toolbar.append(control);
  }
  const grid = node("div", null, "date-picker-grid");
  const today = dayInSeoul();
  const tabbable = [focus, selected, today].find((value) => value?.startsWith(month + "-")) ?? month + "-01";
  grid.append(...["一", "二", "三", "四", "五", "六", "日"].map((label) => node("span", label, "meta")));
  const leading = (new Date(Date.UTC(year, number - 1, 1)).getUTCDay() + 6) % 7;
  for (let gap = 0; gap < leading; gap++) grid.append(node("span"));
  for (let day = 1; day <= new Date(Date.UTC(year, number, 0)).getUTCDate(); day++) {
    const value = month + "-" + String(day).padStart(2, "0");
    const choice = button(day, () => choose(value), "date-choice");
    choice.tabIndex = value === tabbable ? 0 : -1;
    choice.setAttribute("aria-label", value);
    choice.setAttribute("aria-pressed", String(value === selected));
    if (value === today) choice.setAttribute("aria-current", "date");
    grid.append(choice);
  }
  grid.addEventListener("keydown", (event) => {
    const offset = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[event.key];
    const current = event.target.getAttribute("aria-label");
    if (!offset || !validDay(current)) return;
    event.preventDefault();
    const next = shiftDay(current, offset);
    navigate(next.slice(0, 7), next);
  });
  container.replaceChildren(toolbar, grid);
  if (focus) [...container.querySelectorAll("button")]
    .find((item) => item.getAttribute("aria-label") === focus)?.focus();
}

export function setupSchedulePicker(form, parent, { node, button }) {
  const dialog = node("dialog", null, "browse-dialog date-dialog schedule-dialog");
  dialog.id = "schedule-picker";
  dialog.setAttribute("aria-labelledby", "schedule-picker-title");
  const title = node("h3");
  title.id = "schedule-picker-title";
  const header = node("header", null, "browse-dialog-header");
  const close = button("×", () => dialog.close(), "browse-close");
  close.setAttribute("aria-label", "关闭时间选择");
  header.append(title, close);
  const body = node("div", null, "browse-dialog-body");
  const calendar = node("div");
  const time = node("div", null, "schedule-time");
  const hour = numberInput("小时", 23);
  const minute = numberInput("分钟", 59);
  const selectedDate = node("p", null, "meta schedule-selected-date");
  selectedDate.setAttribute("aria-live", "polite");
  body.append(calendar, selectedDate, time);
  const footer = node("div", null, "browse-dialog-actions");
  const apply = button("应用时间", applySchedule, "button primary");
  footer.append(button("取消", () => dialog.close()), apply);
  dialog.append(header, body, footer);
  parent.append(dialog);

  let trigger;
  let selected;
  let month;
  for (const field of form.querySelectorAll("[data-schedule]")) {
    field.setAttribute("aria-haspopup", "dialog");
    field.setAttribute("aria-controls", dialog.id);
    field.addEventListener("click", () => {
      trigger = field;
      const value = form.elements[field.dataset.schedule].value;
      const [day, clock = ""] = value.split("T");
      const [hh, mm] = clock.split(":");
      selected = day;
      month = (day || form.elements.startsAt.value.slice(0, 10) || dayInSeoul()).slice(0, 7);
      hour.value = hh ?? "";
      minute.value = mm ?? "00";
      title.textContent = field.dataset.schedule === "startsAt" ? "开始日期与时间" : "结束日期与时间";
      render();
      dialog.showModal();
    });
  }
  dialog.addEventListener("close", () => trigger?.focus({ preventScroll: true }));

  function numberInput(label, max) {
    const wrapper = node("label", label);
    const input = node("input");
    input.type = "number";
    input.inputMode = "numeric";
    input.min = "0";
    input.max = String(max);
    input.step = "1";
    input.placeholder = "00";
    input.required = true;
    input.addEventListener("input", updateApply);
    wrapper.append(input);
    time.append(wrapper);
    return input;
  }

  function updateApply() {
    apply.disabled = !validDay(selected) || !hour.validity.valid || !minute.validity.valid;
  }

  function render(focus) {
    renderCalendar(calendar, {
      node, button, month, selected, focus,
      navigate(value, target) { month = value; render(target); },
      choose(value) { selected = value; render(value); },
    });
    selectedDate.textContent = selected ? `已选 ${selected} · 韩国时间` : "请选择日期 · 韩国时间";
    updateApply();
  }

  function applySchedule() {
    const clock = [hour, minute].map((part) => String(Number(part.value)).padStart(2, "0")).join(":");
    form.elements[trigger.dataset.schedule].value = `${selected}T${clock}`;
    trigger.querySelector(".schedule-value").textContent = `${selected}  ${clock}`;
    trigger.classList.add("has-value");
    dialog.close();
  }
}

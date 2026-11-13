export function installSelectMenus() {
  if (!HTMLElement.prototype.showPopover) return;
  const menus = new WeakMap();
  let positionOpenMenu;
  let nextId = 0;
  window.addEventListener("resize", () => positionOpenMenu?.());
  window.addEventListener("scroll", () => positionOpenMenu?.(), true);

  function enhance(select) {
    if (select.hidden || select.multiple || select.size > 1 || menus.has(select)) return;
    const label = select.labels[0];
    if (!label) return;
    const field = document.createElement("span");
    field.className = "select-menu";
    const labelText = document.createElement("span");
    labelText.id = "select-label-" + ++nextId;
    labelText.className = "select-menu-label";
    labelText.textContent = [...label.childNodes].filter((child) => child !== select)
      .map((child) => child.textContent).join(" ").trim();
    if (!labelText.textContent) labelText.textContent = label.firstChild?.textContent?.trim() || "请选择";
    labelText.classList.add("select-menu-sr");
    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "select-menu-trigger";
    trigger.id = "select-trigger-" + nextId;
    trigger.setAttribute("aria-labelledby", labelText.id + " " + trigger.id);
    trigger.setAttribute("aria-expanded", "false");
    const popup = document.createElement("div");
    popup.className = "select-menu-popup";
    popup.id = "select-popup-" + nextId;
    popup.popover = "auto";
    trigger.setAttribute("aria-controls", popup.id);
    const choices = document.createElement("div");
    choices.className = "select-menu-options";
    const search = document.createElement("input");
    search.type = "search";
    search.className = "select-menu-search";
    search.placeholder = "搜索选项";
    search.setAttribute("aria-label", "搜索" + labelText.textContent);
    popup.append(search, choices);
    field.append(labelText, trigger, popup);
    select.after(field);
    select.classList.add("select-menu-native");
    select.tabIndex = -1;
    select.setAttribute("aria-hidden", "true");

    function sync() {
      trigger.textContent = select.selectedOptions[0]?.label || "请选择";
      trigger.disabled = select.disabled;
      if (select.disabled && popup.matches(":popover-open")) popup.hidePopover();
    }
    menus.set(select, sync);

    function render() {
      const query = search.value.trim().toLowerCase();
      const options = [...select.options].filter((item) => !item.hidden && item.label.toLowerCase().includes(query));
      choices.replaceChildren();
      for (const option of options) {
        const choice = document.createElement("button");
        choice.type = "button";
        choice.className = "select-menu-option";
        choice.textContent = option.label;
        choice.disabled = option.disabled || (option.parentElement.tagName === "OPTGROUP" && option.parentElement.disabled);
        choice.setAttribute("aria-pressed", String(option.selected));
        choice.addEventListener("click", () => {
          if (select.selectedIndex !== option.index) {
            select.selectedIndex = option.index;
            select.dispatchEvent(new Event("input", { bubbles: true }));
            select.dispatchEvent(new Event("change", { bubbles: true }));
          }
          if (popup.matches(":popover-open")) popup.hidePopover();
          trigger.focus();
        });
        choices.append(choice);
      }
      if (!options.length) {
        const empty = document.createElement("p");
        empty.textContent = "没有匹配的选项";
        choices.append(empty);
      }
    }

    function position() {
      const bounds = trigger.getBoundingClientRect();
      const below = innerHeight - bounds.bottom - 12;
      const above = bounds.top - 12;
      const upwards = below < 235 && above > below;
      popup.style.width = Math.min(Math.max(208, bounds.width), innerWidth - 24) + "px";
      popup.style.left = Math.max(12, Math.min(bounds.left, innerWidth - popup.offsetWidth - 12)) + "px";
      popup.style.maxHeight = Math.max(80, Math.min(330, upwards ? above : below)) + "px";
      popup.style.top = upwards ? "auto" : bounds.bottom + 6 + "px";
      popup.style.bottom = upwards ? innerHeight - bounds.top + 6 + "px" : "auto";
    }

    trigger.addEventListener("click", () => {
      if (popup.matches(":popover-open")) return popup.hidePopover();
      search.hidden = select.options.length <= 9;
      search.value = "";
      render();
      popup.showPopover();
      position();
      const target = search.hidden
        ? choices.querySelector('[aria-pressed="true"]:not(:disabled)') ?? choices.querySelector("button:not(:disabled)")
        : search;
      target?.focus({ preventScroll: true });
    });
    popup.addEventListener("toggle", () => {
      const open = popup.matches(":popover-open");
      trigger.setAttribute("aria-expanded", String(open));
      if (open) positionOpenMenu = position;
      else if (positionOpenMenu === position) positionOpenMenu = undefined;
    });
    search.addEventListener("input", render);
    search.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        choices.querySelector("button:not(:disabled)")?.click();
      }
    });
    popup.addEventListener("keydown", (event) => {
      if (!["ArrowDown", "ArrowUp", "Home", "End", "Escape"].includes(event.key)) return;
      if (event.key === "Escape") {
        event.preventDefault();
        popup.hidePopover();
        trigger.focus();
        return;
      }
      if (event.target === search && ["Home", "End"].includes(event.key)) return;
      const buttons = [...choices.querySelectorAll("button:not(:disabled)")];
      if (!buttons.length) return;
      event.preventDefault();
      const index = buttons.indexOf(document.activeElement);
      const next = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1
        : event.key === "ArrowUp" ? (index <= 0 ? buttons.length - 1 : index - 1)
        : (index + 1) % buttons.length;
      buttons[next].focus();
    });
    field.addEventListener("focusout", (event) => {
      if (event.relatedTarget && !field.contains(event.relatedTarget) && popup.matches(":popover-open")) popup.hidePopover();
    });
    select.addEventListener("change", sync);
    select.form?.addEventListener("reset", () => queueMicrotask(sync));
    select.addEventListener("focus", () => trigger.focus());
    sync();
  }

  function scan(root) {
    if (!(root instanceof Element)) return;
    if (root instanceof HTMLSelectElement) enhance(root);
    for (const select of root.querySelectorAll("select:not([hidden])")) enhance(select);
  }
  const observer = new MutationObserver((changes) => {
    for (const change of changes) {
      const select = change.target.closest?.("select");
      if (select) menus.get(select)?.();
      for (const added of change.addedNodes) scan(added);
    }
  });
  observer.observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ["disabled", "selected"] });
  scan(document.body);
}

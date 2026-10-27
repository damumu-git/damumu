/* Classic local scripts intentionally work under file:// without a server or CDN. */
window.Preview = (() => {
  const esc = (value) =>
    String(value ?? "").replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    );
  const button = (label, action, cls = "") =>
    `<button type="button" class="${cls}" data-action="${esc(action)}">${label}</button>`;
  const link = (label, route, cls = "") =>
    `<button type="button" class="${cls}" data-route="${esc(route)}">${label}</button>`;
  const badge = (label, tone = "") =>
    `<span class="badge ${tone}">${esc(label)}</span>`;
  const field = (label, value = "", type = "text", extra = "") =>
    `<label class="field">${esc(label)}<input type="${type}" value="${esc(value)}" ${extra}></label>`;
  const area = (label, value = "") =>
    `<label class="field">${esc(label)}<textarea>${esc(value)}</textarea></label>`;
  const select = (label, options) =>
    `<label class="field">${esc(label)}<select>${options.map((x) => `<option>${esc(x)}</option>`).join("")}</select></label>`;
  const check = (label, checked = false, disabled = false) =>
    `<label class="check"><input type="checkbox" ${checked ? "checked" : ""} ${disabled ? "disabled" : ""}>${esc(label)}</label>`;
  const toggle = (label, checked = true, disabled = false) =>
    `<label class="switch"><input type="checkbox" aria-label="${esc(label)}" ${checked ? "checked" : ""} ${disabled ? "disabled" : ""}><span>${esc(label)}</span></label>`;
  const avatar = (face = "🐻", big = false) =>
    `<span class="avatar ${big ? "big" : ""}">${esc(face)}</span>`;
  const note = (text) => `<div class="note">${text}</div>`;
  const panel = (title, content, cls = "") =>
    `<section class="panel ${cls}">${title ? `<div class="section-title"><h3>${title}</h3></div>` : ""}${content}</section>`;
  const menu = (title, sub, route) =>
    `<button type="button" class="menu-item" data-route="${esc(route)}"><span>${title}${sub ? `<small>${sub}</small>` : ""}</span><span>›</span></button>`;
  const scene = (kind = 0) => {
    const palettes = [
      ["#aec6b3", "#e0b86f", "#e9dfba", "#46786d"],
      ["#c9b99e", "#f2d7a6", "#ede6d5", "#8a7054"],
      ["#b7cbd0", "#edc8a2", "#dce7e2", "#5d8490"],
    ];
    const [sky, sun, ground, hill] = palettes[kind % 3];
    return `<div class="scene"><svg viewBox="0 0 600 300" role="img" aria-label="${["汉江公园日落插画", "温暖咖啡馆插画", "户外山景插画"][kind % 3]}" preserveAspectRatio="xMidYMid slice"><rect width="600" height="300" fill="${sky}"/><circle cx="445" cy="95" r="48" fill="${sun}"/><path d="M0 195 Q130 80 290 190 T600 150 V300 H0" fill="${hill}"/><path d="M0 238 Q170 183 320 245 T600 213 V300 H0" fill="${ground}"/><path d="M0 265 Q150 215 340 265 T600 246" fill="none" stroke="white" stroke-opacity=".45" stroke-width="5"/><path d="M70 220v-95m-28 25 28-40 29 40m-47 24 18-29 23 29" stroke="#36594a" stroke-width="9" fill="none" stroke-linecap="round"/><rect x="232" y="222" width="83" height="35" rx="5" fill="#c07656" transform="rotate(-8 232 222)"/><circle cx="257" cy="198" r="12" fill="#324b40"/><path d="m252 214-8 24m15-22 15 18" stroke="#324b40" stroke-width="10" stroke-linecap="round"/></svg><span class="scene-caption">${["HANGANG · SLOW WEEKEND", "COFFEE & GOOD COMPANY", "A LITTLE OUTSIDE"][kind % 3]}</span></div>`;
  };
  const table = (heads, rows) =>
    `<div class="table-wrap"><table><thead><tr>${heads.map((h) => `<th>${h}</th>`).join("")}</tr></thead><tbody>${rows.map((row) => `<tr>${row.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody></table></div><div class="table-foot"><span>示例数据 · ${rows.length} 条</span><span>第 1 页</span></div>`;
  let timer;
  function toast(message = "预览操作完成，仅修改当前演示，不会调用 API。") {
    document.querySelector(".toast")?.remove();
    clearTimeout(timer);
    const el = document.createElement("div");
    el.className = "toast";
    el.role = "status";
    el.textContent = message;
    document.body.append(el);
    timer = setTimeout(() => el.remove(), 3200);
  }
  function modal(title, content, actionLabel = "确认", onConfirm) {
    document.querySelector(".preview-modal")?.remove();
    const dialog = document.createElement("dialog");
    dialog.className = "preview-modal";
    dialog.innerHTML = `<div class="modal-body"><header><h2>${esc(title)}</h2><button type="button" aria-label="关闭">×</button></header><form>${content}<div class="actions"><button type="button" data-cancel>取消</button><button class="primary" type="submit">${esc(actionLabel)}</button></div></form></div>`;
    dialog.querySelector("header button").onclick = () => dialog.close();
    dialog.querySelector("[data-cancel]").onclick = () => dialog.close();
    dialog.querySelector("form").onsubmit = (e) => {
      e.preventDefault();
      if (onConfirm) onConfirm(dialog);
      else toast();
      dialog.close();
    };
    dialog.addEventListener("click", (e) => {
      if (e.target === dialog) dialog.close();
    });
    document.body.append(dialog);
    dialog.showModal();
  }
  function boot({ kind, routes, render, actions = {} }) {
    const storageKey = `damumu-preview-${kind}-light-blue-v2`;
    const defaults = {
      primary: "#8fc8ed",
      bg: "#f3f8fc",
      radius: 18,
      font: 14,
      gap: 18,
      width: 390,
    };
    let prefs = { ...defaults };
    try {
      prefs = {
        ...prefs,
        ...JSON.parse(localStorage.getItem(storageKey) || "{}"),
      };
    } catch {
      /* file storage may be disabled */
    }
    const app = document.getElementById("preview");
    app.innerHTML = `<header class="toolbar"><strong>搭慕 / ${kind === "app" ? "APP" : "ADMIN"} 设计预览</strong><div class="row wrap"><a href="../${kind === "app" ? "admin" : "app"}/index.html">切换到 ${kind === "app" ? "Admin" : "App"} ↗</a><button id="tune">主题微调</button><button id="reset-demo">重置演示</button></div></header><div class="preview-layout"><aside class="catalog"><h2>页面目录 <small>${routes.length}</small></h2><input id="catalog-search" aria-label="搜索预览页面" placeholder="搜索页面…"><nav id="catalog-nav"></nav><footer>离线设计稿 · 示例数据<br>无 API 请求，不写入真实账号。<br>设置仅保存于此浏览器。</footer></aside><main class="workspace"><div class="page-meta"><div><h2 id="page-name"></h2><p id="page-description"></p></div><label><select id="view-state" aria-label="页面数据状态"><option value="normal">正常内容</option><option value="loading">加载中</option><option value="empty">空数据</option><option value="error">加载失败</option></select></label></div><div id="stage"></div><div class="source-note" id="source"></div></main></div><aside class="panel tuner" id="tuner" hidden><div class="row between"><h3>主题微调</h3><button id="close-tuner" aria-label="关闭主题微调">×</button></div><small>仅影响当前 ${kind} 预览</small><label>配色方案<select id="palette"><option value="blue">浅蓝 · 当前方向</option><option value="green">森林绿</option><option value="clay">陶土 · 温暖</option></select></label><label>主色<input id="primary" type="color"></label><label>背景色<input id="bg" type="color"></label><label>圆角 <output id="radius-value"></output><input id="radius" type="range" min="0" max="30"></label><label>字号 <output id="font-value"></output><input id="font" type="range" min="12" max="18"></label><label>留白 <output id="gap-value"></output><input id="gap" type="range" min="12" max="28"></label>${kind === "app" ? '<label>设备宽度 <output id="width-value"></output><input id="width" type="range" min="320" max="480"></label>' : ""}<div class="stack"><button id="export-theme" class="primary">导出主题参数</button><button id="reset-theme">恢复默认主题</button></div></aside>`;
    function applyPrefs() {
      const root = document.documentElement.style;
      root.setProperty("--primary", prefs.primary);
      const rgb = prefs.primary
        .match(/[a-f0-9]{2}/gi)
        .map((x) => parseInt(x, 16));
      const luminance = rgb
        .map((x) => x / 255)
        .map((x) => (x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4))
        .reduce((sum, x, i) => sum + x * [0.2126, 0.7152, 0.0722][i], 0);
      root.setProperty("--on-primary", luminance > 0.3 ? "#173b56" : "#ffffff");
      root.setProperty("--bg", prefs.bg);
      root.setProperty("--soft", `${prefs.primary}30`);
      for (const key of ["radius", "font", "gap"])
        root.setProperty(`--${key}`, `${prefs[key]}px`);
      root.setProperty("--phone-width", `${prefs.width}px`);
      for (const key of Object.keys(defaults)) {
        const input = document.getElementById(key);
        if (input) input.value = prefs[key];
        const output = document.getElementById(`${key}-value`);
        if (output) output.textContent = `${prefs[key]}px`;
      }
      try {
        localStorage.setItem(storageKey, JSON.stringify(prefs));
      } catch {
        /* preview remains usable */
      }
    }
    applyPrefs();
    for (const key of Object.keys(defaults))
      document.getElementById(key)?.addEventListener("input", (e) => {
        prefs[key] = ["radius", "font", "gap", "width"].includes(key)
          ? Number(e.target.value)
          : e.target.value;
        applyPrefs();
      });
    const tuner = document.getElementById("tuner");
    document.getElementById("tune").onclick = () => {
      tuner.hidden = !tuner.hidden;
    };
    document.getElementById("close-tuner").onclick = () => {
      tuner.hidden = true;
    };
    document.getElementById("palette").onchange = (e) => {
      const colors = {
        green: ["#287756", "#f5f6f2"],
        blue: ["#8fc8ed", "#f3f8fc"],
        clay: ["#a56448", "#f8f3ee"],
      }[e.target.value];
      [prefs.primary, prefs.bg] = colors;
      applyPrefs();
    };
    document.getElementById("reset-theme").onclick = () => {
      prefs = { ...defaults };
      document.getElementById("palette").value = "blue";
      applyPrefs();
    };
    document.getElementById("export-theme").onclick = () => {
      const blob = new Blob([JSON.stringify({ kind, ...prefs }, null, 2)], {
        type: "application/json",
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `damumu-${kind}-theme.json`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    };
    let current,
      viewState = "normal";
    const go = (id) => {
      if (location.hash === `#${id}`) draw();
      else location.hash = id;
    };
    function drawCatalog() {
      const q = document.getElementById("catalog-search").value.toLowerCase();
      const groups = [...new Set(routes.map((r) => r.group))];
      document.getElementById("catalog-nav").innerHTML = groups
        .map((group) => {
          const list = routes.filter(
            (r) =>
              r.group === group &&
              `${r.title} ${r.id}`.toLowerCase().includes(q),
          );
          return list.length
            ? `<details open><summary>${esc(group)}</summary>${list.map((r) => `<a href="#${r.id}" class="${r.id === current?.id ? "active" : ""}" ${r.id === current?.id ? 'aria-current="page"' : ""}>${esc(r.title)}${r.placeholder ? "<small>占位</small>" : ""}</a>`).join("")}</details>`
            : "";
        })
        .join("");
    }
    document.getElementById("catalog-search").oninput = drawCatalog;
    function draw() {
      current =
        routes.find((r) => r.id === location.hash.slice(1)) || routes[0];
      document.title = `${current.title} · 搭慕 ${kind} 预览`;
      document.getElementById("page-name").textContent = current.title;
      document.getElementById("page-description").textContent =
        current.description || "业务页面设计预览 · 所有操作仅在演示中生效";
      drawCatalog();
      let content;
      if (viewState === "normal")
        content = render(current.id, { go, toast, modal, draw });
      else if (viewState === "loading")
        content =
          '<section class="state-card"><h3>正在加载…</h3><div class="skeleton"></div><div class="skeleton"></div></section>';
      else
        content = `<section class="state-card"><div class="state-icon">${viewState === "empty" ? "○" : "↻"}</div><h3>${viewState === "empty" ? "这里暂时还没有内容" : "暂时无法加载"}</h3><p>${viewState === "empty" ? "有新的活动、消息或记录时，会显示在这里。" : "请稍后再试，已填写的内容不会提交到真实服务。"}</p>${button(viewState === "empty" ? "返回正常预览" : "重新加载", "retry", "primary")}</section>`;
      document.getElementById("stage").innerHTML =
        kind === "app"
          ? `<div class="app-stage"><div class="statusbar"><span>9:41</span><span>◔ ▰ 100%</span></div><div class="app-content">${content}</div>${["home", "discover", "create-basic", "create-schedule", "create-rules", "messages", "profile"].includes(current.id) ? dock(current.id) : ""}</div>`
          : adminShell(content, current);
      document.getElementById("source").innerHTML =
        `来源：<code>${esc(current.source)}</code><br>${current.placeholder ? "现有代码为说明页或本地占位；预览不表示功能已接通。" : "根据实际业务字段整理的独立 HTML 设计稿，并非正式页面的逐像素截图。"}<br>所有人物、活动、统计均为虚构示例；可直接通过目录查看各个页面和弹窗。`;
    }
    const dock = (id) =>
      `<nav class="dock" aria-label="App 主导航">${[
        ["home", "⌂", "首页"],
        ["discover", "⌕", "发现"],
        ["create-basic", "＋", "发布"],
        ["messages", "◫", "消息"],
        ["profile", "◉", "我的"],
      ]
        .map(
          ([route, icon, title]) =>
            `<a href="#${route}" class="${id === route ? "active" : ""}"><b>${icon}</b>${title}</a>`,
        )
        .join("")}</nav>`;
    function adminShell(content, page) {
      return `<div class="admin-stage"><div class="admin-shell"><nav class="admin-nav" aria-label="Admin 主导航"><div class="admin-brand">搭慕<small>COMMUNITY OPERATIONS</small></div>${routes
        .filter((r) => r.main)
        .map(
          (r) =>
            `<a href="#${r.id}" class="${page.id === r.id ? "active" : ""}"><span>${r.icon}</span>${esc(r.title)}</a>`,
        )
        .join(
          "",
        )}</nav><div class="admin-main"><header class="admin-header"><div><small>DAMUMU / 社区运营中心</small><h1>${esc(page.title)}</h1></div><div class="row">${link("发布公告", "announcement", "primary")}<span class="avatar">管</span></div></header><div class="admin-content">${content}</div></div></div></div>`;
    }
    document.getElementById("view-state").onchange = (e) => {
      viewState = e.target.value;
      draw();
    };
    document.getElementById("reset-demo").onclick = () => {
      location.reload();
    };
    document.addEventListener("click", (e) => {
      const target = e.target.closest("[data-route],[data-action]");
      if (!target) return;
      if (target.dataset.route) {
        go(target.dataset.route);
        return;
      }
      const action = target.dataset.action;
      if (action === "retry") {
        viewState = "normal";
        document.getElementById("view-state").value = "normal";
        draw();
        return;
      }
      if (action === "demo") {
        toast();
        return;
      }
      if (actions[action]) actions[action]({ go, toast, modal, draw, target });
    });
    document.addEventListener("submit", (e) => {
      if (e.target.closest("#stage")) {
        e.preventDefault();
        toast();
      }
    });
    document.addEventListener("change", (e) => {
      if (e.target.closest("#stage") && e.target.matches(".switch input"))
        toast("演示开关已切换，不影响正式服务。");
    });
    window.addEventListener("hashchange", () => {
      viewState = "normal";
      document.getElementById("view-state").value = "normal";
      draw();
    });
    draw();
    return { draw, go };
  }
  return {
    esc,
    button,
    link,
    badge,
    field,
    area,
    select,
    check,
    toggle,
    avatar,
    note,
    panel,
    menu,
    scene,
    table,
    toast,
    modal,
    boot,
  };
})();

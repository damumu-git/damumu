/* Offline DOM verification. Supply an external jsdom path; no service is started. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { JSDOM, VirtualConsole } = require(process.argv[2] || "jsdom");
const root = __dirname;
const tick = () => new Promise((resolve) => setTimeout(resolve, 5));
async function open(kind) {
  const errors = [];
  const console = new VirtualConsole();
  console.on("jsdomError", (error) => errors.push(error));
  const entry = path.join(root, kind, "index.html");
  const dom = new JSDOM(fs.readFileSync(entry, "utf8"), {
    url: pathToFileURL(entry).href,
    runScripts: "outside-only",
    virtualConsole: console,
    beforeParse(window) {
      window.fetch = () => {
        throw new Error("Network request attempted");
      };
      window.XMLHttpRequest = class {
        constructor() {
          throw new Error("XHR attempted");
        }
      };
    },
  });
  const w = dom.window,
    d = w.document;
  for (const stylesheet of d.querySelectorAll('link[rel="stylesheet"]')) {
    const cssPath = path.resolve(
      path.dirname(entry),
      stylesheet.getAttribute("href"),
    );
    assert.ok(cssPath.startsWith(root + path.sep), "External stylesheet");
    const style = d.createElement("style");
    style.textContent = fs.readFileSync(cssPath, "utf8");
    d.head.append(style);
    assert.ok(style.sheet?.cssRules.length > 50, "Stylesheet failed to parse");
  }
  for (const script of d.querySelectorAll("script[src]")) {
    const scriptPath = path.resolve(
      path.dirname(entry),
      script.getAttribute("src"),
    );
    assert.ok(scriptPath.startsWith(root + path.sep), "External script");
    w.eval(fs.readFileSync(scriptPath, "utf8"));
  }
  const routes =
    w[kind === "app" ? "APP_PREVIEW_ROUTES" : "ADMIN_PREVIEW_ROUTES"];
  assert.ok(routes?.length, `Missing ${kind} route inventory`);
  async function go(id) {
    w.location.hash = id;
    await tick();
  }
  function click(selector) {
    const node = d.querySelector(selector);
    assert.ok(node, `Missing ${selector} on ${w.location.hash}`);
    node.click();
  }
  function change(selector, value, event = "change") {
    const node = d.querySelector(selector);
    assert.ok(node, selector);
    node.value = value;
    node.dispatchEvent(new w.Event(event, { bubbles: true }));
  }
  function submit(selector) {
    const node = d.querySelector(selector);
    assert.ok(node, selector);
    node.dispatchEvent(
      new w.Event("submit", { bubbles: true, cancelable: true }),
    );
  }
  const ids = new Set(routes.map((r) => r.id));
  assert.equal(ids.size, routes.length, "Duplicate route");
  for (const route of routes) {
    await go(route.id);
    assert.equal(d.querySelector("#page-name").textContent, route.title);
    assert.ok(
      d.querySelector("#stage").textContent.trim().length > 20,
      `Empty ${route.id}`,
    );
    assert.ok(
      !d.querySelector("#stage").textContent.includes("undefined"),
      `Undefined field on ${route.id}`,
    );
    const sourceFile = route.source.split(" · ")[0];
    assert.ok(
      fs.existsSync(path.join(root, "..", sourceFile)),
      `Missing source ${sourceFile}`,
    );
    for (const target of d.querySelectorAll("[data-route]"))
      assert.ok(
        ids.has(target.dataset.route),
        `Broken ${route.id} -> ${target.dataset.route}`,
      );
    for (const target of d.querySelectorAll('#stage a[href^="#"]'))
      assert.ok(ids.has(target.hash.slice(1)), `Broken hash ${target.hash}`);
    // HTML form fields must not end up nested inside buttons or other forms.
    assert.equal(
      d.querySelectorAll("button button,button input,form form").length,
      0,
      `Invalid interactive nesting on ${route.id}`,
    );
    for (const state of ["loading", "empty", "error", "normal"]) {
      change("#view-state", state);
      assert.ok(d.querySelector("#stage").textContent.trim());
    }
  }
  // Theme changes are applied independently of a backend, and reset locally.
  click("#tune");
  assert.equal(d.querySelector("#tuner").hidden, false);
  change("#palette", "blue");
  assert.equal(
    d.documentElement.style.getPropertyValue("--primary"),
    "#8fc8ed",
  );
  change("#radius", "24", "input");
  assert.equal(d.documentElement.style.getPropertyValue("--radius"), "24px");
  click("#reset-theme");
  assert.equal(
    d.documentElement.style.getPropertyValue("--primary"),
    "#8fc8ed",
  );
  change("#catalog-search", "不存在的页面", "input");
  assert.equal(d.querySelectorAll("#catalog-nav a").length, 0);
  change("#catalog-search", "", "input");
  assert.equal(d.querySelectorAll("#catalog-nav a").length, routes.length);
  if (kind === "app") {
    await go("home");
    change("[data-feed-search]", "咖啡", "input");
    assert.equal(d.querySelectorAll(".event-card").length, 1);
    click('[data-action="event:1"]');
    await tick();
    assert.ok(d.querySelector("#stage").textContent.includes("周末咖啡"));
    await go("apply");
    submit("[data-form=apply]");
    await tick();
    assert.equal(w.location.hash, "#join-result");
    await go("event");
    assert.ok(d.querySelector("#stage").textContent.includes("待审核"));
    change("[data-participation]", "已通过");
    assert.ok(d.querySelector("#stage").textContent.includes("示例集合点"));
    await go("chat");
    d.querySelector("[name=message]").value = "离线消息验证";
    submit("[data-form=chat]");
    await tick();
    assert.ok(
      d.querySelector("#new-messages").textContent.includes("离线消息验证"),
    );
    await go("copy-event");
    click('[data-action="copy:0"]');
    await tick();
    await go("create-schedule");
    assert.equal(d.querySelector("[data-draft=start]").value, "");
    change("[data-draft=start]", "2026-11-01T10:00", "input");
    change("[data-draft=end]", "2026-11-01T12:00", "input");
    await go("create-rules");
    click("[data-action=capacity-plus]");
    assert.equal(d.querySelector("#capacity").textContent, "7");
    click("[data-action=publish]");
    await tick();
    assert.equal(w.location.hash, "#organizer");
    await go("cancel-event");
    d.querySelector("textarea").value = "天气原因";
    submit("[data-form=cancel]");
    await tick();
    assert.ok(d.querySelector("#stage").textContent.includes("活动已取消"));
    await go("external");
    assert.equal(d.querySelectorAll("#stage input[disabled]").length, 2);
    await go("delete-account");
    click("[data-action=delete-confirm]");
    await tick();
    assert.equal(w.location.hash, "#delete-account");
  } else {
    await go("users");
    change("[data-search]", "安安", "input");
    assert.equal(d.querySelectorAll("tbody tr").length, 1);
    click('[data-action="user:1"]');
    await tick();
    click("[data-action=ban-user]");
    await tick();
    d.querySelector("textarea").value = "演示原因";
    submit("[data-form=action]");
    await tick();
    assert.ok(d.querySelector("#stage").textContent.includes("已封禁"));
    await go("events");
    change("[data-filter]", "已取消");
    assert.equal(d.querySelectorAll("tbody tr").length, 1);
    await go("event-detail");
    click("[data-action=approve-member]");
    assert.equal(d.querySelectorAll("[data-action=approve-member]").length, 0);
    await go("category-new");
    d.querySelector("[data-name=zh]").value = "离线分类";
    submit("[data-form=category]");
    await tick();
    assert.ok(
      d.querySelector("#list-content").textContent.includes("离线分类"),
    );
    click('[data-action="category:6"]');
    await tick();
    assert.equal(w.location.hash, "#category-edit");
    await go("region-new");
    d.querySelector("[data-name=zh]").value = "离线地区";
    submit("[data-form=region]");
    await tick();
    assert.ok(d.querySelector("#stage").textContent.includes("离线地区"));
    click('[data-action="region:4"]');
    await tick();
    assert.equal(w.location.hash, "#region-edit");
    await go("reports");
    click('[data-action="report:0:处置完成"]');
    await tick();
    submit("[data-form=action]");
    await tick();
    assert.ok(d.querySelector("#stage").textContent.includes("已解决"));
    await go("announcement");
    submit("[data-form=announcement]");
    await tick();
    assert.equal(w.location.hash, "#dashboard");
  }
  assert.deepEqual(
    errors.map((e) => e.message),
    [],
    `${kind} DOM errors`,
  );
  const inventory = routes
    .map(
      (r) =>
        `| ${r.title} | \`${kind}/index.html#${r.id}\` | ${r.source} | ${r.placeholder ? "现有占位 / 说明" : "业务预览"} |`,
    )
    .join("\n");
  process.stdout.write(
    `${kind}: ${routes.length} routes × 4 states; links, forms and key interactions passed\n`,
  );
  dom.window.close();
  return inventory;
}
(async () => {
  const app = await open("app"),
    admin = await open("admin");
  if (process.argv.includes("--inventory"))
    fs.writeFileSync(
      path.join(root, "PAGES.md"),
      `# 页面覆盖清单\n\n按实际 Flutter / React 的用户可见页面及弹窗整理。弹窗在目录中可独立打开，便于评审；不代表正式产品新增独立路由。通用加载、空数据、失败状态由顶部选择器切换。\n\n此清单由离线检查读取页面目录生成；业务变化后应重新核对源代码并更新。\n\n| 页面 / 弹窗 | 本地入口 | 代码来源 | 类型 |\n| --- | --- | --- | --- |\n${app}\n${admin}\n`,
    );
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

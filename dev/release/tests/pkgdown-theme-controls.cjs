// Test the actual head-selected theme script without R, browser, or npm dependencies.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const [root, upstream] = process.argv.slice(2);
if (!root || !upstream || process.argv.length !== 4) {
  throw new Error("Supply the nominated source root and pinned pkgdown theme script");
}
const head = fs.readFileSync(path.join(root, "pkgdown/templates/head.html"), "utf8");
const matches = [...head.matchAll(/\{\{#lightswitch\}\}<script src="\{\{#site\}\}\{\{root\}\}\{\{\/site\}\}([^"/]+\.js)"><\/script>\{\{\/lightswitch\}\}/g)];
assert.equal(matches.length, 1, "Exactly one theme script must run before head dependencies");
const name = matches[0][1];
assert.ok(["lightswitch.js", "gptr-lightswitch.js"].includes(name));
const theme = fs.readFileSync(name === "lightswitch.js" ? upstream :
  path.join(root, "pkgdown/assets", name), "utf8");
const extra = fs.readFileSync(path.join(root, "pkgdown/extra.js"), "utf8");

function invoke(context, callback) {
  context.__theme_control_callback = callback;
  try {
    vm.runInContext("__theme_control_callback()", context, { timeout: 1000 });
  } finally {
    delete context.__theme_control_callback;
  }
}

function page({ stored = null, dark = false, blocked = "", shared = null, navbar = true } = {}) {
  const values = shared || new Map([["other", "unrelated storage sentinel"]]);
  if (stored !== null) values.set("theme", stored);
  const rootNode = { dataset: {}, setAttribute(key, value) {
    assert.equal(key, "data-bs-theme");
    this.dataset.bsTheme = String(value);
    observers.forEach((callback) => invoke(context, callback));
  } };
  const observers = [];
  const windowEvents = {};
  const documentEvents = {};
  const mediaEvents = {};
  const media = { matches: dark, addEventListener(event, callback) { mediaEvents[event] = callback; } };
  const options = ["light", "dark", "auto"].map((choice) => ({
    choice, textContent: ` ${choice} `, attributes: {}, active: false, events: {},
    classList: { toggle(key, active) {
      assert.equal(key, "active");
      options.find((item) => item.choice === choice).active = active;
    } },
    getAttribute(key) { return key === "data-bs-theme-value" ? choice : this.attributes[key]; },
    setAttribute(key, value) { this.attributes[key] = String(value); },
    querySelector() { return { classList: { value: `icon-${choice}` } }; },
    addEventListener(event, callback) { this.events[event] = callback; }
  }));
  const switchIcon = { classList: { value: "original-icon" } };
  const switcher = { attributes: {}, focused: false,
    setAttribute(key, value) { this.attributes[key] = String(value); },
    querySelector() { return switchIcon; }, focus() { this.focused = true; } };
  const icon = { href: "https://example.invalid/favicon.svg" };
  const document = {
    documentElement: rootNode,
    currentScript: { src: "https://example.invalid/extra.js" },
    getElementById(id) { return id === "gptr-favicon" ? icon : null; },
    querySelector(selector) { return navbar && selector === "#dropdown-lightswitch" ? switcher : null; },
    querySelectorAll(selector) { return navbar && selector === "[data-bs-theme-value]" ? options : []; },
    addEventListener(event, callback) { documentEvents[event] = callback; }
  };
  const storage = {
    getItem(key) { if (blocked === "read") throw new Error("synthetic read denied"); return values.get(key) ?? null; },
    setItem(key, value) { if (blocked === "write") throw new Error("synthetic write denied"); values.set(key, value); }
  };
  const context = vm.createContext({ document, URL,
    window: { matchMedia() { return media; },
      addEventListener(event, callback) { windowEvents[event] = callback; } },
    MutationObserver: class { constructor(callback) { this.callback = callback; }
      observe() { observers.push(this.callback); } },
    ResizeObserver: class { observe() {} }
  });
  Object.defineProperty(context, "localStorage", { configurable: true,
    get() { if (blocked === "access") throw new Error("synthetic storage access denied"); return storage; } });
  vm.runInContext(theme, context, { timeout: 1000 });
  vm.runInContext(extra, context, { timeout: 1000 });
  if (documentEvents.DOMContentLoaded) invoke(context, documentEvents.DOMContentLoaded);
  assert.equal(typeof windowEvents.DOMContentLoaded, "function", "Theme listeners must initialize");
  invoke(context, windowEvents.DOMContentLoaded);
  return { values, rootNode, options, switcher, switchIcon, icon,
    click(choice) { const item = options.find((value) => value.choice === choice);
      assert.equal(typeof item.events.click, "function"); invoke(context, item.events.click); },
    system(value) { media.matches = value; assert.equal(typeof mediaEvents.change, "function");
      invoke(context, mediaEvents.change); } };
}

function selected(value, choice, applied = choice) {
  assert.equal(value.rootNode.dataset.bsTheme, applied);
  assert.deepEqual(value.options.filter((item) => item.active).map((item) => item.choice), [choice]);
  value.options.forEach((item) => assert.equal(item.attributes["aria-pressed"], String(item.choice === choice)));
  assert.equal(value.switcher.attributes["aria-label"], ` ${choice} `);
  assert.equal(value.switchIcon.classList.value, `icon-${choice}`);
  assert.ok(value.icon.href.endsWith(applied === "dark" ? "/favicon-dark.svg" : "/favicon.svg"));
}

test("a first visit starts light even when the system prefers dark", () => {
  const value = page({ dark: true }); selected(value, "light");
  assert.equal(value.values.get("other"), "unrelated storage sentinel");
});
for (const stored of ["light", "dark", "auto"]) {
  test(`stored ${stored} choice survives initialization`, () => {
    const value = page({ stored, dark: true }); selected(value, stored, stored === "auto" ? "dark" : stored);
    assert.equal(value.values.get("theme"), stored);
  });
}
test("ordinary toggles persist and a new page restores the choice", () => {
  const value = page(); value.click("dark"); selected(value, "dark");
  assert.equal(value.switcher.focused, true); assert.equal(value.values.get("theme"), "dark");
  selected(page({ shared: value.values }), "dark");
});
for (const blocked of ["access", "read", "write"]) {
  test(`${blocked}-denied storage leaves initialization and toggles functional`, () => {
    const value = page({ dark: true, blocked }); selected(value, "light");
    value.click("dark"); selected(value, "dark");
    value.system(false); selected(value, "dark");
    value.click("auto"); selected(value, "auto", "light");
    value.system(true); selected(value, "auto", "dark");
    value.click("light"); value.system(false); value.system(true); selected(value, "light");
    assert.equal(value.switcher.focused, true);
  });
}
test("stored Auto follows system changes without rewriting its preference", () => {
  const value = page({ stored: "auto", dark: true }); selected(value, "auto", "dark");
  value.system(false); selected(value, "auto", "light");
  assert.equal(value.values.get("theme"), "auto");
});
test("a failed persistence write retains a prior explicit page choice", () => {
  const value = page({ stored: "light", blocked: "write" }); value.click("dark");
  value.system(false); value.system(true); selected(value, "dark");
  assert.equal(value.values.get("theme"), "light");
});
test("an invalid stored theme cannot become a document theme", () => {
  selected(page({ stored: "invalid-private-value", dark: true }), "light");
});
test("pages without a switcher still initialize their theme and favicon", () => {
  const value = page({ stored: "dark", navbar: false });
  assert.equal(value.rootNode.dataset.bsTheme, "dark");
  assert.ok(value.icon.href.endsWith("/favicon-dark.svg"));
});

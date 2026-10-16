// Offline VM controls for our script only; browser layout remains a separate gate.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const root = process.argv[2];
if (!root || process.argv.length !== 3) throw new Error("Supply the nominated source root");
const script = fs.readFileSync(path.join(root, "pkgdown", "extra.js"), "utf8");
const css = fs.readFileSync(path.join(root, "pkgdown", "extra.css"), "utf8");

function node(width, client) {
  return {
    scrollWidth: width, clientWidth: client, attributes: {}, children: [],
    setAttribute(key, value) { this.attributes[key] = value; },
    removeAttribute(key) { delete this.attributes[key]; },
    append(child) { this.children.push(child); child.parentElement = this; }
  };
}

function invoke(context, callback) {
  context.__gptr_ui_callback = callback;
  try {
    vm.runInContext("__gptr_ui_callback()", context, { timeout: 1000 });
  } finally {
    delete context.__gptr_ui_callback;
  }
}

function run(tables, pre = [], blockedStorage = false) {
  const created = [];
  const observed = [];
  const callbacks = {};
  const document = {
    documentElement: { dataset: {}, setAttribute() {} },
    getElementById() { return null; },
    addEventListener(event, callback) { callbacks[event] = callback; },
    querySelectorAll(selector) { return selector === "#main table" ? tables : pre; },
    createElement() { const region = node(240, 100); created.push(region); return region; }
  };
  const localStorage = {
    getItem() { if (blockedStorage) throw new Error("synthetic storage denial"); return null; },
    setItem() { if (blockedStorage) throw new Error("synthetic storage denial"); }
  };
  const context = vm.createContext({
    document, localStorage,
    ResizeObserver: class {
      constructor(update) { this.update = update; }
      observe(region) { observed.push({ region, update: this.update }); this.update(); }
    }
  });
  vm.runInContext(script, context, { timeout: 1000 });
  assert.equal(typeof callbacks.DOMContentLoaded, "function");
  invoke(context, callbacks.DOMContentLoaded);
  return { created, observed, context };
}

function table(parent, caption) {
  const value = node(240, 100);
  value.parentElement = parent;
  value.querySelector = () => caption === null ? null : { textContent: caption };
  value.before = (region) => { value.inserted = region; };
  return value;
}

const bare = table(node(100, 100), null);
const code = node(260, 100);
const ready = run([bare], [code], true);
assert.equal(ready.created.length, 1);
const region = ready.created[0];
assert.equal(bare.parentElement, region);
assert.equal(region.attributes.role, "region");
assert.equal(region.attributes["aria-label"], "Table 1");
assert.equal(region.attributes.tabindex, "0", "Focus must reach the wrapper scrollport");
assert.equal(code.attributes.tabindex, "0");
region.scrollWidth = region.clientWidth;
invoke(ready.context, ready.observed.find((item) => item.region === region).update);
assert.equal(region.attributes.tabindex, undefined, "Resize must update wrapper focusability");

assert.match(css, /\.template-article \.gptr-vignette-brand\s*\{\s*display:\s*none;\s*\}/);
assert.match(css, /#main \.table-responsive > table\s*\{\s*display:\s*table;\s*overflow:\s*visible;\s*\}/);
assert.ok(!script.includes("Storage.prototype"), "Storage APIs must remain dependency-owned");
console.log("PKGDOWN_UI_CONTROLS_OK");

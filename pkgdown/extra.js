// Start in light mode and retain the reader's subsequent theme choice.
if (localStorage.getItem("theme") === null) {
  localStorage.setItem("theme", "light");
  document.documentElement.setAttribute("data-bs-theme", "light");
}

// Keep the tab icon in step with the native pkgdown light switch.
(() => {
  const icon = document.getElementById("gptr-favicon");
  if (!icon) return;
  const root = new URL(".", document.currentScript.src);
  const update = () => {
    const dark = document.documentElement.dataset.bsTheme === "dark";
    icon.href = new URL(dark ? "favicon-dark.svg" : "favicon.svg", root).href;
  };
  update();
  new MutationObserver(update).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-bs-theme"]
  });
})();

// Wide tables scroll independently; keyboard users can focus overflowing tables.
document.addEventListener("DOMContentLoaded", () => {
  const makeScrollable = (region) => {
    const update = () => {
      if (region.scrollWidth > region.clientWidth) region.setAttribute("tabindex", "0");
      else region.removeAttribute("tabindex");
    };
    update();
    new ResizeObserver(update).observe(region);
  };
  document.querySelectorAll("#main table").forEach((table, index) => {
    if (table.parentElement.classList.contains("table-responsive")) return;
    const region = document.createElement("div");
    region.className = "table-responsive";
    region.setAttribute("role", "region");
    const caption = table.querySelector("caption");
    region.setAttribute("aria-label", caption ? caption.textContent : `Table ${index + 1}`);
    table.before(region);
    region.append(table);
    makeScrollable(region);
  });
  document.querySelectorAll("#main pre").forEach((block, index) => {
    block.setAttribute("role", "region");
    block.setAttribute("aria-label", `Code block ${index + 1}`);
    makeScrollable(block);
  });
});

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
    const wrapped = table.parentElement.classList.contains("table-responsive");
    const region = wrapped ? table.parentElement : document.createElement("div");
    if (!wrapped) {
      region.className = "table-responsive";
      table.before(region);
      region.append(table);
    }
    region.setAttribute("role", "region");
    const caption = table.querySelector("caption");
    region.setAttribute("aria-label", caption ? caption.textContent : `Table ${index + 1}`);
    makeScrollable(region);
  });
  document.querySelectorAll("#main pre").forEach((block, index) => {
    block.setAttribute("role", "region");
    block.setAttribute("aria-label", `Code block ${index + 1}`);
    makeScrollable(block);
  });
});

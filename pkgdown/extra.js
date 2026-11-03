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
    new ResizeObserver(update).observe(region);
  };
  document.querySelectorAll("#main table").forEach((table, index) => {
    const region = document.createElement("div");
    region.className = "table-responsive";
    table.before(region);
    region.append(table);
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
  // Inline code of up to 32 characters fits a phone's line, so outside tables it never breaks.
  document.querySelectorAll("#main :not(pre) > code").forEach((code) => {
    if (code.textContent.length <= 32 && !code.closest("table")) code.classList.add("gptr-nowrap");
  });
  // The home page shows a figure above each lead point; README.md itself stays plain text.
  const points = {
    "Work with live R objects.": ["live", "Two piped peter() calls in one R session: the " +
      "first creates fit from mtcars, the second creates res from fit, and all three stay."],
    "Use agents or typed decisions.": ["agents", "A prompt goes to a System 2 agent, which " +
      "calls tools and returns a gptr_session; three inputs go to a System 1 decision model, " +
      "which returns TRUE, FALSE, TRUE, one answer per input."],
    "Keep a record you can rerun.": ["record", "A peter() call in analysis.R sends a prompt " +
      "to the model and the R code it returns is recorded under the call; a later replay runs " +
      "that code in an R session with no model call."],
    "Improve Peter on your own task.": ["coach", "A harness of note, skills, review and rules " +
      "runs your task; coaches propose changes; a final run must pass your check before the " +
      "changed harness is kept, and it can be coached again."]
  };
  document.querySelectorAll(".template-home #main > .section > ul > li > strong:first-child")
    .forEach((lead) => {
      const point = points[lead.textContent];
      if (!point) return;
      const figure = document.createElement("img");
      figure.src = `figures/point-${point[0]}.svg`;
      figure.alt = point[1];
      figure.width = 360;
      figure.height = 162;
      lead.parentElement.prepend(figure);
      lead.parentElement.parentElement.classList.add("gptr-points");
    });
});

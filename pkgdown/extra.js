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
  // Inline code of up to 32 characters (12 in a table) fits a phone's line, so it never breaks;
  // longer code in a table breaks only after _ / | - or ::, never inside a name.
  document.querySelectorAll("#main :not(pre) > code").forEach((code) => {
    const table = code.closest("table");
    if (code.textContent.length <= (table ? 12 : 32)) {
      code.classList.add("gptr-nowrap");
    } else if (table && !code.children.length) {
      const parts = code.textContent.split(/(?<=.(?:[_/|-]|::))(?=.)/);
      code.replaceChildren(...parts.flatMap((part, i) =>
        i ? [document.createElement("wbr"), part] : part));
    }
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
    "Improve the agent on your own task.": ["coach", "A harness of note, skills, review and " +
      "rules runs your task; coaches write new coaching; code checks a final run with it, the " +
      "revised harness is kept only if that run passes, and the next round starts from the " +
      "harness."]
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
  // The launch video sits above the lead points. It plays only if the reader allows motion,
  // and on a phone, where its text is too small to read, it waits on its poster.
  const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const phone = window.matchMedia("(max-width: 575.98px)").matches;
  document.querySelector(".gptr-points")?.insertAdjacentHTML("beforebegin",
    `<figure class="gptr-video"><video ${still || phone ? "" : "autoplay "}muted loop ` +
    `playsinline controls preload="${phone ? "none" : "metadata"}" width="1920" height="1080" ` +
    'aria-label="Objects stay in memory across prompts; System 1 returns typed decisions and ' +
    "System 2 agents use tools; each session becomes a runnable document; gptr runs in " +
    "terminals, RStudio, VS Code, Positron and Jupyter, serves its session over MCP and " +
    "coaches its harness on your task. The end card reads gptr, a grammar of Peter, honoring " +
    'Peter Naur and Peter Wason."></video>' +
    "<figcaption>gptr in 36 seconds, without sound.</figcaption></figure>");
  const video = document.querySelector(".gptr-video video");
  // Figures and the video follow the light switch in every browser: the fragment "#dark"
  // selects a figure's dark colours, and the video has a dark render that resumes in place.
  const dark = () => document.documentElement.dataset.bsTheme === "dark";
  const figures = document.querySelectorAll('#main img[src^="figures/"]');
  const paint = (figure, search) => {
    const url = new URL(figure.src);
    if (search) url.search = search;
    url.hash = dark() ? "dark" : "";
    if (url.href !== figure.src) figure.src = url.href;
  };
  const film = () => {
    const name = `video/gptr${dark() ? "-dark" : ""}`;
    if (!video || video.getAttribute("poster") === `${name}.jpg`) return;
    const time = video.currentTime;
    if (video.getAttribute("src")) video.autoplay = !video.paused;
    video.poster = `${name}.jpg`;
    video.src = `${name}.mp4`;
    if (time) {
      video.addEventListener("loadedmetadata", () => (video.currentTime = time), { once: true });
    }
  };
  const repaint = () => {
    figures.forEach((figure) => paint(figure));
    film();
  };
  repaint();
  new MutationObserver(repaint)
    .observe(document.documentElement, { attributes: true, attributeFilter: ["data-bs-theme"] });
  // A caption describes its figure to assistive technology.
  figures.forEach((figure, index) => {
    const caption = figure.nextElementSibling;
    if (!caption || !caption.classList.contains("figcaption")) return;
    caption.id = `figure-caption-${index + 1}`;
    figure.setAttribute("aria-describedby", caption.id);
  });
  // A figure draws once at load and again from the start when it first comes into view,
  // unless the reader asks for reduced motion, which shows the final frame.
  if (still) return;
  const replay = new IntersectionObserver((entries) => entries.forEach((entry) => {
    if (!entry.isIntersecting) return;
    replay.unobserve(entry.target);
    paint(entry.target, "?view");
  }), { threshold: 0.6 });
  figures.forEach((figure) => replay.observe(figure));
});

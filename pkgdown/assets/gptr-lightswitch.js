/*!
 * Adapted from Bootstrap's color mode toggler and pkgdown 2.2.1's bslib updates.
 * Copyright 2011-2023 The Bootstrap Authors; updates by the bslib authors.
 * CC BY 3.0: https://creativecommons.org/licenses/by/3.0/
 * Source: https://github.com/r-lib/pkgdown/blob/v2.2.1/inst/BS5/assets/lightswitch.js
 * Changes: light default, guarded storage, and page-local choice after denied persistence.
 */
(() => {
  const allowed = new Set(["light", "dark", "auto"]);
  let theme = "light";
  try {
    const stored = localStorage.getItem("theme");
    if (allowed.has(stored)) theme = stored;
  } catch {
    // A blocked storage accessor or read does not prevent theme initialization.
  }
  const system = window.matchMedia("(prefers-color-scheme: dark)");
  const apply = () => {
    const selected = theme === "auto" ? (system.matches ? "dark" : "light") : theme;
    document.documentElement.setAttribute("data-bs-theme", selected);
  };
  const show = (focus = false) => {
    let active;
    document.querySelectorAll("[data-bs-theme-value]").forEach((button) => {
      const selected = button.getAttribute("data-bs-theme-value") === theme;
      button.classList.toggle("active", selected);
      button.setAttribute("aria-pressed", selected);
      if (selected) active = button;
    });
    const switcher = document.querySelector("#dropdown-lightswitch");
    if (!switcher || !active) return;
    switcher.setAttribute("aria-label", active.textContent);
    switcher.querySelector("span").classList.value = active.querySelector("span").classList.value;
    if (focus) switcher.focus();
  };
  apply();
  system.addEventListener("change", () => {
    if (theme === "auto") apply();
  });
  window.addEventListener("DOMContentLoaded", () => {
    show();
    document.querySelectorAll("[data-bs-theme-value]").forEach((button) => {
      button.addEventListener("click", () => {
        const selected = button.getAttribute("data-bs-theme-value");
        if (!allowed.has(selected)) return;
        theme = selected;
        apply();
        try {
          localStorage.setItem("theme", theme);
        } catch {
          // Keep the selected mode on this page even when persistence is denied.
        }
        show(true);
      });
    });
  });
})();

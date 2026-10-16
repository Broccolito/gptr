---
name: shiny-bslib
description: "Build Shiny apps with bslib layouts (page_sidebar, cards, value boxes) for artifacts."
license: MIT
metadata:
  source: "gptr research report 17, sections 2.4 and 4.4"
---

# Shiny artifacts with bslib

Write `<artifacts>/<id>/app.R` (id: lower-case letters, digits, `-`), then in r run
`a = peter$app("<id>", data = c("obj"))` and print `a`. Each call snapshots the objects into a new
version on the same URL. Fix what the checks, messages or screenshot show with edit (not a rewrite)
and call `peter$app()` again until no check reads FAILED.
After revising, assign the new handle in its own statement (`a = peter$app(...)`), then inspect
`a$checks` and call `gptr_return(a)`. Capture `print(a)` output only after the assignment.

Rules for app.R:
- One file ending in `shinyApp(ui, server)`; the objects in `data` exist under their names. Never
  read files or call `setwd()`, `runApp()` or `install.packages()`.
- Ship small data (the rows and columns shown); check it in r with `dim()` or `peter$describe(x)`.
- Start dashboards with `page_sidebar(sidebar = sidebar(...), fillable = FALSE, ...)`.
  Set `fillable = FALSE` explicitly so the main area can shrink beside an open sidebar;
  bslib's filling layout otherwise imposes a desktop minimum width. Keep inputs in the named
  `sidebar`; compact KPIs as `value_box()` in
  `layout_columns(..., fill = FALSE)`;
  each chart or table in `card(card_header(), ..., full_screen = TRUE)`; never nest cards or pages.
- Keep plots readable at narrow widths with a bounded height (for example,
  `plotOutput(..., height = "300px")`) and legible axis text. Wrap wide tables in a standard
  `table-responsive` div with `tabindex = 0`, `role = "region"` and a descriptive `aria-label`
  so keyboard users can scroll horizontally.
- Stack chart and table cards when a sidebar leaves little content width; check each card
  against the visible content area at 320, 768 and 1440 pixels and at 200% browser zoom.
  Page scroll width alone can miss a clipped sidebar main area.
- Prefer `numericInput()` for exact numeric thresholds when keyboard focus must preserve the
  value; use sliders for visual adjustments.
- `renderPlot()` with ggplot2 and `theme_minimal()`; plotly, DT or leaflet only if `<r_env>` lists
  them. Filter once in `reactive()`; `req()` for empty inputs, `validate(need())` for empty
  results; no custom CSS or JS. Use `=` for assignment and `|>` for data transforms;
  add ggplot2 geoms, labels, scales and themes with `+`.

```r
library(shiny)
library(bslib)
ui = page_sidebar(
  title = "Markers",
  fillable = FALSE,
  sidebar = sidebar(textInput("gene", "Gene")),
  layout_columns(value_box("Markers shown", textOutput("n")), fill = FALSE),
  card(
    card_header("Top markers"),
    div(
      class = "table-responsive", tabindex = 0, role = "region",
      `aria-label` = "Top markers", tableOutput("top")
    ),
    full_screen = TRUE
  )
)
server = function(input, output, session) {
  shown = reactive(markers[grepl(input$gene, markers$gene, ignore.case = TRUE), ])
  output$n = renderText(nrow(shown()))
  output$top = renderTable({
    validate(need(nrow(shown()) > 0, "No marker matches the search."))
    head(shown(), 20)
  })
}
shinyApp(ui, server)
```

Raw HTML only when truly required: write `<artifacts>/<id>/page.html` and call
`peter$app("<id>", data = c("obj"), kind = "html")`; the data is `window.GPTR_DATA.<name>`.

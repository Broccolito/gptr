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

Rules for app.R:
- One file ending in `shinyApp(ui, server)`; the objects in `data` exist under their names. Never
  read files or call `setwd()`, `runApp()` or `install.packages()`.
- Ship small data (the rows and columns shown); check it in r with `dim()` or `peter$describe(x)`.
- `page_sidebar()` with the inputs in `sidebar()`; KPIs as `value_box()` in `layout_columns()`;
  each chart or table in `card(card_header(), ..., full_screen = TRUE)`; never nest cards or pages.
- `renderPlot()` with ggplot2 and `theme_minimal()`; plotly, DT or leaflet only if `<r_env>` lists
  them. Filter once in `reactive()`; `req()` for empty inputs, `validate(need())` for empty
  results; no custom CSS or JS. Use `=` and `|>`.

```r
library(shiny)
library(bslib)
ui = page_sidebar(
  title = "Markers",
  sidebar = sidebar(textInput("gene", "Gene")),
  layout_columns(value_box("Markers shown", textOutput("n"))),
  card(card_header("Top markers"), tableOutput("top"), full_screen = TRUE)
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

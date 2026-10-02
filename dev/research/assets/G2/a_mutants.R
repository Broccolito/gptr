# G2 (a) negative controls: one subtle bug per level in shiny_a and html_a; the checker must FAIL them.
G2 = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2"
src = file.path(G2, "a_apps"); dst = file.path(G2, "a_mutants")
unlink(dst, recursive = TRUE)
mut = list(
  L1 = list(shiny_a = c("agg[order(-agg$revenue), ]", "agg[order(agg$revenue), ]"),
            html_a = c("b[1].revenue - a[1].revenue", "a[1].revenue - b[1].revenue")),
  L2 = list(shiny_a = c("sales$region == input$region", "sales$region != input$region"),
            html_a = c("`${rows.length} orders`", "`${rows.length + 1} orders`")),
  L3 = list(shiny_a = c("mean(sel()$price)", "median(sel()$price)"),
            html_a = c("rows.slice(0, 10)", "rows.slice(0, 9)")),
  L4 = list(shiny_a = c("xvar = \"wt\", yvar = \"mpg\"", "xvar = \"mpg\", yvar = \"wt\""),
            html_a = c("const COLS = [\"name\", \"wt\", \"mpg\", \"hp\"];", "const COLS = [\"name\", \"wt\", \"mpg\"];")),
  L5 = list(shiny_a = c("d[e$row, e$col + 1]", "d[e$row, e$col]"),
            html_a = c("warehouses.reduce((s, w) => s + w.value(), 0)", "warehouses[0].value()")))
for (lv in names(mut)) {
  dir.create(file.path(dst, lv), recursive = TRUE)
  for (impl in names(mut[[lv]])) {
    ext = if (startsWith(impl, "shiny")) ".R" else ".html"
    x = readLines(file.path(src, lv, paste0(impl, ext)), warn = FALSE)
    pat = mut[[lv]][[impl]]
    hit = grepl(pat[1], x, fixed = TRUE)
    stopifnot(sum(hit) == 1)
    x[hit] = sub(pat[1], pat[2], x[hit], fixed = TRUE)
    writeLines(x, file.path(dst, lv, paste0(impl, ext)))
  }
}
cat("mutants written:", length(list.files(dst, recursive = TRUE)), "\n")

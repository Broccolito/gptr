# G2 (a): token cost of the 20 verified apps, growth over complexity, and data transfer cost.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
A = file.path(G2, "a_apps")
source(file.path(A, "data.R"))
rows = list()
for (lv in paste0("L", 1:5)) for (impl in c("shiny_a", "shiny_b", "html_a", "html_b")) {
  f = file.path(A, lv, paste0(impl, if (startsWith(impl, "shiny")) ".R" else ".html"))
  x = paste(readLines(f, warn = FALSE), collapse = "\n")
  rows[[length(rows) + 1]] = data.frame(level = lv, impl, lines = length(strsplit(x, "\n")[[1]]),
    chars = nchar(x), o200k = tok_o200k(x), cl100k = tok_cl100k(x),
    as_write_arg = tok_o200k(j(list(path = basename(f), content = x))))
}
d = do.call(rbind, rows)
d$side = ifelse(startsWith(d$impl, "shiny"), "shiny", "html")
print(d[, c("level", "impl", "lines", "chars", "o200k", "cl100k", "as_write_arg")], row.names = FALSE)

cat("\nPer level: mean of the two implementations per side (o200k), ratio html/shiny, and the range over\n")
cat("the four cross pairs (html_x / shiny_y):\n")
for (lv in unique(d$level)) {
  s = d$o200k[d$level == lv & d$side == "shiny"]; h = d$o200k[d$level == lv & d$side == "html"]
  sw = d$as_write_arg[d$level == lv & d$side == "shiny"]; hw = d$as_write_arg[d$level == lv & d$side == "html"]
  pairs = as.vector(outer(h, s, "/"))
  cat(sprintf("  %s shiny %6.1f  html %6.1f  ratio %.2f  pair range %.2f-%.2f | as write-call argument: ratio %.2f\n",
              lv, mean(s), mean(h), mean(h) / mean(s), min(pairs), max(pairs), mean(hw) / mean(sw)))
}
tot = aggregate(cbind(o200k, cl100k, as_write_arg) ~ side, d, sum)
print(tot, row.names = FALSE)
cat(sprintf("Overall html/shiny: o200k %.2f, cl100k %.2f, as write-call argument %.2f\n",
            tot$o200k[tot$side == "html"] / tot$o200k[tot$side == "shiny"],
            tot$cl100k[tot$side == "html"] / tot$cl100k[tot$side == "shiny"],
            tot$as_write_arg[tot$side == "html"] / tot$as_write_arg[tot$side == "shiny"]))
cat(sprintf("Tokenizer agreement: cl100k/o200k per file median %.3f (range %.3f-%.3f)\n",
            median(d$cl100k / d$o200k), min(d$cl100k / d$o200k), max(d$cl100k / d$o200k)))
cat(sprintf("JSON escaping in a write call: +%.1f%% shiny, +%.1f%% html (median over files)\n",
            100 * median(d$as_write_arg[d$side == "shiny"] / d$o200k[d$side == "shiny"] - 1),
            100 * median(d$as_write_arg[d$side == "html"] / d$o200k[d$side == "html"] - 1)))

cat("\nGrowth curve (mean o200k per side by level index 1..5; least-squares slope per level):\n")
g = aggregate(o200k ~ level + side, d, mean)
g$k = as.integer(sub("L", "", g$level))
for (sd in c("shiny", "html")) {
  gg = g[g$side == sd, ]
  fit = lm(o200k ~ k, gg)
  cat(sprintf("  %-5s %s | slope %.0f tokens/level, intercept %.0f\n", sd,
              paste(sprintf("%.0f", gg$o200k[order(gg$k)]), collapse = " -> "), coef(fit)[2], coef(fit)[1]))
}

cat("\nData transfer: what the model must emit/receive for the data (o200k)\n")
desc = function(df) paste0(deparse(substitute(df)), " <data.frame ", nrow(df), " x ", ncol(df), ">: ",
  paste(sprintf("%s %s", names(df), vapply(df, function(v) class(v)[1], "")), collapse = ", "))
show = function(label, df, name) {
  jr = j(df); jc = as.character(jsonlite::toJSON(df, dataframe = "columns", digits = NA))
  csv = paste(capture.output(write.csv(df, stdout(), row.names = FALSE)), collapse = "\n")
  ds = sprintf("%s <data.frame %d x %d>: %s", name, nrow(df), ncol(df),
               paste(sprintf("%s %s", names(df), vapply(df, function(v) class(v)[1], "")), collapse = ", "))
  cat(sprintf("  %-22s rows-JSON %7d | columns-JSON %7d | CSV %7d | name %d | name + schema line %d\n",
              label, tok_o200k(jr), tok_o200k(jc), tok_o200k(csv), tok_o200k(name), tok_o200k(ds)))
}
show("sales (5000 x 5)", sales, "sales")
show("sales[1:1000, ]", sales[1:1000, ], "sales")
show("sales[1:100, ]", sales[1:100, ], "sales")
show("cars_df (32 x 12)", cars_df, "cars_df")
show("inv_a + inv_b (16 x 3)", rbind(inv_a, inv_b), "inv_a")
big = sales[rep(seq_len(nrow(sales)), 10), ]
cat(sprintf("  %-22s rows-JSON %7d (linear in rows: %.1f tokens/row)\n", "sales x10 (50000 x 5)",
            tok_o200k(j(big)), tok_o200k(j(big)) / nrow(big)))

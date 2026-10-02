# G2 (g): output budgets: tool-result truncation, read line numbers, edit diffs, plot sizes.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
source(file.path(G2, "f_estimator.R"))
fx = readRDS(file.path(G2, "f_fit.rds"))
est = function(x, cls) estimate_tokens(x, cls, cpt = fx$cpt_ship, w_cjk = fx$w_cjk, w_other = fx$w_other_ship)
options(width = 100)
co = function(expr) paste(utils::capture.output(expr), collapse = "\n")

# ---------------- 1. truncation of large r results ----------------
set.seed(1)
big_df = data.frame(id = 1:20000, g = sample(letters, 20000, TRUE), x = rnorm(20000), y = runif(20000), d = as.Date("2020-01-01") + 1:20000)
warn_run = function() { for (i in 1:300) warning(sprintf("NAs introduced by coercion in column %d", i)) }
op = options(max.print = 99999); big_print = co(print(big_df)); options(op)
outs = list(
  `print(df) 20k rows (max.print 99999)` = big_print,
  `str(list of 400 models)` = co(str(lapply(1:400, function(i) list(coef = rnorm(3), call = "lm(y ~ x)", r2 = runif(1))))),
  `300 warnings + final error` = paste(c(vapply(1:300, function(i) sprintf("Warning in f(x): NAs introduced by coercion in column %d", i), ""), "Error in solve.default(m): Lapack routine dgesv: system is exactly singular"), collapse = "\n"),
  `summary() of 60 lm fits` = paste(vapply(1:60, function(i) co(print(summary(lm(mpg ~ wt + hp, mtcars[sample(32, 25), ])))), ""), collapse = "\n"))
trunc_pi = function(x, lines = 2000L, bytes = 51200L) {          # Pi: keep the tail
  l = strsplit(x, "\n", fixed = TRUE)[[1]]
  keep = utils::tail(l, lines)
  while (sum(nchar(keep, "bytes") + 1L) > bytes) keep = keep[-1]
  paste(c(keep, sprintf("\n[Showing lines %d-%d of %d. Full output: /tmp/pi-bash-1.log]", length(l) - length(keep) + 1L, length(l), length(l))), collapse = "\n")
}
trunc_ht = function(x, lines = 2000L, chars = 50000L) {          # report 12: head 40% + tail 60% of lines/characters
  l = strsplit(x, "\n", fixed = TRUE)[[1]]
  if (length(l) <= lines && nchar(x) <= chars) return(x)
  h = character(); t = character(); nh = 0; nt = 0
  for (s in l) { if (nh + nchar(s) + 1 > 0.4 * chars || length(h) >= 0.4 * lines) break; h = c(h, s); nh = nh + nchar(s) + 1 }
  for (s in rev(l)) { if (nt + nchar(s) + 1 > 0.6 * chars || length(t) >= 0.6 * lines) break; t = c(s, t); nt = nt + nchar(s) + 1 }
  paste(c(h, sprintf("[... %d lines omitted; full text in /tmp/gptr-output-1.txt]", length(l) - length(h) - length(t)), t), collapse = "\n")
}
trunc_tok = function(x, budget = 4000L, cls = "r_output") {      # proposed: head 40% + tail 60% of an estimated-token budget
  l = strsplit(x, "\n", fixed = TRUE)[[1]]
  lt = est(l, cls) + 1
  if (sum(lt) <= budget) return(x)
  h = which(cumsum(lt) <= 0.4 * budget); t = which(rev(cumsum(rev(lt))) <= 0.6 * budget)
  paste(c(l[h], sprintf("[... %d of %d lines omitted (~%d tokens); full text: gptr_spill(1) or /tmp/gptr-output-1.txt]", length(l) - length(h) - length(t), length(l), sum(lt) - sum(lt[c(h, t)])), l[t]), collapse = "\n")
}
cat("Large r results, o200k tokens after each truncation rule:\n")
tr_rows = list()
for (nm in names(outs)) {
  x = outs[[nm]]
  cls = if (grepl("warning", nm)) "error" else "r_output"
  tr_rows[[nm]] = data.frame(output = nm, chars = nchar(x), full = tok_o200k(x), pi_tail_2000l_50KB = tok_o200k(trunc_pi(x)),
                             head_tail_2000l_50000c = tok_o200k(trunc_ht(x)), tok_budget_8000 = tok_o200k(trunc_tok(x, 8000L, cls)),
                             tok_budget_4000 = tok_o200k(trunc_tok(x, 4000L, cls)), tok_budget_2000 = tok_o200k(trunc_tok(x, 2000L, cls)))
}
print(do.call(rbind, tr_rows), row.names = FALSE)
x = outs[["300 warnings + final error"]]
cat(sprintf("\nThe final error survives: Pi tail %s, head+tail %s, token budget 2000 %s\n",
            grepl("singular", trunc_pi(x)), grepl("singular", trunc_ht(x)), grepl("singular", trunc_tok(x, 2000L, "error"))))
x = outs[["print(df) 20k rows (max.print 99999)"]]
cat(sprintf("The column header survives: Pi tail %s, head+tail %s, token budget 4000 %s\n",
            grepl("^ +id g", trunc_pi(x)), grepl("id g", substr(trunc_ht(x), 1, 200)), grepl("id g", substr(trunc_tok(x, 4000L), 1, 200))))

# ---------------- 2. read tool with and without line numbers ----------------
rfiles = c(list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-01/proto", "\\.R$", full.names = TRUE),
           list.files(file.path(G2, "a_apps"), "\\.(R|html)$", recursive = TRUE, full.names = TRUE))
mdfiles = list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi/packages/coding-agent/docs", "\\.md$", full.names = TRUE)[1:12]
csvfile = file.path(G2, "e_proj/data/sales.csv")
num_cat = function(l) sprintf("%6d\t%s", seq_along(l), l)                 # cat -n / Claude Code Read style
num_bar = function(l) sprintf("%d|%s", seq_along(l), l)                  # compact
num_hash = function(l) sprintf("%d:%s|%s", seq_along(l), substr(vapply(l, function(s) rlang::hash(s), ""), 1, 3), l)   # btw hashline
ln_rows = list()
for (grp in c("R/HTML source", "Markdown", "CSV (first 300 lines)")) {
  fs = switch(grp, `R/HTML source` = rfiles, Markdown = mdfiles, `CSV (first 300 lines)` = csvfile)
  L = lapply(fs, function(f) { l = readLines(f, warn = FALSE); if (grepl("CSV", grp)) utils::head(l, 300) else l })
  txt = function(fun) paste(vapply(L, function(l) paste(fun(l), collapse = "\n"), ""), collapse = "\n")
  base = tok_o200k(txt(identity))
  ln_rows[[grp]] = data.frame(content = grp, files = length(fs), lines = sum(lengths(L)), plain = base,
                              cat_n = sprintf("%+.1f%%", 100 * (tok_o200k(txt(num_cat)) / base - 1)),
                              bar = sprintf("%+.1f%%", 100 * (tok_o200k(txt(num_bar)) / base - 1)),
                              hashline = sprintf("%+.1f%%", 100 * (tok_o200k(txt(num_hash)) / base - 1)))
}
cat("\nRead results with line numbers (token overhead vs plain text):\n"); print(do.call(rbind, ln_rows), row.names = FALSE)

# ---------------- 3. edit results with and without a diff ----------------
src = file.path(G2, "a_apps"); rev = file.path(G2, "a_revised")
ed_rows = list()
for (f in list.files(rev, "\\.(R|html)$", recursive = TRUE)) {
  a = file.path(src, f); b = file.path(rev, f)
  d3 = suppressWarnings(system2("diff", c("-U3", shQuote(a), shQuote(b)), stdout = TRUE))
  d0 = suppressWarnings(system2("diff", c("-U0", shQuote(a), shQuote(b)), stdout = TRUE))
  d3 = paste(d3[-(1:2)], collapse = "\n"); d0 = paste(d0[-(1:2)], collapse = "\n")
  msg = sprintf("Successfully replaced %d block(s) in %s.", 1L, f)
  ed_rows[[f]] = data.frame(file = f, message_only = tok_o200k(msg), with_diff_U0 = tok_o200k(paste(msg, d0, sep = "\n")), with_diff_U3 = tok_o200k(paste(msg, d3, sep = "\n")))
}
ed = do.call(rbind, ed_rows)
cat("\nEdit tool result for the 20 revisions of part (a) (o200k):\n")
cat(sprintf("  message only: median %.0f | + diff -U0: median %.0f (max %d) | + diff -U3: median %.0f (max %d)\n",
            median(ed$message_only), median(ed$with_diff_U0), max(ed$with_diff_U0), median(ed$with_diff_U3), max(ed$with_diff_U3)))
er = readRDS(file.path(G2, "a_rev_calls.rds"))
cat(sprintf("  for comparison, the edit CALLS themselves (model output): median %.0f tokens\n", median(er$edit_tok)))

# ---------------- 4. plot sizes ----------------
suppressPackageStartupMessages(library(ggplot2))
set.seed(4)
dd = data.frame(x = rnorm(5000), y = rnorm(5000), grp = sample(c("control", "treated", "placebo"), 5000, TRUE))
p = ggplot(dd, aes(x, y, colour = grp)) + geom_point(alpha = 0.5, size = 0.8) + labs(title = "PC1 vs PC2 by treatment group (n = 5,000)", x = "PC1 (23.4%)", y = "PC2 (11.9%)", colour = "Group") + theme_minimal()
claude = function(w, h, max_px = 1568, max_tok = 1568) {          # standard tier; Claude 4.7+/5.x: max_px 2576, max_tok 4784
  s = min(1, max_px / max(w, h))
  repeat { tk = ceiling(w * s / 28) * ceiling(h * s / 28); if (tk <= max_tok) return(tk); s = s * 0.99 }
}
gpt5 = function(w, h) ceiling(ceiling(w / 32) * ceiling(h / 32) * 1.2)
gem25 = function(w, h) if (w <= 384 && h <= 384) 258 else ceiling(w / 768) * ceiling(h / 768) * 258
pl = list()
for (sz in list(c(768, 512, 96), c(768, 512, 120), c(1000, 700, 120), c(1400, 1000, 144))) {
  f = file.path(G2, "out", sprintf("plot_%dx%d_%d.png", sz[1], sz[2], sz[3]))
  ragg::agg_png(f, width = sz[1], height = sz[2], res = sz[3]); print(p); invisible(grDevices::dev.off())
  pl[[f]] = data.frame(size = sprintf("%dx%d @%d", sz[1], sz[2], sz[3]), bytes = file.size(f), claude5x = claude(sz[1], sz[2], 2576, 4784), claude_std = claude(sz[1], sz[2]),
                       gpt5x = gpt5(sz[1], sz[2]), gemini25 = gem25(sz[1], sz[2]), gemini3_default = 1120)
}
cat("\nPlot image cost (tokens) by size; files written to out/ for visual inspection:\n"); print(do.call(rbind, pl), row.names = FALSE)
tok_save()

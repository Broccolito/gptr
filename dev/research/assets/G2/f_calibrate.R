# G2 (f): fit and evaluate the class-aware estimator on held-out chunks (tokenizer: o200k_base; cl100k shown too).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
source(file.path(G2, "f_estimator.R"))
d = readRDS(file.path(G2, "f_counts.rds"))
map = c(print_df = "r_output", print_tibble = "r_output", summary_lm = "r_output", print_misc = "r_output",
        str = "str", errors = "error", json = "json", csv = "csv", r_code = "code", markdown = "prose",
        cjk = "prose", cjk_mixed_output = "r_output")
d$est_class = map[d$class]
d$ascii = nchar(gsub("[^\\x01-\\x7F]", "", d$text, perl = TRUE), "chars")
d$cjk = d$chars - nchar(gsub(.cjk_rx, "", d$text, perl = TRUE), "chars")
d$other = d$chars - d$ascii - d$cjk
set.seed(9)
d$train = as.logical(ave(seq_len(nrow(d)), d$class, FUN = function(i) sample(rep_len(c(1, 0), length(i)))))

cat("Corpora (all chunks): chars per o200k token and chars/4 bias, per corpus class\n")
s = aggregate(cbind(chars, o200k, cl100k, cjk, other) ~ class, d, sum)
s$n = as.vector(table(d$class)[s$class])
s$cpt_o200k = round(s$chars / s$o200k, 2); s$cpt_cl100k = round(s$chars / s$cl100k, 2)
s$chars4_err = sprintf("%+.1f%%", 100 * (s$chars / 4 - s$o200k) / s$o200k)
s$chars2_err = sprintf("%+.1f%%", 100 * (s$chars / 2 - s$o200k) / s$o200k)
print(s[order(s$cpt_o200k), c("class", "n", "chars", "o200k", "cl100k", "cpt_o200k", "cpt_cl100k", "chars4_err", "chars2_err")], row.names = FALSE)
cat(sprintf("Total: %d chunks, %d chars, %d o200k tokens (report 21 section 2.8 had 9,959 chars of printed R output; here %d)\n\n",
            nrow(d), sum(d$chars), sum(d$o200k), sum(d$chars[d$est_class %in% c("r_output", "str")])))

# ---- fit on the training half, in two stages (ratio of sums, so class totals are unbiased) ----
tr = d[d$train, ]
pure = tr$cjk + tr$other < 0.01 * tr$chars
cpt = with(tr[pure, ], round(tapply(ascii, est_class, sum) / tapply(o200k, est_class, sum), 2))
res = function(k) with(tr[k, ], o200k - ascii / cpt[est_class])
k_cjk = tr$cjk > 0.2 * tr$chars
w_cjk = round(sum(res(k_cjk)) / sum(tr$cjk[k_cjk]), 3)
k_oth = tr$other > 0 & tr$cjk == 0
w_other = round(sum(res(k_oth)) / sum(tr$other[k_oth]), 3)
# conservative variant that gptr ships: r_output from table-like prints only (print_df, tibble, misc),
# which are denser than summary() output, and a non-ASCII weight floored at 0.35 (report 21: Cyrillic
# 0.30, German 0.27 tokens/char under o200k; the corpus here has almost no non-CJK non-ASCII text)
w_other_ship = max(w_other, 0.35)
kt = tr$class %in% c("print_df", "print_tibble", "print_misc")
cpt_ship = cpt
cpt_ship["r_output"] = round(sum(tr$ascii[kt]) / sum(tr$o200k[kt] - w_other_ship * tr$other[kt] - w_cjk * tr$cjk[kt]), 2)
cat("Fitted chars-per-token by estimator class (training half):\n"); print(cpt)
cat("Shipped (conservative) constants:\n"); print(cpt_ship)
cat(sprintf("Fitted weights: CJK %.3f tokens/char, other non-ASCII %.3f tokens/char\n\n", w_cjk, w_other))

# ---- evaluate on the held-out half ----
te = d[!d$train, ]
rule21 = function(x, cls) {                       # report 21's rule: chars/4 prose+code, chars/2 tool results, CJK 1/char
  n = nchar(x, "chars"); cj = n - nchar(gsub(.cjk_rx, "", x, perl = TRUE), "chars")
  ceiling((n - cj) / ifelse(cls %in% c("prose", "code"), 4, 2) + cj)
}
ests = list(`chars/4` = ceiling(te$chars / 4), `chars/2` = ceiling(te$chars / 2), `report 21 rule` = rule21(te$text, te$est_class),
            `G2 class known` = estimate_tokens(te$text, te$est_class, cpt = cpt, w_cjk = w_cjk, w_other = w_other),
            `G2 auto-detect` = estimate_tokens(te$text, "auto", cpt = cpt, w_cjk = w_cjk, w_other = w_other),
            `G2 shipped, class known` = estimate_tokens(te$text, te$est_class, cpt = cpt_ship, w_cjk = w_cjk, w_other = w_other_ship),
            `G2 shipped, auto` = estimate_tokens(te$text, "auto", cpt = cpt_ship, w_cjk = w_cjk, w_other = w_other_ship))
err_tab = function(truth, lab) {
  do.call(rbind, lapply(names(ests), function(k) {
    e = (ests[[k]] - truth) / truth
    data.frame(estimator = k, median_abs = sprintf("%.1f%%", 100 * median(abs(e))), p90_abs = sprintf("%.1f%%", 100 * quantile(abs(e), 0.9)),
               under_20pct = sprintf("%.0f%%", 100 * mean(e < -0.2)), total_bias = sprintf("%+.1f%%", 100 * (sum(ests[[k]]) - sum(truth)) / sum(truth)))
  }))
}
cat("Held-out chunks (n =", nrow(te), "), error vs o200k_base:\n"); print(err_tab(te$o200k), row.names = FALSE)
cat("\nSame estimators vs cl100k_base (constants were fitted on o200k):\n"); print(err_tab(te$cl100k), row.names = FALSE)
cat("\nPer class, held-out total bias vs o200k (class known | auto | chars/4 | report 21 rule):\n")
for (k in unique(te$class)) {
  i = te$class == k
  b = function(v) sprintf("%+6.1f%%", 100 * (sum(v[i]) - sum(te$o200k[i])) / sum(te$o200k[i]))
  cat(sprintf("  %-17s %s | %s | %s | %s | shipped %s\n", k, b(ests$`G2 class known`), b(ests$`G2 auto-detect`), b(ests$`chars/4`), b(ests$`report 21 rule`), b(ests$`G2 shipped, class known`)))
}
det = vapply(te$text, detect_class, "", USE.NAMES = FALSE)
cat(sprintf("\nAuto-detect agreement with the true estimator class: %.0f%%\n", 100 * mean(det == te$est_class)))
print(table(true = te$est_class, detected = det))
tm = system.time(for (r in 1:20) estimate_tokens(d$text, d$est_class, cpt = cpt))[["elapsed"]] / 20
cat(sprintf("\nSpeed: estimate_tokens() on all %d chunks (%.2f MB) takes %.1f ms; rtiktoken o200k on one 4 KB chunk takes %.0f ms\n",
            nrow(d), sum(nchar(d$text, "bytes")) / 1e6, 1000 * tm, 1000 * system.time(rtiktoken::get_token_count(d$text[1], "o200k_base"))[["elapsed"]]))
saveRDS(list(cpt = cpt, w_cjk = w_cjk, w_other = w_other, cpt_ship = cpt_ship, w_other_ship = w_other_ship), file.path(G2, "f_fit.rds"))

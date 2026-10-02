# G2 (f): does a character-feature model beat class ratios? Same train/test split as f_calibrate.R.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
source(file.path(G2, "f_estimator.R"))
d = readRDS(file.path(G2, "f_counts.rds"))
map = c(print_df = "r_output", print_tibble = "r_output", summary_lm = "r_output", print_misc = "r_output", str = "str",
        errors = "error", json = "json", csv = "csv", r_code = "code", markdown = "prose", cjk = "prose", cjk_mixed_output = "r_output")
d$est_class = map[d$class]
set.seed(9)
d$train = as.logical(ave(seq_len(nrow(d)), d$class, FUN = function(i) sample(rep_len(c(1, 0), length(i)))))
cnt = function(x, rx) nchar(x, "chars") - nchar(gsub(rx, "", x, perl = TRUE), "chars")
feat = function(x) cbind(letters = cnt(x, "[A-Za-z]"), digits = cnt(x, "[0-9]"), punct = cnt(x, "[!-/:-@\\[-`{-~]"),
                         wsrun = cnt(x, "(?<![ \\t]) "), newline = cnt(x, "\n"), cjk = cnt(x, .cjk_rx),
                         other = cnt(x, "[^\\x00-\\x7F]") - cnt(x, .cjk_rx))
F = feat(d$text)
tr = d$train; te = !d$train
fit = lm.fit(F[tr, ], d$o200k[tr])
cat("Universal feature model (tokens per character class):\n"); print(round(fit$coefficients, 3))
pred_u = ceiling(drop(F[te, ] %*% fit$coefficients))
# class-specific feature model: one coefficient vector per estimator class (letters, digits, punct, wsrun)
pred_c = numeric(sum(te))
coefs = list()
for (k in unique(d$est_class)) {
  i = tr & d$est_class == k
  cols = c("letters", "digits", "punct", "wsrun", "newline")
  f = lm.fit(F[i, cols, drop = FALSE], d$o200k[i] - 0.848 * F[i, "cjk"] - 0.35 * F[i, "other"])
  coefs[[k]] = f$coefficients
  j = d$est_class[te] == k
  pred_c[j] = ceiling(drop(F[te, cols, drop = FALSE][j, , drop = FALSE] %*% f$coefficients) + 0.848 * F[te, "cjk"][j] + 0.35 * F[te, "other"][j])
}
fx = readRDS(file.path(G2, "f_fit.rds"))
pred_r = estimate_tokens(d$text[te], d$est_class[te], cpt = fx$cpt_ship, w_cjk = fx$w_cjk, w_other = fx$w_other_ship)
truth = d$o200k[te]
show = function(lab, p) {
  e = (p - truth) / truth
  cat(sprintf("  %-34s median |err| %5.1f%%  p90 %5.1f%%  bias %+5.1f%%  | r_output-class median |err| %5.1f%%\n", lab,
              100 * median(abs(e)), 100 * quantile(abs(e), .9), 100 * (sum(p) - sum(truth)) / sum(truth),
              100 * median(abs(e[d$est_class[te] == "r_output"]))))
}
cat("\nHeld-out error vs o200k:\n")
show("class ratio (shipped constants)", pred_r)
show("universal feature model", pred_u)
show("class-specific feature model", pred_c)
cat("\nClass-specific coefficients (tokens per letter, digit, punct, space-run start, newline):\n")
print(round(do.call(rbind, coefs), 3))
tm = system.time(for (r in 1:10) feat(d$text))[["elapsed"]] / 10
cat(sprintf("\nFeature extraction for %d chunks: %.0f ms (class ratio: see f_calibrate.txt)\n", nrow(d), 1000 * tm))

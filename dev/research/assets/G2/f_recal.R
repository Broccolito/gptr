# G2 (f): per-session recalibration from provider-reported usage, replayed over the golden transcripts.
# Before request k gptr predicts its input size as
#   input_(k-1) + output_(k-1)            (both exact, from the previous response's usage)
#   + m * estimate_tokens(new messages)   (tool results and user text added since then)
# and after the response it updates m from the observed delta. "Provider" token counts are simulated:
# o200k (OpenAI-like), cl100k (a second real tokenizer) and 1.35 x o200k with +-8% per-message noise
# (a Claude-5.x-like tokenizer; Anthropic: "approximately 30% more tokens" than its previous tokenizer).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
source(file.path(G2, "f_estimator.R"))
fx = readRDS(file.path(G2, "f_fit.rds"))
TR = readRDS(file.path(G2, "d_transcripts.rds"))$TR
new_msgs = function(t) {                      # the non-assistant messages, each with text and a class
  out = list()
  for (i in seq_along(t$messages)) {
    m = t$messages[[i]]
    if (m$role == "assistant") { out[[length(out) + 1]] = list(boundary = TRUE); next }
    for (b in m$content) {
      if (identical(b$type, "text")) out[[length(out) + 1]] = list(text = b$text, class = "prose")
      else out[[length(out) + 1]] = list(text = b$content, class = if (grepl("^\\s*[{\\[]", b$content)) "json" else "r_output")
    }
  }
  out
}
update_m = function(m, obs, est, alpha = 0.5) {
  if (est < 150) return(m)                                   # too little new text to learn from
  r = min(max(obs / est, 0.5), 3)
  exp((1 - alpha) * log(m) + alpha * log(r))                 # EWMA on the log ratio
}
set.seed(12)
res = list()
for (prov in c("o200k", "cl100k", "claude-like")) for (t in TR) {
  items = new_msgs(t)
  truth_of = function(x) switch(prov, o200k = tok_o200k(x), cl100k = tok_cl100k(x),
                                `claude-like` = round(1.35 * tok_o200k(x) * runif(1, 0.92, 1.08)))
  m = switch(prov, `claude-like` = 1.30, 1.00)                 # provider-family prior (see report section 4)
  m_fixed = m
  seg_true = 0; seg_est = 0; seg_c4 = 0; k = 0
  for (it in items) {
    if (isTRUE(it$boundary)) {
      if (seg_true > 0) {
        k = k + 1
        res[[length(res) + 1]] = data.frame(provider = prov, task = t$task, style = t$style, k = k, true = seg_true,
          chars4 = seg_c4, class_raw = seg_est, class_prior = seg_est * m_fixed, recal = seg_est * m)
        m = update_m(m, seg_true, seg_est)
      }
      seg_true = 0; seg_est = 0; seg_c4 = 0
      next
    }
    seg_true = seg_true + truth_of(it$text)
    seg_est = seg_est + estimate_tokens(it$text, it$class, cpt = fx$cpt_ship, w_cjk = fx$w_cjk, w_other = fx$w_other_ship)
    seg_c4 = seg_c4 + ceiling(nchar(it$text) / 4)
  }
}
d = do.call(rbind, res)
cat(sprintf("%d request deltas (new tool results and user text between two requests), %d transcripts x 3 providers\n\n", nrow(d) / 3, length(TR)))
for (prov in unique(d$provider)) {
  x = d[d$provider == prov, ]
  e = function(v) (v - x$true) / x$true
  big = x$true >= 150
  cat(sprintf("%-11s delta error (median |err|, p90 |err|, total bias) on deltas >= 150 tokens (n=%d):\n", prov, sum(big)))
  for (k in c("chars4", "class_raw", "class_prior", "recal")) {
    ee = e(x[[k]])[big]
    cat(sprintf("   %-11s %5.1f%%  %5.1f%%  %+5.1f%%\n", k, 100 * median(abs(ee)), 100 * quantile(abs(ee), 0.9), 100 * (sum(x[[k]][big]) - sum(x$true[big])) / sum(x$true[big])))
  }
}
tok_save()
# error on the whole predicted context (usage-anchored), using the transcripts' o200k context sizes
pr = readRDS(file.path(G2, "d_metrics.rds"))$per_req
pr = pr[pr$req > 1, ]
x = d[d$provider == "claude-like", ]
ctx = merge(x, transform(pr, k = req - 1L), by = c("task", "style", "k"))
rel = function(v) abs(v - ctx$true) / (ctx$input * 1.35)
cat(sprintf("\nClaude-like provider, error of the predicted full context (usage-anchored; n = %d requests):\n", nrow(ctx)))
for (k in c("chars4", "class_raw", "class_prior", "recal")) cat(sprintf("   %-11s median %.2f%%, max %.2f%%\n", k, 100 * median(rel(ctx[[k]])), 100 * max(rel(ctx[[k]]))))

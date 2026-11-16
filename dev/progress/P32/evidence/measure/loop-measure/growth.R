# Growth of per-model-request costs with transcript length: run_build (and others) vs messages so far
# Usage: Rscript --vanilla growth.R tag [fn ...]
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/loop-measure"
a = commandArgs(TRUE)
tag = a[1]
fns = if (length(a) > 1) a[-1] else c("run_build", "prompt_request_estimate", "run_response", "dispatch_call")
e = read.csv(file.path(W, "logs", tag, "events.csv"))
p = read.csv(file.path(W, "logs", tag, "phases.csv"))
msg_t = sort(e$t[grepl("^message_end:", e$type)])
for (fn in fns) {
  x = p[p$name == fn, ]
  if (!nrow(x)) next
  x$dur = x$t1 - x$t0
  x$msgs = findInterval(x$t0, msg_t)
  fit = lm(dur ~ msgs, x)
  b = coef(fit)
  bins = cut(x$msgs, breaks = c(-1, 25, 50, 100, 150, 200, 250, 300, 400, 1e6))
  tb = aggregate(cbind(dur, msgs) ~ bins, x, median)
  cat(sprintf("\n%s: n=%d  dur = %.4f s + %.3f ms/message (R2 %.2f)\n", fn, nrow(x), b[1], 1000 * b[2],
              summary(fit)$r.squared))
  print(transform(tb, dur_ms = round(1000 * dur, 1))[, c("bins", "msgs", "dur_ms")], row.names = FALSE)
}
# per-turn interval: turn_end -> next before_request, vs messages
te = e$t[e$type == "turn_end"]
br = e$t[e$type == "before_request"]
nx = sapply(te, function(t) { b = br[br > t]; if (length(b)) b[1] - t else NA })
ok = !is.na(nx) & nx < 5
m = findInterval(te[ok], msg_t)
fit = lm(nx[ok] ~ m)
cat(sprintf("\nturn_end -> next before_request: %.4f s + %.3f ms/message (n=%d, R2 %.2f)\n",
            coef(fit)[1], 1000 * coef(fit)[2], sum(ok), summary(fit)$r.squared))
q = read.csv(file.path(W, "logs", tag, "requests.csv"))
cat("total messages at end:", length(msg_t), "\n")
h = q[q$label == "history", ]
if (nrow(h)) {
  cat("history request walls (1 tool call each): first 5 / last 5:\n")
  print(round(head(h$wall, 5), 3)); print(round(tail(h$wall, 5), 3))
  fit = lm(wall ~ seq_along(wall), h)
  cat(sprintf("history wall = %.3f s + %.2f ms per prior prompt\n", coef(fit)[1], 1000 * coef(fit)[2]))
}

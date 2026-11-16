# One row per tag: per-request and per-turn medians (ms) and selected traced functions per call
# Usage: Rscript --vanilla summary.R out.csv tag1 tag2 ...
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/loop-measure"
a = commandArgs(TRUE)
out = a[1]
tags = a[-1]
med = function(x) if (length(x)) stats::median(x, na.rm = TRUE) else NA_real_
rows = list()
for (tag in tags) {
  dir = file.path(W, "logs", tag)
  if (!file.exists(file.path(dir, "requests.csv"))) next
  q = read.csv(file.path(dir, "requests.csv"))
  qm = q[q$label == "measured", ]
  e = read.csv(file.path(dir, "events.csv"))
  p = read.csv(file.path(dir, "phases.csv"))
  r = list(tag = tag, req_wall = med(qm$wall) * 1000, gc = if (!is.null(qm$gc_s)) med(qm$gc_s) * 1000 else NA)
  pr = list(); tr = list()
  for (k in qm$req) {
    er = e[e$req == k, ]
    if (!nrow(er)) next
    at = function(type) er$t[er$type == type]
    br = at("before_request"); ma = at("message_end:assistant"); ts = at("tool_execution_start")
    te = at("tool_execution_end"); tx = er$x[er$type == "tool_execution_end"]; tend = at("turn_end")
    K = length(ts); qr = qm[qm$req == k, ]
    a0 = at("agent_start")[1]; a1 = tail(at("agent_end"), 1)
    pr[[length(pr) + 1]] = c(gw_pre = a0 - qr$t0, start_req1 = br[1] - a0,
                             final = tail(tend, 1) - br[K + 1], post = qr$t1 - a1)
    if (K) {
      i = seq_len(K)
      tr[[length(tr) + 1]] = cbind(provider = ma[i] - br[i], pre_exec = ts[i] - ma[i],
        tool_outer = te[i] - ts[i], tool_internal = tx[i], post_tool = tend[i] - te[i],
        next_req = br[i + 1] - tend[i], turn = br[i + 1] - br[i])
    }
  }
  if (length(pr)) {
    pm = do.call(rbind, pr); for (n in colnames(pm)) r[[n]] = med(pm[, n]) * 1000
  }
  if (length(tr)) {
    tm = do.call(rbind, tr); for (n in colnames(tm)) r[[paste0("t_", n)]] = med(tm[, n]) * 1000
  }
  if (nrow(p)) {
    pp = p[p$req %in% qm$req, ]
    pp$dur = pp$t1 - pp$t0
    for (fn in c("run_build", "run_response", "dispatch_call", "tool_run", "call_risk", "perm_check",
                 "checkpoint_before", "session_append", "session_emit", "reactor_io", "env_view_snapshot",
                 "env_snap_size", "run_compact_check", "loop_next", "prompt_request_estimate",
                 "context_collect", "dispatch_finish", "tool_call_hook")) {
      x = pp[pp$name == fn, ]
      if (nrow(x)) {
        per_req_n = nrow(x) / length(unique(x$req))
        r[[paste0("f_", fn, "_ms")]] = 1000 * sum(x$dur) / nrow(x)
        r[[paste0("f_", fn, "_n")]] = per_req_n
      }
    }
  }
  rows[[length(rows) + 1]] = as.data.frame(r)
}
all = Reduce(function(x, y) merge(x, y, all = TRUE, sort = FALSE), rows)
write.csv(all, out, row.names = FALSE)
show = c("tag", "req_wall", "gc", "gw_pre", "start_req1", "final", "post", "t_provider", "t_pre_exec",
         "t_tool_outer", "t_tool_internal", "t_post_tool", "t_next_req", "t_turn")
show = intersect(show, names(all))
print(format(all[, show], digits = 3), row.names = FALSE)
fcols = grep("^f_.*_ms$", names(all), value = TRUE)
if (length(fcols)) {
  cat("\nper-call inclusive ms of traced functions (calls per request in the _n columns of the CSV):\n")
  print(format(all[, c("tag", fcols)], digits = 3), row.names = FALSE)
}

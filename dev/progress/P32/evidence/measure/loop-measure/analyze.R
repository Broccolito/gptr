# Summarise logs/<tag>/{events,phases,requests}.csv: per-request and per-turn harness intervals
# Usage: Rscript --vanilla analyze.R tag1 tag2 ...
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/loop-measure"
med = function(x) if (length(x)) stats::median(x) else NA_real_
one = function(tag) {
  dir = file.path(W, "logs", tag)
  e = read.csv(file.path(dir, "events.csv"))
  p = read.csv(file.path(dir, "phases.csv"))
  q = read.csv(file.path(dir, "requests.csv"))
  q = q[q$label == "measured", ]
  rows = list()
  turns = list()
  for (r in q$req) {
    er = e[e$req == r, ]
    at = function(type) er$t[er$type == type]
    br = at("before_request")
    ma = at("message_end:assistant")
    ts = at("tool_execution_start")
    te = at("tool_execution_end")
    tx = er$x[er$type == "tool_execution_end"]
    tend = at("turn_end")
    K = length(ts)
    qr = q[q$req == r, ]
    a0 = at("agent_start")[1]
    a1 = tail(at("agent_end"), 1)
    if (K > 0) {
      i = seq_len(K)
      turns[[length(turns) + 1L]] = data.frame(req = r, turn = i,
        provider = ma[i] - br[i], pre_exec = ts[i] - ma[i], tool_outer = te[i] - ts[i],
        tool_internal = tx[i], post_tool = tend[i] - te[i], next_req = br[i + 1] - tend[i],
        turn_total = br[i + 1] - br[i])
    }
    rows[[length(rows) + 1L]] = data.frame(req = r, wall = qr$wall, K = K,
      gateway_pre = a0 - qr$t0, start_to_req1 = br[1] - a0,
      loop_turns = if (K) br[K + 1] - br[1] else 0,
      final_turn = tail(at("turn_end"), 1) - br[K + 1],
      turnend_to_agentend = a1 - tail(at("turn_end"), 1),
      gateway_post = qr$t1 - a1)
  }
  rows = do.call(rbind, rows)
  turns = do.call(rbind, turns)
  pm = p[p$req %in% q$req, ]
  fsum = NULL
  if (nrow(pm)) {
    pm$dur = pm$t1 - pm$t0
    fn = aggregate(dur ~ name + req, pm, sum)
    cn = aggregate(dur ~ name + req, pm, length)
    names(cn)[3] = "n"
    fn = merge(fn, cn)
    fsum = aggregate(cbind(dur, n) ~ name, fn, med)
    fsum = fsum[order(-fsum$dur), ]
  }
  list(req = rows, turns = turns, fn = fsum)
}
for (tag in commandArgs(TRUE)) {
  x = one(tag)
  cat("\n=====", tag, "=====\n")
  cat("per request (median over measured requests, seconds):\n")
  print(round(sapply(x$req[, -1], med), 4))
  if (!is.null(x$turns)) {
    cat("per tool turn (median over all turns; mean in 2nd row):\n")
    print(round(rbind(median = sapply(x$turns[, -(1:2)], med),
                      mean = sapply(x$turns[, -(1:2)], mean)), 4))
  }
  if (!is.null(x$fn)) {
    cat("traced functions (median per request: inclusive seconds, calls):\n")
    print(head(transform(x$fn, dur = round(dur, 4)), 45), row.names = FALSE)
  }
}

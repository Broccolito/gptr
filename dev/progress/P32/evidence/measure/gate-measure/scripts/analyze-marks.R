# Per tool call: inclusive seconds and call counts per traced function, plus the phase split.
# Usage: Rscript --vanilla analyze-marks.R <marks.csv> [<marks.csv> ...]; writes <marks>-fn.csv and
# <marks>-phase.csv next to each input and prints medians by variant.
args = commandArgs(TRUE)
for (f in args) {
  m = read.csv(f, stringsAsFactors = FALSE)
  m = m[nzchar(m$req) & !startsWith(m$req, "warm"), ]
  out = list()
  ph = list()
  for (rq in unique(m$req)) {
    x = m[m$req == rq, ]
    # pair enter/exit per fn with a stack; inclusive = outermost spans only
    span = list()
    for (fn in unique(x$fn)) {
      y = x[x$fn == fn, ]
      depth = 0L; t0 = NA; tot = 0; n = 0L; first = NA; durs = numeric()
      st = numeric()
      for (i in seq_len(nrow(y))) {
        if (y$stage[i] == "enter") {
          n = n + 1L
          st = c(st, y$t[i])
          if (is.na(first)) first = y$t[i]
        } else {
          s0 = st[length(st)]; st = st[-length(st)]
          if (!length(st)) { tot = tot + (y$t[i] - s0) }
          durs = c(durs, y$t[i] - s0)
        }
      }
      callers = paste(unique(y$caller[y$stage == "enter" & nzchar(y$caller)]), collapse = " | ")
      out[[length(out) + 1L]] = data.frame(req = rq, fn = fn, calls = n, incl_s = tot,
                                           max_one_s = if (length(durs)) max(durs) else NA,
                                           callers = callers)
      span[[fn]] = list(first = first, tot = tot, durs = durs)
    }
    g = function(fn) if (is.null(span[[fn]])) 0 else span[[fn]]$tot
    tool0 = x$t[x$fn == "TOOL" & x$stage == "enter"][1]
    tool1 = x$t[x$fn == "TOOL" & x$stage == "exit"][1]
    gate0 = x$t[x$fn %in% c("mcp_serve_gate", "perm_check") & x$stage == "enter"][1]
    # risk classifications in order: the first before the gate, the second inside it
    rc = x[x$fn == "risk_classify_r", ]
    rc_d = numeric(); st = numeric()
    for (i in seq_len(nrow(rc))) if (rc$stage[i] == "enter") st = c(st, rc$t[i]) else {
      rc_d = c(rc_d, rc$t[i] - st[length(st)]); st = st[-length(st)] }
    es = x[x$fn == "env_snap_size", ]
    es_risk = 0; es_ck = 0; es_post = 0; st = numeric(); who = character()
    for (i in seq_len(nrow(es))) if (es$stage[i] == "enter") { st = c(st, es$t[i]); who = c(who, es$caller[i]) } else {
      s0 = st[length(st)]; d = es$t[i] - s0; w = who[length(who)]; st = st[-length(st)]; who = who[-length(who)]
      if (s0 > tool1) es_post = es_post + d
      else if (s0 >= tool0 && grepl("risk_binding", w)) es_risk = es_risk + d
      else if (s0 >= tool0 && grepl("env_snap_rows", w)) es_ck = es_ck + d }
    ph[[length(ph) + 1L]] = data.frame(req = rq, variant = sub("#.*", "", rq), outer = tool1 - tool0,
      pre_gate = gate0 - tool0, gate = g("mcp_serve_gate") + g("perm_check") * is.null(span[["mcp_serve_gate"]]),
      classify_1 = if (length(rc_d) >= 1) rc_d[1] else NA, classify_2 = if (length(rc_d) >= 2) rc_d[2] else NA,
      n_classify = length(rc_d), call_risk = g("call_risk"), perm_policies = g("perm_policies"),
      schema_validate = g("schema_validate") + g("tool_validate"), tool_call_hook = g("tool_call_hook"),
      env_snap_size_risk = es_risk, env_snap_size_ckpt = es_ck, env_snap_size_after_tool = es_post,
      checkpoint_before = g("checkpoint_before"), exec = g("mcp_serve_r") + g("tool_execute_frame"),
      checkpoint_after = g("checkpoint_after"), ckpt_predict = g("ckpt_predict"), env_snapshot = g("env_snapshot"),
      fingerprint = g("fingerprint"))
  }
  fnr = do.call(rbind, out)
  phr = do.call(rbind, ph)
  write.csv(fnr, sub("\\.csv$", "-fn.csv", f), row.names = FALSE)
  write.csv(phr, sub("\\.csv$", "-phase.csv", f), row.names = FALSE)
  num = setdiff(names(phr), c("req", "variant"))
  med = aggregate(phr[num], list(variant = phr$variant), median)
  cat("==", basename(f), "(medians over reps, seconds)\n")
  print(format(med, digits = 3), row.names = FALSE)
}

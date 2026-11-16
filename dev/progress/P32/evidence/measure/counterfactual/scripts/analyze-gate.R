# Medians (of the reps) per variant x code: outer / internal / gap / wall / post-tool, savings vs
# base, plus the phase split from the light trace marks. Usage: analyze-gate.R <tag> [<tag> ...]
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/counterfactual"
options(width = 220)
med = function(x) stats::median(x, na.rm = TRUE)
for (tag in commandArgs(TRUE)) {
  r = read.csv(file.path(W, "out", paste0("runs-", tag, ".csv")))
  mk = file.path(W, "out", paste0("marks-", tag, ".csv"))
  m = if (file.exists(mk)) read.csv(mk) else NULL
  ph = list()
  if (!is.null(m)) for (q in unique(m$req)) {
    x = m[m$req == q, ]
    iv = function(fn) {
      a = x$t[x$fn == fn & x$stage == "enter"]; b = x$t[x$fn == fn & x$stage == "exit"]
      n = min(length(a), length(b)); if (!n) return(matrix(numeric(), 0, 2)); cbind(a[1:n], b[1:n])
    }
    tool = iv("TOOL")
    if (!nrow(tool)) next
    t0 = tool[1, 1]; t1 = tool[1, 2]
    gate = iv(if (any(x$fn == "mcp_serve_gate")) "mcp_serve_gate" else "perm_check")
    gate = gate[gate[, 1] >= t0 & gate[, 2] <= t1, , drop = FALSE]
    g0 = if (nrow(gate)) gate[1, 1] else NA; g1 = if (nrow(gate)) gate[1, 2] else NA
    within = function(iv, a, b) { iv = iv[iv[, 1] >= a & iv[, 2] <= b, , drop = FALSE]; sum(iv[, 2] - iv[, 1]) }
    cls = iv("risk_classify_r"); sz = iv("env_snap_size"); cb = iv("checkpoint_before"); ca = iv("checkpoint_after")
    ae = iv("env_on_agent_end")
    ph[[length(ph) + 1L]] = data.frame(req = q,
      pre_gate = g0 - t0, gate = g1 - g0,
      classify_pre = within(cls, t0, g0), classify_gate = within(cls, g0, g1),
      n_classify = sum(cls[, 1] >= t0 & cls[, 2] <= t1),
      size_in_tool = within(sz, t0, t1), n_size_in_tool = sum(sz[, 1] >= t0 & sz[, 2] <= t1),
      ckpt_before = within(cb, t0, t1), ckpt_after = within(ca, t0, t1),
      size_after_tool = within(sz, t1, Inf), agent_end = within(ae, t1, Inf))
  }
  ph = if (length(ph)) do.call(rbind, ph) else NULL
  r$req = paste(r$variant, r$code, r$rep, sep = "#")
  if (!is.null(ph)) r = merge(r, ph, by = "req", all.x = TRUE, sort = FALSE)
  meas = r[r$rep >= 1 & !r$variant %in% c("warm", "create"), ]
  cols = intersect(c("wall_s", "pre_tool_s", "outer_s", "internal_s", "gap_s", "post_tool_s", "pre_gate", "gate",
           "classify_pre", "classify_gate", "n_classify", "size_in_tool", "n_size_in_tool",
           "ckpt_before", "ckpt_after", "size_after_tool", "agent_end"), names(meas))
  agg = aggregate(meas[, cols], by = list(variant = meas$variant, code = meas$code), FUN = med)
  agg$reps = aggregate(meas$outer_s, by = list(meas$variant, meas$code), FUN = length)$x
  agg$errors = aggregate(meas$is_error, by = list(meas$variant, meas$code), FUN = function(z) sum(z %in% TRUE))$x
  base = agg[agg$variant == "base", c("code", "outer_s", "gap_s", "wall_s")]
  names(base) = c("code", "outer_base", "gap_base", "wall_base")
  agg = merge(agg, base, by = "code")
  agg$save_outer = agg$outer_base - agg$outer_s
  agg$save_gap = agg$gap_base - agg$gap_s
  agg$save_wall = agg$wall_base - agg$wall_s
  agg$save_outer_pct = round(100 * agg$save_outer / agg$outer_base, 1)
  ord = unique(r$variant[r$rep >= 1])
  agg = agg[order(agg$code, match(agg$variant, ord)), ]
  cat("\n======", tag, "======\n")
  print(format(agg[, c("code", "variant", "reps", "errors", "wall_s", "outer_s", "internal_s", "gap_s",
                       "post_tool_s", "save_outer", "save_gap", "save_wall", "save_outer_pct")], digits = 3), row.names = FALSE)
  if (!is.null(ph)) {
    cat("\nphase medians (s):\n")
    print(format(agg[, c("code", "variant", intersect(c("pre_gate", "gate", "classify_pre", "classify_gate", "n_classify",
                         "size_in_tool", "n_size_in_tool", "ckpt_before", "ckpt_after", "size_after_tool",
                         "agent_end"), names(agg)))], digits = 3), row.names = FALSE)
  }
  spread = aggregate(meas[, c("outer_s", "gap_s")], by = list(variant = meas$variant, code = meas$code),
                     FUN = function(z) paste(sprintf("%.3f", sort(z)), collapse = "/"))
  cat("\nper-rep outer / gap (sorted):\n")
  print(spread[order(spread$code, match(spread$variant, ord)), ], row.names = FALSE)
  extra = r[r$variant %in% c("warm", "create") | r$rep == 0, c("variant", "code", "rep", "wall_s", "outer_s", "internal_s", "gap_s", "post_tool_s", intersect(c("ckpt_after", "size_in_tool", "size_after_tool", "agent_end"), names(r)))]
  cat("\nwarm-up / create / rep-0 rows:\n")
  print(format(extra, digits = 3), row.names = FALSE)
  cat(sprintf("\nmax RSS sampled after requests: %.2f GB; load1 range %s\n", max(r$rss_gb, na.rm = TRUE),
              if (!is.null(r$load1)) paste(range(r$load1), collapse = "-") else "n/a"))
  write.csv(agg, file.path(W, "out", paste0("summary-", tag, ".csv")), row.names = FALSE)
}

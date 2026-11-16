# Median over the 3 runs of each loop scenario x variant (per-tag medians from loop-summary.R)
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/counterfactual"
options(width = 220)
d = read.csv(file.path(W, "logs", "loop", "loop-summary.csv"))
parts = do.call(rbind, strsplit(sub("^L_", "", d$tag), "_"))
d$scenario = parts[, 1]; d$variant = parts[, 2]; d$run = as.integer(parts[, 3])
cols = intersect(c("req_wall", "gc", "gw_pre", "start_req1", "final", "post", "t_provider", "t_pre_exec",
                   "t_tool_outer", "t_tool_internal", "t_post_tool", "t_next_req", "t_turn"), names(d))
agg = aggregate(d[, cols], by = list(scenario = d$scenario, variant = d$variant), FUN = median)
agg$runs = aggregate(d$run, by = list(d$scenario, d$variant), FUN = length)$x
base = agg[agg$variant == "none", c("scenario", "t_turn", "req_wall")]
names(base) = c("scenario", "turn_none", "wall_none")
agg = merge(agg, base, by = "scenario")
agg$save_turn_ms = agg$turn_none - agg$t_turn
agg$save_req_ms = agg$wall_none - agg$req_wall
agg$save_turn_pct = round(100 * agg$save_turn_ms / agg$turn_none, 1)
ord = c("none", "lm", "reactor", "loop", "all")
agg = agg[order(agg$scenario, match(agg$variant, ord)), ]
cat("medians over runs (ms); per-turn columns are medians over the turns of the measured requests\n")
print(format(agg[, c("scenario", "variant", "runs", "req_wall", "t_turn", "t_provider", "t_pre_exec", "t_tool_outer",
                     "t_tool_internal", "t_post_tool", "t_next_req", "gc", "save_turn_ms", "save_turn_pct", "save_req_ms")],
             digits = 4), row.names = FALSE)
sp = aggregate(d[, c("t_turn", "req_wall")], by = list(scenario = d$scenario, variant = d$variant),
               FUN = function(z) paste(round(sort(z)), collapse = "/"))
cat("\nper-run t_turn / req_wall (sorted):\n")
print(sp[order(sp$scenario, match(sp$variant, ord)), ], row.names = FALSE)
write.csv(agg, file.path(W, "out", "summary-loop.csv"), row.names = FALSE)

# G2 prototype: token accounting, budgets that stop with classed conditions, and the offline
# token-efficiency benchmark (golden transcripts replayed through a fake provider; pure R, no tokenizer).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
source(file.path(G2, "f_estimator.R"))
fx = readRDS(file.path(G2, "f_fit.rds"))
GPTR_CPT = fx$cpt_ship; GPTR_W_NONASCII = fx$w_other_ship; GPTR_W_CJK = fx$w_cjk

# ---- conditions (dev/plan/00-conventions.md section 5) ----
gptr_abort = function(message, class, ..., call = NULL) {
  stop(structure(class = c(paste0("gptr_error_", class), "gptr_error", "error", "condition"),
                 list(message = message, call = call, ...)))
}
gptr_warn = function(message, class, ...) {
  warning(structure(class = c(paste0("gptr_warning_", class), "gptr_warning", "warning", "condition"),
                    list(message = message, call = NULL, ...)))
}

# ---- usage records: one row per provider request (INFRA-20 fields) ----
usage_record = function(session, agent, provider, model, route, input, output, cache_read = 0, cache_write_5m = 0,
                        cache_write_1h = 0, reasoning = 0, price = NULL, est = NULL) {
  cost = if (is.null(price)) NA_real_ else (input * price$i + output * price$o + cache_read * price$read +
                                           cache_write_5m * 1.25 * price$i + cache_write_1h * 2 * price$i) / 1e6
  data.frame(time = Sys.time(), session, agent, provider, model, route, input, output, cache_read, cache_write_5m,
             cache_write_1h, reasoning, cost, est_prefix = est$prefix %||% NA, est_history = est$history %||% NA,
             est_new = est$new %||% NA)
}

# ---- budgets ----
gptr_budget = function(max_tokens = Inf, max_turns = Inf, max_cost = Inf, max_context = Inf, warn_at = 0.8) {
  structure(list(max_tokens = max_tokens, max_turns = max_turns, max_cost = max_cost, max_context = max_context, warn_at = warn_at), class = "gptr_budget")
}
# called BEFORE each request with the projected size of that request and the usage so far
budget_check = function(b, usage, projected_input) {
  used_tok = sum(usage$input + usage$cache_read + usage$cache_write_5m + usage$cache_write_1h + usage$output)
  used_cost = sum(usage$cost, na.rm = TRUE)
  turns = nrow(usage)
  if (turns >= b$max_turns) gptr_abort(sprintf("Turn budget reached: %d of %d requests.", turns, b$max_turns), "budget_turns", used = turns, limit = b$max_turns)
  if (used_tok + projected_input > b$max_tokens) gptr_abort(sprintf("Token budget: %s used + %s for the next request would exceed %s.", format(used_tok, big.mark = ","), format(projected_input, big.mark = ","), format(b$max_tokens, big.mark = ",")), "budget_tokens", used = used_tok, next_request = projected_input, limit = b$max_tokens)
  if (used_cost >= b$max_cost) gptr_abort(sprintf("Cost budget reached: $%.4f of $%.4f.", used_cost, b$max_cost), "budget_cost", used = used_cost, limit = b$max_cost)
  if (projected_input > b$max_context) gptr_abort(sprintf("Context budget: next request ~%s tokens > %s; compact or fork.", format(projected_input, big.mark = ","), format(b$max_context, big.mark = ",")), "budget_context", next_request = projected_input, limit = b$max_context)
  if (used_tok + projected_input > b$warn_at * b$max_tokens) gptr_warn(sprintf("%.0f%% of the token budget used.", 100 * (used_tok + projected_input) / b$max_tokens), "budget_near")
  invisible(TRUE)
}

# ---- per-section estimates of a request (what gptr can compute before sending) ----
msg_text = function(m) vapply(m$content, function(b) switch(b$type, text = b$text, tool_use = j(b$input), tool_result = b$content, ""), "")
msg_class = function(m) vapply(m$content, function(b) switch(b$type, text = "prose", tool_use = "code",
                        tool_result = if (grepl("^\\s*[{\\[]", b$content)) "json" else "r_output", "prose"), "")
img_tokens = function(m) sum(vapply(m$content, function(b) if (identical(b$type, "tool_result") && length(b$images)) sum(vapply(b$images, function(wh) ceiling(wh[1] / 28) * ceiling(wh[2] / 28), 1)) else 0, 1))
est_msg = function(m) sum(estimate_tokens(msg_text(m), msg_class(m))) + img_tokens(m) + 8L * length(m$content)   # + per-block JSON wrapper
prefix_est = function(tools, system) sum(estimate_tokens(c(system, j(lapply(tools, function(t) list(name = t$name, description = t$description, input_schema = t$parameters)))), c("prose", "json")))

# ---- fake provider: replays a golden transcript; its "usage" is the estimator's count (deterministic) ----
replay = function(tr, tools, system, budget = gptr_budget(), price = list(i = 2, o = 10, read = 0.2)) {
  pre = prefix_est(tools, system)
  usage = usage_record("s", "main", "fake", "fake-1", "api", 0, 0)[0, ]
  hist = 0; prev_input = 0
  for (i in seq_along(tr$messages)) {
    m = tr$messages[[i]]
    if (m$role != "assistant") { hist = hist + est_msg(m); next }
    projected = pre + hist
    budget_check(budget, usage, projected)
    out = est_msg(m)
    rd = if (prev_input >= 512) prev_input else 0
    usage = rbind(usage, usage_record("s", "main", "fake", "fake-1", "api", input = projected - rd, output = out, cache_read = rd,
                                      price = price, est = list(prefix = pre, history = hist, new = 0)))
    prev_input = projected
    hist = hist + out
  }
  usage
}

# ---- the benchmark: metrics per golden transcript, compared with a stored baseline ----
bench_tokens = function(transcripts, tools, system) {
  do.call(rbind, lapply(transcripts, function(tr) {
    u = replay(tr, tools, system)
    data.frame(case = sprintf("task%d_%s", tr$task, tr$style), requests = nrow(u), prefix = prefix_est(tools, system),
               input_total = sum(u$input + u$cache_read), output_total = sum(u$output), cost_cached = round(sum(u$cost), 5))
  }))
}
bench_compare = function(res, baseline, tol = c(prefix = 0.02, input_total = 0.05, output_total = 0.05, requests = 0, cost_cached = 0.05)) {
  b = baseline[match(res$case, baseline$case), ]
  bad = list()
  for (k in names(tol)) {
    over = res[[k]] > b[[k]] * (1 + tol[[k]])
    if (any(over, na.rm = TRUE)) bad[[k]] = sprintf("%s: %s %s -> %s (+%.1f%%, tolerance %.0f%%)", res$case[over], k, b[[k]][over], res[[k]][over], 100 * (res[[k]][over] / b[[k]][over] - 1), 100 * tol[[k]])
  }
  if (length(bad)) gptr_abort(paste(c("Token-efficiency regression:", unlist(bad)), collapse = "\n  "), "token_regression", details = bad)
  invisible(TRUE)
}

TR = readRDS(file.path(G2, "d_transcripts.rds"))$TR
tools7 = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")]
sys7 = gptr_prompt(names(tools7))
t0 = Sys.time()
base = bench_tokens(TR, tools7, sys7)
cat(sprintf("Baseline over %d golden transcripts computed in %.2f s (pure R, no tokenizer):\n", length(TR), as.numeric(Sys.time() - t0, units = "secs")))
print(base, row.names = FALSE)
jsonlite::write_json(base, file.path(G2, "out/bench_baseline.json"), dataframe = "rows", digits = NA, pretty = TRUE)
base = jsonlite::read_json(file.path(G2, "out/bench_baseline.json"), simplifyVector = TRUE)
cat("\n1) unchanged harness:", tryCatch(bench_compare(bench_tokens(TR, tools7, sys7), base), error = function(e) conditionMessage(e)), "\n")
fat = tools7; fat$r$description = paste(fat$r$description, strrep("Always explain your reasoning in detail before running code. ", 12))
r2 = tryCatch(bench_compare(bench_tokens(TR, fat, sys7), base), gptr_error_token_regression = function(e) e)
cat("\n2) r tool description grew by 12 sentences -> condition class:", paste(class(r2), collapse = ", "), "\n", substr(conditionMessage(r2), 1, 600), "\n")
cat("\n3) budgets during a replay of task 6 (style S):\n")
for (b in list(gptr_budget(max_tokens = 40000), gptr_budget(max_turns = 5), gptr_budget(max_context = 3500), gptr_budget(max_cost = 0.03))) {
  r = withCallingHandlers(tryCatch({ replay(TR[[12]], tools7, sys7, budget = b); "completed" }, gptr_error = function(e) paste0("[", class(e)[1], "] ", conditionMessage(e))),
                          gptr_warning_budget_near = function(w) invokeRestart("muffleWarning"))
  cat("  ", r, "\n")
}
u = replay(TR[[12]], tools7, sys7)
cat(sprintf("\nUsage records (task 6 S, fake provider): %d rows; columns: %s\n", nrow(u), paste(names(u), collapse = ", ")))
print(utils::head(u[, c("input", "output", "cache_read", "cost", "est_prefix")], 4), row.names = FALSE)

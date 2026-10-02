.libPaths(c("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib", .libPaths()))
tk = function(f) { x = paste(readLines(f, warn = FALSE), collapse = "\n"); length(rtiktoken::get_tokens(x, "o200k_base")) }
fs = c("tools_min.txt", "rules_min_extra.txt", "mode_manual.txt", "mode_plan.txt", "env_block.txt", "ws_block.txt")
r = vapply(fs, tk, integer(1)); print(r)
min_t0 = tk("preamble_min.txt") + r[["tools_min.txt"]] + tk("rules.txt") + r[["rules_min_extra.txt"]] + tk("modes.txt") + tk("context.txt")
cat("minimal T0:", min_t0, " + tools_min.json", tk("tools_min.json"), "=", min_t0 + tk("tools_min.json"), "\n")
std_noask_t0 = tk("preamble.txt") + r[["tools_min.txt"]] + tk("rules.txt") + tk("r_session.txt") + tk("r_performance.txt") + tk("modes.txt") + tk("context.txt")
cat("standard T0 core (no documents/artifacts/system1, no ask):", std_noask_t0, "\n")

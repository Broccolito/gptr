.libPaths(c("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib", .libPaths()))
tk = function(f) { x = paste(readLines(f, warn = FALSE), collapse = "\n"); length(rtiktoken::get_tokens(x, "o200k_base")) }
fs = c("preamble.txt", "preamble_min.txt", "tools.txt", "rules.txt", "r_session.txt", "r_performance.txt",
       "documents.txt", "artifacts.txt", "system1.txt", "modes.txt", "context.txt", "skills_hdr.txt", "mcp_hdr.txt",
       "tools_min.json", "tools_std.json", "tool_ask.json", "tool_r.json")
res = vapply(fs, tk, integer(1))
print(res)
std_t0 = sum(res[c("preamble.txt", "tools.txt", "rules.txt", "r_session.txt", "r_performance.txt", "documents.txt", "artifacts.txt", "system1.txt", "modes.txt", "context.txt")])
cat("standard T0 (all sections):", std_t0, "\n")
min_t0 = sum(res[c("preamble_min.txt", "tools.txt", "rules.txt", "modes.txt", "context.txt")])
cat("minimal T0 approx:", min_t0, "\n")

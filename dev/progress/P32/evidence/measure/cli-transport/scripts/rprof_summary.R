a = commandArgs(TRUE)
s = summaryRprof(a[[1]], memory = "none")
tt = s$by.total
cat("sampling.time:", s$sampling.time, "\n")
pat = "env_|ckpt|risk|perm_|pcli_|reactor_|json_|mcp_|stream_|run_|checkpoint|object.size|serialize|size|proc_|later|poll|Sys.sleep|tool_|redact|session_|describe"
keep = tt[grepl(pat, rownames(tt)), ]
print(utils::head(keep[order(-keep$total.time), ], 70))

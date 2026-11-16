# What-if timing of T03 requests 2 and 3 (recorded tool inputs) per counterfactual variant.
# Env: N, ROUTE (mcp|native), VARIANTS (comma list), REPS, MARKS (1 = light trace() phase marks)
N = as.integer(Sys.getenv("N", "1231"))
ROUTE = Sys.getenv("ROUTE", "mcp")
REPS = as.integer(Sys.getenv("REPS", "3"))
MARKS = Sys.getenv("MARKS", "1") == "1"
TAG = paste0("gate-", ROUTE, "-", N, if (!MARKS) "-nomarks", Sys.getenv("SUFFIX"))
source("/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/counterfactual/scripts/workload.R")
VARIANTS = strsplit(Sys.getenv("VARIANTS", "base,reuse,cache,bound,skip,share,loop,all"), ",")[[1]]

# ---- light phase marks: enter/exit of a few functions (outermost only) -----------------------------
P = new.env()
P$k = 0L; P$fn = P$req = character(2e5); P$t = numeric(2e5); P$stage = character(2e5)
P$depth = list(); P$cur = ""
mark = function(fn, stage) {
  d = P$depth[[fn]] %||% 0L
  if (stage == "enter") { P$depth[[fn]] = d + 1L; if (d > 0L) return(invisible()) }
  else { P$depth[[fn]] = d - 1L; if (d > 1L) return(invisible()) }
  k = P$k + 1L; P$k = k
  P$fn[k] = fn; P$stage[k] = stage; P$t[k] = clock(); P$req[k] = P$cur
}
assign("mark", mark, envir = globalenv())
fns = c("risk_classify_r", "env_snap_size", "mcp_serve_gate", "perm_check", "checkpoint_before",
        "checkpoint_after", "env_on_agent_end", "context_collect", "tool_call_hook")
if (MARKS) for (fn in fns) {
  suppressMessages(trace(fn, where = ns, print = FALSE,
    tracer = substitute(get("mark", globalenv())(FN, "enter"), list(FN = fn)),
    exit = substitute(get("mark", globalenv())(FN, "exit"), list(FN = fn))))
}

# ---- hooks and provider -----------------------------------------------------------------------------
S = new.env()
S$code = "invisible(0)"; S$id = 0L; S$pending = FALSE
S$prof = ""
gptr_register(gptr_hook("tool_execution_start", function(event, ctx) {
  if (nzchar(S$prof)) utils::Rprof(S$prof, interval = 0.005)
  S$t_start = clock(); mark("TOOL", "enter"); NULL
}))
gptr_register(gptr_hook("tool_execution_end", function(event, ctx) {
  S$t_end = clock(); mark("TOOL", "exit")
  if (nzchar(S$prof)) utils::Rprof(NULL)
  S$internal = event$elapsed; S$is_error = isTRUE(event$is_error)
  S$refused = paste(event$refused %||% "", collapse = " ")
  S$text = substr(paste(vapply(event$content %||% list(), function(b) b$text %||% "", ""),
                        collapse = " "), 1, 200)
  NULL
}))
if (ROUTE == "mcp") {
  gptr_register(gptr_hook("before_request", function(event, ctx) {
    if (!isTRUE(S$pending)) return(NULL)
    S$pending = FALSE
    S$id = S$id + 1L
    res = get("mcp_dispatch_local", ns)(list(jsonrpc = "2.0", id = S$id, method = "tools/call",
      params = list(name = "r", arguments = list(code = S$code))), ctx$session)
    S$rpc_error = !is.null(res$error) || isTRUE(res$result$isError)
    NULL
  }))
  script = list("Recorded tool call completed offline.")
} else {
  script = function(req) {
    if (!isTRUE(S$pending)) return("Recorded tool call completed offline.")
    S$pending = FALSE
    S$id = S$id + 1L
    list(tool = "r", input = list(code = S$code), id = paste0("call_", S$id))
  }
}
fake = gptr_fake_provider(script, name = "counterfactual")
home = new.env(parent = globalenv())
s = peter("start", model = fake, mode = "auto", tools = "minimal", envir = home, .run = FALSE)

rows = list()
one = function(variant, label, code, rep) {
  set_variant(if (variant %in% c("warm", "create")) "base" else variant)
  S$code = code; S$pending = TRUE
  S$t_start = S$t_end = S$internal = NA; S$is_error = NA; S$refused = ""
  P$cur = paste(variant, label, rep, sep = "#")
  S$prof = if (Sys.getenv("RPROF") == "1" && rep >= 1L) file.path(OUT, sprintf("rprof-%s-%s-%s-%d.out", TAG, variant, label, rep)) else ""
  invisible(gc())
  t0 = clock()
  peter(s, prompt = paste("request", variant, label, rep))
  t1 = clock()
  row = data.frame(route = ROUTE, n = N, variant = variant, code = label, rep = rep,
                   wall_s = t1 - t0, pre_tool_s = S$t_start - t0, outer_s = S$t_end - S$t_start,
                   internal_s = S$internal, gap_s = S$t_end - S$t_start - S$internal,
                   post_tool_s = t1 - S$t_end, is_error = S$is_error, refused = S$refused,
                   rss_gb = rss_gb(), load1 = as.numeric(strsplit(system("sysctl -n vm.loadavg", intern = TRUE), " ")[[1]][2]))
  rows[[length(rows) + 1L]] <<- row
  write.csv(do.call(rbind, rows), file.path(OUT, paste0("runs-", TAG, ".csv")), row.names = FALSE)
  if (MARKS) {
    k = P$k
    write.csv(data.frame(req = P$req[1:k], fn = P$fn[1:k], stage = P$stage[1:k], t = P$t[1:k]),
              file.path(OUT, paste0("marks-", TAG, ".csv")), row.names = FALSE)
  }
  print(row[, c("variant", "code", "rep", "wall_s", "outer_s", "internal_s", "gap_s", "post_tool_s", "is_error", "rss_gb")], row.names = FALSE)
  if (isTRUE(S$is_error)) cat("  error text:", S$text, "\n")
  flush.console()
}
one("warm", "w", "invisible(0)", 1L)
one("warm", "w", "invisible(0)", 2L)
one("create", "c1", code1, 1L)
cat(sprintf("home: %s\n", paste(ls(home), collapse = ", ")))
for (v in VARIANTS) one(v, "a2", code2, 0L)
for (r in seq_len(REPS)) for (v in VARIANTS) {
  one(v, "a2", code2, r)
  one(v, "a3", code3, r)
}
setwd(W)
unlink(work, recursive = TRUE)
cat("DONE\n")

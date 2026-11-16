# Step 1 decomposed: the minimal replay (4M synthetic IDs, dead `x = NULL` branch) with trace()
# markers; prints per-function inclusive seconds and call counts inside the one tool call.
# Env: CODE_VARIANT = recorded (default) | nofallback
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/gate-measure"
work = tempfile("gptr-minimal-", tmpdir = file.path(W, "tmp")); dir.create(work, recursive = TRUE); setwd(work)
Sys.setenv(R_USER_CONFIG_DIR = work, R_USER_DATA_DIR = work, R_USER_CACHE_DIR = work, GPTR_PROJECT_ROOT = work)
if (Sys.getenv("LIB") == "installed") library(gptr, lib.loc = file.path(W, "lib")) else pkgload::load_all("/Users/wgu/Desktop/gptr", quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
ns = asNamespace("gptr")
clock = function() as.numeric(proc.time()[["elapsed"]])
M = new.env(); M$x = list()
assign("mk", function(fn, st) M$x[[length(M$x) + 1L]] = data.frame(fn = fn, st = st, t = clock()), envir = globalenv())
fns = c("mcp_serve_exec", "risk_classify_r", "env_snap_size", "tool_call_hook", "mcp_serve_gate", "call_risk",
        "perm_policies", "checkpoint_before", "mcp_serve_r", "checkpoint_after")
for (fn in fns) suppressMessages(trace(fn, where = ns, print = FALSE,
  tracer = substitute(get("mk", globalenv())(FN, "in"), list(FN = fn)),
  exit = substitute(get("mk", globalenv())(FN, "out"), list(FN = fn))))
home = new.env()
home$x = sprintf("gene_%08d", seq_len(4000000))
code = if (Sys.getenv("CODE_VARIANT") == "nofallback") 'sum(nchar(gsub("[0-9]", "", x)))' else
  'if (!exists("x")) x = NULL; sum(nchar(gsub("[0-9]", "", x)))'
s = peter("Strip digits", model = gptr_fake_provider("Done"), envir = home, mode = "auto", tools = "minimal", .run = FALSE)
out = new.env()
gptr_on(s, "tool_execution_start", function(event, ctx) { out$t0 = clock(); mk("TOOL", "in") })
gptr_on(s, "tool_execution_end", function(event, ctx) { mk("TOOL", "out"); out$outer = clock() - out$t0; out$internal = event$elapsed })
gptr_on(s, "before_request", function(event, ctx) {
  gptr:::mcp_dispatch_local(list(jsonrpc = "2.0", id = 1L, method = "tools/call",
    params = list(name = "r", arguments = list(code = code))), ctx$session)
  NULL
})
invisible(gptr_wait(s))
x = do.call(rbind, M$x)
t0 = x$t[x$fn == "TOOL" & x$st == "in"][1]; t1 = x$t[x$fn == "TOOL" & x$st == "out"][1]
x = x[x$t >= t0 & x$t <= t1, ]
r = do.call(rbind, lapply(unique(x$fn), function(f) {
  y = x[x$fn == f, ]
  data.frame(fn = f, calls = sum(y$st == "in"), incl_s = sum(y$t[y$st == "out"]) - sum(y$t[y$st == "in"]))
}))
cat(sprintf("variant=%s run=%s outer=%.3f internal=%.3f gap=%.3f\n", Sys.getenv("CODE_VARIANT", "recorded"),
            Sys.getenv("RUN_ID"), out$outer, out$internal, out$outer - out$internal))
print(r, row.names = FALSE)
setwd(W); unlink(work, recursive = TRUE)

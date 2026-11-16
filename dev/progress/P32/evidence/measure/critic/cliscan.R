# Codex CLI route (real adapter + relay, fake codex): per-request file scans from the CLI hooks.
# Args: <nfiles> <code: trivial|write> <n_req> <n_calls> <outdir>
a = commandArgs(TRUE)
nfiles = as.integer(a[[1]]); variant = a[[2]]; n_req = as.integer(a[[3]]); n_calls = as.integer(a[[4]]); out = a[[5]]
TW = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/cli-transport"
LIB = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/gate-measure/lib"
unlink(out, recursive = TRUE); dir.create(out, recursive = TRUE)
proj = file.path(out, "project"); dir.create(proj)
if (nfiles > 0) for (i in seq_len(nfiles)) writeLines(sprintf("a\tb\n%d\t2", i), file.path(proj, sprintf("f%04d.tsv", i)))
setwd(proj)
Sys.setenv(R_USER_CONFIG_DIR = file.path(out, "private/config"), R_USER_DATA_DIR = file.path(out, "private/data"),
           R_USER_CACHE_DIR = file.path(out, "private/cache"), GPTR_PROJECT_ROOT = proj,
           FAKE_LOG = file.path(out, "fake.jsonl"), FAKE_CALLS = n_calls)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj, gptr.cli_turn_timeout = 600)
library(gptr, lib.loc = LIB)
ns = asNamespace("gptr")
now = function() as.numeric(proc.time()[["elapsed"]])
acc = new.env(); acc$t = list(); acc$start = list(); acc$req = 0L
.tin = function(f) acc$start[[f]] = now()
.tout = function(f) { k = paste(acc$req, f); acc$t[[k]] = c(acc$t[[k]], now() - acc$start[[f]]) }
for (fn in c("ckpt_files_sync", "ckpt_files_turn_scan", "ckpt_files_step", "ckpt_scan_run", "mcp_serve_exec", "env_view_snapshot")) {
  suppressMessages(trace(fn, where = ns, print = FALSE,
    tracer = substitute(get(".tin", globalenv())(F), list(F = fn)),
    exit = substitute(get(".tout", globalenv())(F), list(F = fn))))
}
paths = list(codex = c(file.path(R.home("bin"), "Rscript"), "--vanilla", file.path(TW, "scripts/fake_codex.R")))
options(gptr.cli_path = paths)
spec = get("pcli_fake_provider", ns)("codex"); gptr_register(spec)
model = paste0(spec$id, "/", spec$models[[1L]]$id)
gptr_config(budget = list(tokens = 1e6, cost = 5, turns = 100), .scope = "session")
home = new.env(parent = globalenv())
code = if (variant == "write") "writeLines('x', 'out.txt')" else "1 + 1"
s = peter("request 1", model = model, mode = "auto", tools = "minimal", envir = home, .run = FALSE)
walls = numeric()
for (i in seq_len(n_req)) {
  acc$req = i; Sys.setenv(FAKE_CODE = code); t0 = now()
  if (i == 1L) gptr_wait(s) else peter(s, prompt = paste("request", i))
  walls[i] = now() - t0
}
cat(sprintf("nfiles=%d code=%s calls/request=%d status=%s\n", nfiles, variant, n_calls, s$status))
cat("request walls:", sprintf("%.2f", walls), "\n")
for (k in sort(names(acc$t))) cat(sprintf("  req %s: n=%d total=%.3f s [%s]\n", k, length(acc$t[[k]]), sum(acc$t[[k]]), paste(sprintf("%.3f", acc$t[[k]]), collapse = " ")))

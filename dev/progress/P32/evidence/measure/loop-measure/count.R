# Call counts and inclusive time per request for hot helpers (empty workspace, K tool calls)
# Usage: Rscript --vanilla count.R K=10 tools=minimal mode=auto tag=count
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/loop-measure"
cfg = list(K = 10L, tools = "minimal", mode = "auto", tag = "count", reqs = 4L)
for (a in commandArgs(TRUE)) { kv = strsplit(a, "=", fixed = TRUE)[[1]]; cfg[[kv[1]]] = if (is.integer(cfg[[kv[1]]])) as.integer(kv[2]) else kv[2] }
home_dir = file.path(W, "home", cfg$tag); proj = file.path(home_dir, "project")
dir.create(proj, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(R_USER_CONFIG_DIR = file.path(home_dir, "config"), R_USER_DATA_DIR = file.path(home_dir, "data"),
           R_USER_CACHE_DIR = file.path(home_dir, "cache"), GPTR_PROJECT_ROOT = proj)
setwd(proj)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj)
pkgload::load_all(file.path(W, "src/gptr"), quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
ctl = new.env(); ctl$left = 0L
fake = gptr_fake_provider(function(req) {
  if (ctl$left > 0L) { ctl$left = ctl$left - 1L; list(tool = "r", input = list(code = "1 + 1")) } else "Done."
}, name = "countfake")
cnt = new.env()
fns = c("setting_get", "service_lookup", "settings_file_read", "json_encode", "json_decode", "hash_sha256",
        "registry_all", "registry_get", "model_resolve", "catalog_get", "est_tokens", "project_messages",
        "ev_dispatch", "session_emit", "session_append", "store_write_lines", "project_root",
        "workspace_dir", "redact_tree", "prompt_request_estimate", "call_risk", "env_snap_size",
        "env_view_snapshot", "usage_row", "risk_classify", "file.exists")
fns = fns[vapply(fns, function(f) exists(f, envir = ns, inherits = FALSE), NA)]
for (fn in fns) {
  assign(fn, 0L, envir = cnt)
  suppressMessages(trace(fn, where = ns, print = FALSE,
    tracer = substitute(assign(FN, get(FN, envir = CNT) + 1L, envir = CNT), list(FN = fn, CNT = cnt))))
}
s = NULL
rows = list()
args = list(model = fake, envir = new.env(parent = globalenv()))
if (cfg$tools == "minimal") args$tools = "minimal"
if (cfg$mode == "auto") args$mode = "auto"
for (r in seq_len(cfg$reqs)) {
  for (fn in fns) assign(fn, 0L, envir = cnt)
  ctl$left = cfg$K
  if (is.null(s)) s = do.call(peter, c(list("count calls"), args)) else s = peter(s, prompt = "count calls again")
  rows[[r]] = vapply(fns, function(fn) get(fn, envir = cnt), 0L)
}
m = do.call(cbind, rows)
colnames(m) = paste0("req", seq_len(cfg$reqs))
print(m)
write.csv(m, file.path(W, "logs", paste0(cfg$tag, "-counts.csv")))

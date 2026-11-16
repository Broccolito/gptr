# Direct cost of env_snap_size(raw) and of one risk classification of the recorded request-2 code,
# outside any session, vs N; memory via gc(). Env: N, KIND, REPS, SRC.
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/gate-measure"
BENCH = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/bench/gptr-bench/biomedical/v0.5/reports/T03"
env = function(k, d) { v = Sys.getenv(k); if (nzchar(v)) v else d }
N = as.integer(env("N", "100")); KIND = env("KIND", "chr"); REPS = as.integer(env("REPS", "3"))
SRC = env("SRC", "/Users/wgu/Desktop/gptr")
work = file.path(W, "tmp", paste0("size-", Sys.getpid())); dir.create(work, recursive = TRUE); setwd(work)
Sys.setenv(R_USER_CONFIG_DIR = work, R_USER_DATA_DIR = work, R_USER_CACHE_DIR = work, GPTR_PROJECT_ROOT = work)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
pkgload::load_all(SRC, quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])
tf = file.path(W, "data", paste0("star-", KIND, ".tsv"))
mb = function() { g = gc(); sum(g[, 2]) }
mb0 = mb()
home = new.env(parent = globalenv())
files = sprintf("f%05d.tsv", seq_len(N))
tabs = lapply(seq_len(N), function(i) data.table::fread(file = tf, skip = "gene_id", header = TRUE, showProgress = FALSE))
home$raw = list(files = files, tables = setNames(tabs, files)); rm(tabs)
mb1 = mb()
invisible(gc(reset = TRUE))
calls = jsonlite::read_json(file.path(BENCH, "mcp-replay-analysis/evidence/calls.json"))
code2 = gsub("1231L", paste0(N, "L"), calls$calls[[2]]$input$code, fixed = TRUE)
res = list()
for (r in seq_len(REPS)) {
  t0 = clock(); b = ns$env_snap_size(home$raw, home); t1 = clock()
  t2 = clock(); o = utils::object.size(home$raw); t3 = clock()
  t4 = clock(); rk = ns$risk_classify(code2, envir = home, root = work, kind = "r"); t5 = clock()
  res[[r]] = data.frame(n = N, kind = KIND, rep = r, env_snap_size_s = t1 - t0, env_snap_size_gb = b / 1e9,
                        object_size_s = t3 - t2, object_size_gb = as.numeric(o) / 1e9,
                        classify_s = t5 - t4, risk_level = rk$level, raw_sized_gb = rk$sizes[["raw"]] / 1e9)
}
g = gc()
out = do.call(rbind, res)
out$live_mb_raw = mb1 - mb0
out$max_used_mb_during = sum(g[, ncol(g)])
print(out)
f = file.path(W, "out", "size-direct.csv")
write.table(out, f, sep = ",", row.names = FALSE, append = file.exists(f), col.names = !file.exists(f))
cat("flags:\n"); print(rk$flagged[rk$flagged$level >= 1, c("call", "level", "category")])
setwd(W); unlink(work, recursive = TRUE)

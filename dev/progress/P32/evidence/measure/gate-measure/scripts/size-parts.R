# Where env_snap_size(raw) spends its time: the walk (per-vector unique.default into the string
# store) vs env_size_strings() (unique(unlist()) over stored strings: once for the sampled list's
# extrapolation in env_size_items(), once at the end of env_snap_size()); tables walked before the
# sampling cut. Env: N, SHARENUM, REPS.
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/gate-measure"
env = function(k, d) { v = Sys.getenv(k); if (nzchar(v)) v else d }
N = as.integer(env("N", "300")); REPS = as.integer(env("REPS", "3")); SHARENUM = env("SHARENUM", "0") == "1"
work = file.path(W, "tmp", paste0("parts-", Sys.getpid())); dir.create(work, recursive = TRUE); setwd(work)
Sys.setenv(R_USER_CONFIG_DIR = work, R_USER_DATA_DIR = work, R_USER_CACHE_DIR = work, GPTR_PROJECT_ROOT = work)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
pkgload::load_all("/Users/wgu/Desktop/gptr", quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])
tf = file.path(W, "data", "star-chr.tsv")
rd = function() data.table::fread(file = tf, skip = "gene_id", header = TRUE, showProgress = FALSE)
shared = if (SHARENUM) as.list(rd())
tabs = lapply(seq_len(N), function(i) {
  x = rd(); if (!SHARENUM) return(x)
  l = unclass(x); num = which(!vapply(l, is.character, NA)); l[num] = shared[num]
  attr(l, ".internal.selfref") = NULL; data.table::setDT(l); l
})
home = new.env(parent = globalenv())
home$raw = list(files = sprintf("f%05d", seq_len(N)), tables = setNames(tabs, sprintf("f%05d", seq_len(N))))
rm(tabs); invisible(gc())
L = new.env(); L$rows = list()
assign("lg", function(...) L$rows[[length(L$rows) + 1L]] = data.frame(..., t = clock()), envir = globalenv())
suppressMessages({
  trace("env_size_strings", where = ns, print = FALSE,
        tracer = quote(get("lg", globalenv())(what = "strings", stage = "enter", n_idx = length(idx),
                                              n_items = NA, walked = NA)),
        exit = quote(get("lg", globalenv())(what = "strings", stage = "exit", n_idx = NA, n_items = NA, walked = NA)))
  trace("env_size_items", where = ns, print = FALSE,
        tracer = quote(get("lg", globalenv())(what = "items", stage = "enter", n_idx = NA, n_items = length(keys), walked = NA)),
        exit = quote(get("lg", globalenv())(what = "items", stage = "exit", n_idx = NA, n_items = n, walked = i - 1L)))
})
res = list()
for (r in seq_len(REPS)) {
  L$rows = list(); invisible(gc())
  t0 = clock(); b = ns$env_snap_size(home$raw, home); t1 = clock()
  x = do.call(rbind, L$rows)
  s = x[x$what == "strings", ]
  d = s$t[s$stage == "exit"] - s$t[s$stage == "enter"]
  it = x[x$what == "items" & x$stage == "exit" & x$n_items == N, ]
  res[[r]] = data.frame(n = N, sharenum = SHARENUM, rep = r, total_s = t1 - t0, gb = b / 1e9,
                        strings_calls = length(d), strings_s = sum(d),
                        strings_s_each = paste(round(d, 3), collapse = "+"),
                        strings_nidx_each = paste(s$n_idx[s$stage == "enter"], collapse = "+"),
                        walk_s = (t1 - t0) - sum(d), tables_walked = it$walked[1])
}
out = do.call(rbind, res); print(out)
f = file.path(W, "out", "size-parts.csv")
write.table(out, f, sep = ",", row.names = FALSE, append = file.exists(f), col.names = !file.exists(f))
setwd(W); unlink(work, recursive = TRUE)

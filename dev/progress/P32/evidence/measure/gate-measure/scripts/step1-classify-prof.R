# Which part of risk classification of the minimal replay's code (no fallback) touches the 4M IDs
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/gate-measure"
work = tempfile("cls-", tmpdir = file.path(W, "tmp")); dir.create(work, recursive = TRUE); setwd(work)
Sys.setenv(R_USER_CONFIG_DIR = work, R_USER_DATA_DIR = work, R_USER_CACHE_DIR = work, GPTR_PROJECT_ROOT = work)
pkgload::load_all("/Users/wgu/Desktop/gptr", quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
ns = asNamespace("gptr")
home = new.env(); home$x = sprintf("gene_%08d", seq_len(4000000))
code = 'sum(nchar(gsub("[0-9]", "", x)))'
f = file.path(W, "out", "rprof-step1-classify.out")
Rprof(f, interval = 0.002, event = "elapsed")
for (i in 1:5) r = ns$risk_classify(code, envir = home, root = work, kind = "r")
Rprof(NULL)
s = summaryRprof(f); print(head(s$by.self, 12)); bt = s$by.total; print(head(bt[bt$total.pct < 99, ], 25))
print(system.time(for (i in 1:5) ns$risk_classify(code, envir = home, root = work, kind = "r")))
setwd(W); unlink(work, recursive = TRUE)

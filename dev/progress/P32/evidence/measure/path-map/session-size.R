# Does env_snap_size() of a gptr_session (dot_facts() of peter(s, ...)) walk the session home?
out = commandArgs(TRUE)[1]
setwd(out)
Sys.setenv(R_USER_CONFIG_DIR = file.path(out, "config"), R_USER_DATA_DIR = file.path(out, "data"),
           R_USER_CACHE_DIR = file.path(out, "cache"), GPTR_PROJECT_ROOT = out)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = out)
pkgload::load_all("/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/path-map/src/gptr",
                  quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
home = new.env(parent = globalenv())
s = peter("hi", model = gptr_fake_provider(list("ok")), mode = "auto", tools = "minimal", envir = home)
size = get("env_snap_size", ns)
b0 = size(s)
home$big = runif(2.5e7)   # 200 MB
home$chr = as.character(seq_len(2e5))
t = system.time(b1 <- size(s))[["elapsed"]]
cat("session bytes before big object:", b0, "\n")
cat("session bytes with 200 MB object in home:", b1, " elapsed:", t, "\n")
cat("walk reaches home:", b1 - b0 > 1e8, "\n")
f = get("dot_facts", ns)
cat("dot_facts(s)$bytes:", f(s)$bytes, "\n")

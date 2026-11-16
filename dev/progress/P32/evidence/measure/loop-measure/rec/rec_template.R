# Document-recording cost: three peter() requests of K=10 tool calls, record = REC
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/loop-measure"
d = file.path(W, "home", "rec_REC")
dir.create(file.path(d, "project"), recursive = TRUE, showWarnings = FALSE)
Sys.setenv(R_USER_CONFIG_DIR = file.path(d, "config"), R_USER_DATA_DIR = file.path(d, "data"),
           R_USER_CACHE_DIR = file.path(d, "cache"), GPTR_PROJECT_ROOT = getwd())
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = getwd(), gptr.record = "REC")
pkgload::load_all(file.path(W, "src/gptr"), quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ctl = new.env(); ctl$left = 0L
fake = gptr_fake_provider(function(req) {
  if (ctl$left > 0L) { ctl$left = ctl$left - 1L; list(tool = "r", input = list(code = "1 + 1")) } else "Done."
}, name = "recfake")
home = new.env()
walls = numeric()
ctl$left = 10L; t0 = proc.time()[[3]]
s = peter("Compute 1 + 1 ten times with the r tool.", model = fake, mode = "auto", tools = "minimal", envir = home)
walls = c(walls, proc.time()[[3]] - t0)
ctl$left = 10L; t0 = proc.time()[[3]]
s = peter(s, prompt = "Again, ten times.")
walls = c(walls, proc.time()[[3]] - t0)
ctl$left = 10L; t0 = proc.time()[[3]]
s = peter(s, prompt = "And once more, ten times.")
walls = c(walls, proc.time()[[3]] - t0)
ctl$left = 10L; t0 = proc.time()[[3]]
s = peter(s, prompt = "Last time, ten times.")
walls = c(walls, proc.time()[[3]] - t0)
cat("REC walls:", round(walls, 3), "\n")

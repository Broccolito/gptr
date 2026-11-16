# Per-call cost of mutating small calls vs number of project entries (file-scan valley check).
# Rscript --vanilla valley.R nfiles=500 kind=rwrite K=10 reps=3
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work"
cfg = list(nfiles = 0L, kind = "rwrite", K = 10L, reps = 3L, warm = 1L)
for (a in commandArgs(TRUE)) { kv = strsplit(a, "=", fixed = TRUE)[[1]]; cfg[[kv[1]]] = if (kv[1] == "kind") kv[2] else as.integer(kv[2]) }
tag = sprintf("%s-%d", cfg$kind, cfg$nfiles)
hd = file.path(W, "critic", "home", tag); unlink(hd, recursive = TRUE)
proj = file.path(hd, "project"); dir.create(proj, recursive = TRUE)
if (cfg$nfiles > 0) for (i in seq_len(cfg$nfiles)) writeLines(sprintf("a,b\n%d,2", i), file.path(proj, sprintf("f%05d.csv", i)))
Sys.setenv(R_USER_CONFIG_DIR = file.path(hd, "config"), R_USER_DATA_DIR = file.path(hd, "data"),
           R_USER_CACHE_DIR = file.path(hd, "cache"), GPTR_PROJECT_ROOT = proj)
setwd(proj)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj)
library(gptr, lib.loc = file.path(W, "gate-measure", "lib"))
clock = function() as.numeric(proc.time()[["elapsed"]])
home = new.env(parent = globalenv())
ctl = new.env(); ctl$left = 0L; ctl$i = 0L
script = function(req) {
  if (ctl$left > 0L) {
    ctl$left = ctl$left - 1L; ctl$i = ctl$i + 1L
    switch(cfg$kind,
      rwrite = list(tool = "r", input = list(code = sprintf("y = %d\nwriteLines('v%d', 'out.txt')", ctl$i, ctl$i))),
      robj = list(tool = "r", input = list(code = sprintf("y = %d", ctl$i))),
      read = list(tool = "r", input = list(code = "1 + 1")),
      write = list(tool = "write", input = list(path = file.path(proj, "out.txt"), content = sprintf("v%d\n", ctl$i))))
  } else "Done."
}
fake = gptr_fake_provider(script, name = "valleyfake")
ev = new.env(); ev$s = numeric(); ev$o = numeric(); ev$i = numeric(); ev$req = integer(); ev$cur = 0L
gptr_register(gptr_hook("tool_execution_start", function(event, ctx) { ev$s = c(ev$s, clock()); NULL }))
gptr_register(gptr_hook("tool_execution_end", function(event, ctx) {
  ev$o = c(ev$o, clock() - ev$s[length(ev$s)]); ev$i = c(ev$i, as.numeric(event$elapsed %||% NA)); ev$req = c(ev$req, ev$cur); NULL }))
`%||%` = function(a, b) if (is.null(a)) b else a
s = NULL; walls = numeric()
ask = function(k) {
  ctl$left = k; ev$cur = ev$cur + 1L; t0 = clock()
  if (is.null(s)) s <<- peter("Do it.", model = fake, envir = home, tools = "minimal", mode = "auto") else s <<- peter(s, prompt = "Again.")
  walls[ev$cur] <<- clock() - t0
}
for (w in seq_len(cfg$warm)) ask(cfg$K)
for (r in seq_len(cfg$reps)) ask(cfg$K)
m = ev$req > cfg$warm
cat(sprintf("%s nfiles=%d K=%d: per-call outer median %.3f s, internal %.3f s, gap %.3f s; first call of request median %.3f s; request wall median %.2f s; errors? n=%d\n",
  cfg$kind, cfg$nfiles, cfg$K, median(ev$o[m]), median(ev$i[m]), median(ev$o[m] - ev$i[m]),
  median(tapply(ev$o[m], ev$req[m], function(x) x[1])), median(walls[-seq_len(cfg$warm)]), sum(m)))

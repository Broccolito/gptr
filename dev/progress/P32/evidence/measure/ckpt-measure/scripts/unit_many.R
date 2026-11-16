# The objects checkpointer alone (ckpt_objects_before/after on a fresh checkpoint state), with n
# small bindings in the home: scaling and Rprof. Usage: Rscript --vanilla unit_many.R <outdir> n1 n2 ...
a = commandArgs(TRUE)
outdir = a[1]; ns_list = as.integer(a[-1])
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/ckpt-measure"
work = file.path(outdir, "unit_many_work"); unlink(work, recursive = TRUE); dir.create(work, recursive = TRUE)
Sys.setenv(R_USER_CONFIG_DIR = file.path(work, "config"), R_USER_DATA_DIR = file.path(work, "data"),
           R_USER_CACHE_DIR = file.path(work, "cache"), GPTR_PROJECT_ROOT = work)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
suppressMessages(pkgload::load_all(file.path(W, "src/gptr"), quiet = TRUE, helpers = FALSE,
                                   attach_testthat = FALSE))
ns = asNamespace("gptr")
g = function(f) get(f, ns)
clock = function() as.numeric(proc.time()[["elapsed"]])
res = list()
for (n in ns_list) {
  home = new.env(parent = globalenv())
  for (i in seq_len(n)) assign(sprintf("o%05d", i), as.numeric(1:10) + i, envir = home)
  ck = g("ckpt_ck_new")("kunit", NULL)
  call = list(input = list(code = "v = sum(o00001)"))
  r = list(n = n)
  t0 = clock(); ck$snap = g("env_snapshot")(home); r$snapshot_cold = clock() - t0
  t0 = clock(); s2 = g("env_snapshot")(home, ck$snap); r$snapshot_warm = clock() - t0
  t0 = clock(); g("env_snapshot_rows")(home, NULL, sizes = FALSE); r$snapshot_nosize = clock() - t0
  t0 = clock(); for (nm in ls(home)) g("fingerprint")(get(nm, home)); r$fingerprint_all = clock() - t0
  bt = numeric(3); at = numeric(3)
  for (k in 1:3) {
    gc()
    t0 = clock(); tok = g("ckpt_objects_before")(ck, call, home, k); bt[k] = clock() - t0
    assign("v", k, envir = home)
    t0 = clock(); fr = g("ckpt_objects_after")(ck, call, home, tok); at[k] = clock() - t0
  }
  r$before = median(bt); r$before_all = bt; r$after = median(at); r$after_all = at
  # parts of before
  snap = ck$snap[ck$snap$kind == "value", , drop = FALSE]
  tg = g("ckpt_predict")(call$input$code)
  pred = g("ckpt_predicted")(snap$name, tg)
  lim = g("ckpt_limits")()
  t0 = clock(); pm = g("ckpt_preimage_modes")(ck$obj, home, snap, pred, lim); r$preimage_modes = clock() - t0
  t0 = clock(); cap = g("ckpt_capture")(ck$obj, home, snap$name); r$capture = clock() - t0
  t0 = clock(); for (i in seq_len(min(n, 1000))) g("id_new")("", 12L); r$id_new_per_1000 = clock() - t0
  t0 = clock(); st = g("ckpt_settle")(ck$obj, home, cap); r$settle = clock() - t0
  if (n == max(ns_list)) {
    pf = file.path(outdir, sprintf("unit_many_n%d.Rprof", n))
    utils::Rprof(pf, interval = 0.005)
    for (k in 4:6) {
      tok = g("ckpt_objects_before")(ck, call, home, k)
      assign("v", k, envir = home)
      fr = g("ckpt_objects_after")(ck, call, home, tok)
    }
    utils::Rprof(NULL)
    sp = summaryRprof(pf)
    print(utils::head(sp$by.self, 20)); print(utils::head(sp$by.total, 35))
  }
  str(r)
  res[[length(res) + 1L]] = r
  rm(home, ck); gc()
}
jsonlite::write_json(res, file.path(outdir, "unit_many.json"), auto_unbox = TRUE, digits = 8, pretty = TRUE)
unlink(work, recursive = TRUE)

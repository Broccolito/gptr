# Undo of large objects (plan P33 T7): seconds, disk and memory of one peter() call that changes a
# 0.5 GB object and of its undo, from the repository root:
#   Rscript --vanilla dev/bench/undo/run.R [tree] [--reps=3]
# `tree` is the source tree to install into a temporary library (default "."), so the same command
# measures main and the P33 branch. Each repetition is a fresh child (this file with `child`) under
# /usr/bin/time -l (macOS; peak RSS); a fourth child per scenario also checks that the undo restores
# the object with identical(). A table of medians and the load average before and after are printed.
# Needs a machine with about 4 GB free; the load average should be below 20 (it waits up to 15 min).

scenarios = list(
  a = list(what = "list of 4e6 strings, element edit", edit = "obj[[7]][3] = 'x'",
           make = quote(lapply(1:400, function(i) {
             sprintf("string-value-%010d-%s", (i - 1) * 1e4 + 1:1e4, strrep("x", 12))
           }))),
  b = list(what = "data frame of 8 numeric columns, df$a[1] = 0", edit = "obj$a[1] = 0",
           make = quote(as.data.frame(lapply(stats::setNames(1:8, letters[1:8]),
                                             function(j) (1:8e6) * j + 0.5)))),
  c = list(what = "numeric matrix 8000 x 8000, m[1, 1] = 0", edit = "obj[1, 1] = 0",
           make = quote(matrix((1:6.4e7) * 1.5, 8000L))),
  d = list(what = "numeric vector of 6.5e7, rebind x = x + 1", edit = "obj = obj + 1",
           make = quote((1:6.5e7) * 1.5)),
  e = list(what = "scenario b without .gptr/ (non-interactive)", edit = "obj$a[1] = 0",
           make = quote(as.data.frame(lapply(stats::setNames(1:8, letters[1:8]),
                                             function(j) (1:8e6) * j + 0.5))), ws = FALSE))

child = function(id, lib, out, verify) {
  sc = scenarios[[id]]
  root = file.path(tempfile("gptr-undo-"), "project")
  dir.create(root, recursive = TRUE)
  for (v in c("HOME", "R_USER_CONFIG_DIR", "R_USER_DATA_DIR", "R_USER_CACHE_DIR")) {
    d = file.path(dirname(root), v)
    dir.create(d)
    do.call(Sys.setenv, stats::setNames(list(d), v))
  }
  setwd(root)
  options(gptr.project_root = root)
  .libPaths(c(lib, .libPaths()))
  suppressMessages(library(gptr))
  if (!isFALSE(sc$ws)) suppressMessages(gptr_init(root, instructions = FALSE))
  ns = asNamespace("gptr")
  now = function() proc.time()[["elapsed"]]
  imgs = function() {
    f = list.files(file.path(root, ".gptr", "checkpoints", "objects"), recursive = TRUE,
                   full.names = TRUE)
    sum(file.size(f)) / 1e6
  }
  ev = list()
  st = new.env()
  hook = function(fn, exit = function() NULL) {
    orig = get(fn, ns)
    unlockBinding(fn, ns)
    assign(fn, function(...) {
      t0 = now()
      if (fn == "ckpt_objects_after") st$in_after = TRUE
      on.exit({
        if (fn == "ckpt_objects_after") st$in_after = FALSE
        ev[[length(ev) + 1L]] <<- list(fn = fn, t0 = t0, t1 = now(), nested = isTRUE(st$in_after))
        exit()
      })
      orig(...)
    }, envir = ns)
  }
  img = c(pre = NA, post = NA)
  hook("ckpt_objects_before", function() img[["pre"]] <<- imgs())
  hook("ckpt_objects_after", function() img[["post"]] <<- imgs())
  hook("ckpt_objects_budget")

  e = new.env()
  e$obj = eval(sc$make)
  size = as.numeric(utils::object.size(e$obj)) / 1e6
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = sc$edit)), "done"))
  gptr_register(fake)
  s = suppressMessages(peter("edit obj", model = "fake/fake-1", mode = "auto", envir = e))
  end = imgs()
  cp = gptr_checkpoints(s)
  tu = system.time(suppressMessages(gptr_rewind(s, turn = -1L)))[["elapsed"]]
  dur = function(fn, nested = NULL) {
    sum(vapply(Filter(function(x) x$fn == fn && (is.null(nested) || x$nested == nested), ev),
               function(x) x$t1 - x$t0, 0))
  }
  b = Filter(function(x) x$fn == "ckpt_objects_before", ev)[[1L]]
  a = Filter(function(x) x$fn == "ckpt_objects_after", ev)[[1L]]
  res = c(size_mb = size, before = dur("ckpt_objects_before"), eval = a$t0 - b$t1,
          after = dur("ckpt_objects_after"), budget_end = dur("ckpt_objects_budget", FALSE),
          budget_in_after = dur("ckpt_objects_budget", TRUE), undo = tu,
          img_pre_mb = img[["pre"]], img_post_mb = img[["post"]], img_end_mb = end,
          held_mb = cp$held_mb[[nrow(cp)]], disk_mb = cp$disk_mb[[nrow(cp)]],
          restored = if (verify) as.numeric(identical(e$obj, eval(sc$make))) else NA)
  saveRDS(res, out)
}

if (identical(commandArgs(TRUE)[1L], "child")) {
  a = commandArgs(TRUE)
  child(a[[2L]], a[[3L]], a[[4L]], identical(a[5L], "verify"))
  quit(save = "no")
}

source(file.path("dev", "bench", "common.R"), local = TRUE)

load1 = function() as.numeric(strsplit(trimws(gsub("[{}]", "", system2("sysctl", c("-n", "vm.loadavg"),
                                                                       stdout = TRUE))), " +")[[1L]][[1L]])
wait_for_load = function(limit = 20, minutes = 15L) {
  for (i in seq_len(minutes)) {
    if (load1() <= limit) break
    message(sprintf("[undo] load %.1f above %d; waiting a minute", load1(), limit))
    Sys.sleep(60)
  }
}

run_child = function(id, lib, verify) {
  out = tempfile(fileext = ".rds")
  log = tempfile(fileext = ".log")
  status = system2("/usr/bin/time", c("-l", file.path(R.home("bin"), "Rscript"), "--vanilla",
                                      file.path("dev", "bench", "undo", "run.R"), "child", id,
                                      shQuote(lib), shQuote(out), if (verify) "verify"),
                   stdout = log, stderr = log)
  txt = readLines(log)
  if (!identical(status, 0L) || !file.exists(out)) {
    stop("scenario ", id, " child failed:\n", paste(utils::tail(txt, 30L), collapse = "\n"))
  }
  rss = as.numeric(sub("^\\s*(\\d+)\\s+maximum resident set size.*$", "\\1",
                       grep("maximum resident set size", txt, value = TRUE)))
  c(readRDS(out), rss_mb = rss / 1e6)
}

if (sys.nframe() == 0L) quit(save = "no", status = bench_run(function() {
  args = commandArgs(TRUE)
  tree = if (length(args) && !startsWith(args[[1L]], "--")) args[[1L]] else "."
  reps = as.integer(sub("^--reps=", "", args[startsWith(args, "--reps=")]))
  if (!length(reps)) reps = 3L
  wait_for_load()
  load_before = system2("sysctl", c("-n", "vm.loadavg"), stdout = TRUE)
  bench_isolate()
  lib = bench_install_gptr(tree)
  rows = lapply(names(scenarios), function(id) {
    runs = lapply(seq_len(reps), function(i) run_child(id, lib, FALSE))
    ok = run_child(id, lib, TRUE)[["restored"]]
    m = apply(do.call(rbind, runs), 2L, stats::median)
    m[["restored"]] = ok
    message("[undo] ", id, " done")
    m
  })
  tab = data.frame(scenario = names(scenarios), round(do.call(rbind, rows), 2))
  withr::with_options(list(width = 250L), print(tab, row.names = FALSE))
  cat("\nseconds: before, eval, after = checkpointer before / R evaluation / checkpointer after;",
      "budget_end = agent_end budget; budget_in_after = budget inside after (P33).",
      "\nimg_*_mb: files under .gptr/checkpoints/objects at the end of before, of after, of the turn.",
      "\nrestored: 1 = identical() after the undo. medians of", reps, "children.\n")
  for (id in names(scenarios)) cat(id, ": ", scenarios[[id]]$what, "\n", sep = "")
  cat("load average before:", load_before, " after:", system2("sysctl", c("-n", "vm.loadavg"),
                                                             stdout = TRUE), "\n")
}))

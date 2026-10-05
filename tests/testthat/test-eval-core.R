test_that("rng_seeds derives a valid L'Ecuyer vector from a key without the RNG", {
  env = globalenv()
  before = get0(".Random.seed", envir = env, inherits = FALSE)
  s = rng_seeds("s0123456789")
  expect_type(s, "integer")
  expect_length(s, 7L)
  expect_equal(s[1], 10407L)
  expect_identical(rng_seeds("s0123456789"), s)
  expect_false(identical(rng_seeds("s0123456789:b"), s))
  expect_identical(get0(".Random.seed", envir = env, inherits = FALSE), before)
})

test_that("rng_swap keeps the user's .Random.seed and advances the agent's stream", {
  withr::local_seed(42)
  env = globalenv()
  before = get(".Random.seed", envir = env)
  st1 = new.env()
  st1$id = "s0123456789"
  x1 = rng_swap(st1, stats::runif(3))
  expect_identical(get(".Random.seed", envir = env), before)
  expect_equal(st1$seed[1], 10407L)
  st2 = new.env()
  st2$id = "s0123456789"
  expect_identical(rng_swap(st2, stats::runif(3)), x1)
  expect_false(identical(rng_swap(st2, stats::runif(3)), x1))
  expect_identical(stats::runif(1), withr::with_seed(42, stats::runif(1)))
})

test_that("rng_swap removes .Random.seed again when the user had none", {
  env = globalenv()
  saved = get0(".Random.seed", envir = env, inherits = FALSE)
  withr::defer({
    if (!is.null(saved)) env[[".Random.seed"]] = saved
  })
  if (!is.null(saved)) rm(list = ".Random.seed", envir = env)
  st = new.env()
  st$id = "s1"
  x = rng_swap(st, stats::runif(1))
  expect_false(exists(".Random.seed", envir = env, inherits = FALSE))
  expect_true(is.numeric(x))
  expect_equal(st$seed[1], 10407L)
  expect_error(rng_swap(list(), 1), class = "gptr_error_invalid_argument")
})

test_that("rng_swap leaves R's generator kind as it found it when the user had no seed", {
  env = globalenv()
  withr::local_preserve_seed()
  set.seed(42)
  ref = stats::runif(1)
  rm(list = ".Random.seed", envir = env)
  st = new.env()
  st$id = "s2"
  rng_swap(st, stats::runif(1))
  expect_false(exists(".Random.seed", envir = env, inherits = FALSE))
  set.seed(42)
  expect_identical(stats::runif(1), ref)
})

# Added beyond the plan's blocks (P09 Task 7 evidence in dev/progress/P09.md).

test_that("rng_seeds matches IC-61's derivation word for word", {
  # Reference vectors computed independently (Python hashlib): the first 24 bytes of
  # sha256(key) as six big-endian 32-bit words, three modulo m1 and three modulo m2, in
  # two's complement. Pinned so that reproducible streams (.opts$seed) stay stable.
  expect_identical(
    rng_seeds("s0123456789"),
    c(10407L, -146143283L, 119445096L, -844057359L, 1765153392L, 252959532L, -1668458951L)
  )
  expect_identical(
    rng_seeds("7:worker"),
    c(10407L, -1139394146L, 1575112895L, 1638773665L, -378824907L, -253925496L, 1846536792L)
  )
  s = rng_seeds("s0123456789:b")
  u = ifelse(is.na(s[-1L]), 2147483648, ifelse(s[-1L] < 0L, s[-1L] + 4294967296, s[-1L]))
  expect_true(all(u[1:3] < 4294967087))
  expect_true(all(u[4:6] < 4294944443))
})

test_that("rng_seeds stores the word 2^31 as NA silently and never yields an all-zero group", {
  local_mocked_bindings(hash_sha256 = function(x) {
    paste0(strrep("80000000", 3L), strrep("00000000", 3L), strrep("0", 16L))
  })
  s = expect_no_warning(rng_seeds("k"))
  expect_identical(s, c(10407L, NA, NA, NA, 1L, 0L, 0L))
  local_mocked_bindings(hash_sha256 = function(x) {
    paste0("ffffff2f", "00000000", "00000000", "ffffa6bb", "00000001", "7fffffff",
           strrep("0", 16L))
  })
  expect_identical(rng_seeds("k"), c(10407L, 1L, 0L, 0L, 0L, 1L, 2147483647L))
})

test_that("a vector with NA words is a valid, reproducible stream for R", {
  withr::local_seed(7)
  env = globalenv()
  before = get(".Random.seed", envir = env)
  seed = c(10407L, NA, NA, NA, 1L, 0L, 0L)
  st1 = new.env()
  st1$seed = seed
  st2 = new.env()
  st2$seed = seed
  a = expect_no_warning(rng_swap(st1, stats::runif(2)))
  expect_identical(rng_swap(st2, stats::runif(2)), a)
  expect_identical(get(".Random.seed", envir = env), before)
})

test_that("rng_swap restores the user's seed after an error and keeps the advanced stream", {
  withr::local_seed(11)
  env = globalenv()
  before = get(".Random.seed", envir = env)
  st = new.env()
  st$id = "s-err"
  expect_error(rng_swap(st, {
    stats::runif(1)
    stop("boom")
  }), "boom")
  expect_identical(get(".Random.seed", envir = env), before)
  expect_equal(st$seed[1], 10407L)
  expect_false(identical(st$seed, rng_seeds("s-err")))
  ref = new.env()
  ref$id = "s-err"
  first = rng_swap(ref, stats::runif(2))
  expect_identical(rng_swap(st, stats::runif(1)), first[2])
})

test_that("rng_swap derives the stream from the id, or from 'gptr' without one, and returns expr", {
  withr::local_seed(3)
  st = new.env()
  expect_identical(rng_swap(st, "value"), "value")
  expect_identical(st$seed, rng_seeds("gptr"))
  st2 = new.env()
  st2$id = "3:worker"
  expect_identical(rng_swap(st2, 1L), 1L)
  expect_identical(st2$seed, rng_seeds("3:worker"))
})

test_that("rng_swap keeps a non-default generator kind when the user had no seed", {
  env = globalenv()
  withr::local_preserve_seed()
  old = RNGkind("Knuth-TAOCP-2002")
  withr::defer(RNGkind(old[1L], old[2L], old[3L]))
  set.seed(42)
  ref = stats::runif(1)
  rm(list = ".Random.seed", envir = env)
  st = new.env()
  st$id = "s3"
  rng_swap(st, stats::runif(1))
  expect_false(exists(".Random.seed", envir = env, inherits = FALSE))
  expect_equal(st$seed[1], 10407L)
  set.seed(42)
  expect_identical(stats::runif(1), ref)
})

# Review round 1: the branch where the user had a seed.

test_that("rng_swap leaves R's generator kind as it found it when the user had a seed", {
  # R keeps the kind internally; the restored vector alone left L'Ecuyer-CMRG in force, so a
  # user who then removed .Random.seed drew other numbers after set.seed(42).
  env = globalenv()
  withr::local_preserve_seed()
  set.seed(42)
  ref = stats::runif(1)
  set.seed(1)
  before = get(".Random.seed", envir = env)
  st = new.env()
  st$id = "s5"
  rng_swap(st, stats::runif(1))
  expect_identical(get(".Random.seed", envir = env), before)
  rm(list = ".Random.seed", envir = env)
  set.seed(42)
  expect_identical(stats::runif(1), ref)
  rm(list = ".Random.seed", envir = env)
  rng_swap(st, stats::runif(1))
  set.seed(42)
  expect_identical(stats::runif(1), ref)
})

test_that("rng_swap restores a .Random.seed that R would reject, silently and identically", {
  env = globalenv()
  withr::local_preserve_seed()
  withr::defer({
    if (exists(".Random.seed", envir = env, inherits = FALSE)) {
      rm(list = ".Random.seed", envir = env)
    }
  })
  st = new.env()
  st$id = "s6"
  bad = list(c(10403L, 1L, 2L), c(1.5, 2), 10403L, c(NA_integer_, 1L))
  for (b in bad) {
    env[[".Random.seed"]] = b
    expect_no_warning(rng_swap(st, stats::runif(1)))
    expect_identical(get(".Random.seed", envir = env), b)
  }
})

# P09 Task 8: the evaluator eval_r().

ev_types = function(res) vapply(res$events, function(e) e$type, "")
ev_of = function(res, type) Filter(function(e) identical(e$type, type), res$events)

test_that("eval_r evaluates in envir, prints like the console and keeps no value", {
  e = new.env()
  res = eval_r("x = 1:3\nx\ny = x * 2; invisible(y)\nsum(y)", e)
  expect_s3_class(res, "gptr_eval_result")
  expect_named(res, c("status", "events", "n_done", "n_total", "changes", "elapsed", "images",
                      "assigned", "outputs", "spill", "out_id", "interrupted_after"))
  expect_equal(res$status, "ok")
  expect_equal(c(res$n_done, res$n_total), c(5L, 5L))
  expect_equal(e$y, c(2, 4, 6))
  out = paste(vapply(ev_of(res, "output"), function(ev) ev$text, ""), collapse = "")
  expect_equal(out, "[1] 1 2 3\n[1] 12\n")
  expect_equal(res$outputs, list(character(), "[1] 1 2 3", character(), character(), "[1] 12"))
  expect_setequal(res$assigned, c("x", "y"))
  expect_equal(res$changes$objects$added, c("x", "y"))
  expect_equal(res$changes$objects$lines, c("+ x <integer length 3>", "+ y <numeric length 3>"))
  expect_equal(ev_of(res, "source")[[2]]$text, "x")
})

test_that("warnings and messages are captured in order and muffled without tee", {
  e = new.env()
  code = paste("message('m1')", "f = function() warning('w1'); f()", "cat('o1\\n')",
               "message('m2')", sep = "\n")
  expect_silent({
    res = eval_r(code, e, tee = FALSE)
  })
  types = ev_types(res)
  expect_equal(types[types != "source"], c("message", "warning", "output", "message"))
  w = ev_of(res, "warning")[[1]]
  expect_equal(w$text, "w1")
  expect_equal(w$call, "f()")
})

test_that("an error stops at the first failing expression with a trimmed traceback", {
  e = new.env()
  code = "a1 = 1\nh = function(v) stop('boom: ', v)\ng = function(v) h(v)\ng('z')\na2 = 2"
  res = eval_r(code, e)
  expect_equal(res$status, "error")
  expect_equal(c(res$n_done, res$n_total), c(3L, 5L))
  expect_equal(e$a1, 1)
  expect_false(exists("a2", envir = e, inherits = FALSE))
  err = ev_of(res, "error")[[1]]
  expect_equal(err$message, "boom: z")
  expect_equal(err$call, "h(v)")
  expect_equal(err$line, 4L)
  tb = err$traceback
  expect_match(tb[1], "^ 1: g\\(\"z\"\\)")
  expect_match(tb[2], "^ 2: h\\(v\\) at <gptr>#3")
  expect_match(tb[3], "^ 3: stop\\(\"boom: \", v\\) at <gptr>#2")
  expect_false(any(grepl("eval_frame|withCallingHandlers|handleSimpleError", tb)))
})

test_that("options(warn = 2) turns a model warning into an error result", {
  e = new.env()
  withr::local_options(warn = 0)
  res = eval_r("options(warn = 2); as.integer('x')", e)
  expect_equal(res$status, "error")
  expect_match(ev_of(res, "error")[[1]]$message, "converted from warning")
  expect_equal(res$changes$options, "warn")
})

test_that("q(), readline() and g = q; g() are refused without evaluation", {
  e = new.env()
  codes = c("done = TRUE; q('no')", "done = TRUE; x = readline('?')", "done = TRUE; g = q; g()")
  for (code in codes) {
    res = eval_r(code, e)
    expect_equal(res$status, "blocked")
    expect_equal(res$n_done, 0L)
    expect_false(exists("done", envir = e, inherits = FALSE))
    expect_match(ev_of(res, "error")[[1]]$message, "^Not run: ")
  }
})

test_that("parse errors evaluate nothing", {
  res = eval_r("x = c(1, 2\ny = ]", new.env())
  expect_equal(res$status, "parse_error")
  expect_match(ev_of(res, "error")[[1]]$message, "<gptr>:")
})

test_that("CR LF line ends parse, and query calls print like the console", {
  e = new.env()
  withr::local_options(digits = 7)
  res = eval_r("x = 1\r\ny = 2\r\nx + y", e)
  expect_equal(res$status, "ok")
  expect_equal(res$outputs[[3]], "[1] 3")
  res = eval_r("options('digits')\nsuppressPackageStartupMessages(1 + 1)", e)
  expect_equal(res$outputs, list(c("$digits", "[1] 7"), "[1] 2"))
})

test_that("an infinite recursion becomes an error result instead of escaping", {
  e = new.env()
  res = eval_r("f = function(n) f(n + 1)\nf(1)\nafter = 1", e)
  expect_equal(res$status, "error")
  expect_equal(c(res$n_done, res$n_total), c(1L, 3L))
  err = ev_of(res, "error")[[1]]
  expect_true("stackOverflowError" %in% err$class)
  expect_equal(err$line, 2L)
  expect_false(exists("after", envir = e, inherits = FALSE))
})

test_that("sinks, options, hooks and the time limit are restored after errors and interrupts", {
  e = new.env()
  n_sink = sink.number()
  width = getOption("width")
  hooks = length(getHook("before.plot.new"))
  conns = nrow(showConnections())
  res1 = eval_r("sink(tempfile()); cat('into user sink\\n'); stop('after sink')", e)
  expect_equal(res1$status, "error")
  res2 = eval_r("sink(); cat('after pop\\n')", e)
  expect_match(ev_of(res2, "output")[[1]]$text, "after pop")
  interrupt = "signalCondition(structure(class = c('interrupt', 'condition'), list()))"
  res3 = eval_r(paste0("a1 = 1\n", interrupt, "\na2 = 2"), e)
  expect_equal(res3$status, "interrupt")
  expect_true(is.numeric(res3$interrupted_after))
  expect_true(exists("a1", envir = e, inherits = FALSE))
  expect_false(exists("a2", envir = e, inherits = FALSE))
  expect_true("interrupt" %in% ev_types(res3))
  expect_equal(sink.number(), n_sink)
  expect_equal(getOption("width"), width)
  expect_length(getHook("before.plot.new"), hooks)
  expect_equal(nrow(showConnections()), conns)
})

test_that("session-state changes are reported by name, never by value", {
  e = new.env()
  withr::local_dir(getwd())
  withr::local_envvar(GPTR_P09_TEST = NA)
  withr::local_options(digits = 7)
  wd = getwd()
  code = sprintf("options(digits = 3); setwd('%s'); Sys.setenv(GPTR_P09_TEST = 'sekret')",
                 gsub("\\\\", "/", tempdir()))
  res = eval_r(code, e)
  expect_equal(res$changes$options, "digits")
  expect_equal(unname(res$changes$wd["from"]), wd)
  expect_equal(res$changes$envvars, "GPTR_P09_TEST")
  expect_false(grepl("sekret", paste(unlist(res$changes), collapse = " ")))
})

test_that("R's lazily set TZDIR is not reported as a change", {
  a = list(wd = "/a", options = list(), envvars = c(HOME = "/h"), search = "x", ns = "base",
           devices = NULL)
  b = a
  b$envvars = c(HOME = "/h", TZDIR = "/usr/share/zoneinfo")
  expect_equal(eval_state_diff(a, b)$envvars, character())
  b$envvars = c(HOME = "/h2")
  expect_equal(eval_state_diff(a, b)$envvars, "HOME")
})

test_that("a timeout stops a busy loop with status timeout", {
  res = eval_r("i = 0\nrepeat { i = i + 1 }", new.env(), timeout = 1)
  expect_equal(res$status, "timeout")
  expect_lt(res$elapsed, 10)
  expect_match(ev_of(res, "error")[[1]]$message, "^Timed out after 1s")
})

test_that("a plot yields one 768x512 PNG image block and no Rplots.pdf", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  dir = withr::local_tempdir()
  withr::local_dir(dir)
  dev = grDevices::dev.cur()
  res = eval_r("plot(1:10)", new.env())
  expect_length(res$images, 1L)
  expect_equal(c(res$images[[1]]$width, res$images[[1]]$height), c(768L, 512L))
  expect_equal(res$images[[1]]$mime, "image/png")
  expect_equal(res$images[[1]]$source, "plot")
  p = ev_of(res, "plot")[[1]]
  expect_true(p$attached)
  expect_true(file.exists(p$path))
  expect_false(file.exists(file.path(dir, "Rplots.pdf")))
  expect_equal(grDevices::dev.cur(), dev)
})

test_that("a 50-plot loop attaches 3 images and keeps the rest in one out entry", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  res = eval_r("for (i in 1:50) plot(i)", new.env())
  expect_length(res$images, 3L)
  plots = ev_of(res, "plot")
  expect_length(plots, 50L)
  expect_equal(sum(vapply(plots, function(p) isTRUE(p$attached), NA)), 3L)
  ids = unique(vapply(plots[4:50], function(p) p$out_id, ""))
  expect_length(ids, 1L)
  stored = out_get(ids)
  expect_length(stored, 47L)
  expect_match(stored[1], "^plot 4: .*gptr-plot-[0-9a-f]+\\.png$")
})

test_that("a plot finished by low-level calls in later expressions is one image", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  res = eval_r("plot(1:10)\nabline(h = 5)\nlines(10:1)\npoints(3, 3)", new.env())
  expect_length(res$images, 1L)
  expect_length(ev_of(res, "plot"), 1L)
})

test_that("a plotting evaluation under Rscript leaves no Rplots.pdf in the working directory", {
  skip_on_cran()
  dir = withr::local_tempdir()
  script = file.path(dir, "plot.R")
  writeLines(c(
    tracemem_loader(),
    "ev = get('eval_r', envir = asNamespace('gptr'))",
    "res = ev('plot(1:10); hist(rnorm(5))', new.env())",
    "cat(res$status, length(res$images), '\\n')"
  ), script)
  libs = paste(.libPaths(), collapse = .Platform$path.sep)
  out = processx::run(rscript_path(), c("--vanilla", script), wd = dir, error_on_status = FALSE,
                      env = c("current", R_LIBS = libs))
  expect_equal(out$status, 0L)
  expect_match(out$stdout, "ok 2")
  expect_false(file.exists(file.path(dir, "Rplots.pdf")))
})

test_that("the gptr shim reaches gptr:: when gptr is not visible from envir", {
  e = new.env(parent = baseenv())
  res = eval_r("r = gptr_return(5)", e)
  expect_equal(res$status, "ok")
  expect_equal(e$r, 5)
})

test_that("an evaluation with an agent stream leaves .Random.seed identical (IC-61)", {
  withr::local_seed(42)
  before = get(".Random.seed", envir = globalenv())
  st1 = new.env()
  st1$id = "s0123456789"
  e1 = new.env()
  res = eval_r("x = stats::runif(3)", e1, rng = st1)
  expect_equal(res$status, "ok")
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  st2 = new.env()
  st2$id = "s0123456789"
  e2 = new.env()
  eval_r("x = stats::runif(3)", e2, rng = st2)
  expect_identical(e1$x, e2$x)
})

test_that("arguments are validated", {
  expect_error(eval_r(1, new.env()), class = "gptr_error_invalid_argument")
  expect_error(eval_r("1", list()), class = "gptr_error_invalid_argument")
  expect_error(eval_r("1", new.env(), plots = "maybe"), class = "gptr_error_invalid_argument")
  expect_error(eval_r("1", new.env(), rng = list()), class = "gptr_error_invalid_argument")
})

# Added beyond the plan's Task 8 blocks (P09 Task 8 evidence in dev/progress/P09.md, D-055).

test_that("gptr's own PNG rendering is not reported as a change the code made", {
  # The first replay to PNG in a process loads ragg (and systemfonts, textshaping); the session
  # state is compared before rendering, so the model is not told its code loaded them.
  skip_on_cran()
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  dir = withr::local_tempdir()
  script = file.path(dir, "render.R")
  writeLines(c(
    tracemem_loader(),
    "ev = get('eval_r', envir = asNamespace('gptr'))",
    "before = loadedNamespaces()",
    "res = ev('plot(1:10)', new.env())",
    "cat('images', length(res$images), '\\n')",
    "cat('rendering loaded:', setdiff(loadedNamespaces(), before), '\\n')",
    "cat('reported loaded:', deparse(res$changes$loaded), '\\n')",
    "cat('reported envvars:', deparse(res$changes$envvars), '\\n')"
  ), script)
  libs = paste(.libPaths(), collapse = .Platform$path.sep)
  out = processx::run(rscript_path(), c("--vanilla", script), wd = dir, error_on_status = FALSE,
                      env = c("current", R_LIBS = libs))
  expect_equal(out$status, 0L)
  # the child's stdout is a text-mode stream on Windows, where each "\n" arrives as CRLF
  printed = gsub("\r\n", "\n", out$stdout, fixed = TRUE)
  expect_match(printed, "images 1 \n", fixed = TRUE)
  if (requireNamespace("ragg", quietly = TRUE)) {
    expect_match(printed, "rendering loaded:[^\n]* ragg")
  }
  expect_match(printed, "reported loaded: character(0) \n", fixed = TRUE)
  expect_match(printed, "reported envvars: character(0) \n", fixed = TRUE)
})

test_that("added promises and active bindings are reported by kind and never forced", {
  e = new.env()
  code = paste0("delayedAssign('p', stop('forced'))\n",
                "makeActiveBinding('ab', function() 1, environment())")
  res = eval_r(code, e)
  expect_equal(res$status, "ok")
  expect_equal(res$changes$objects$added, c("ab", "p"))
  expect_equal(res$changes$objects$lines, c("+ ab <active>", "+ p <promise>"))
  expect_true(rlang::env_binding_are_lazy(e, "p"))
})

test_that("non-ASCII and invalid object names are reported as valid UTF-8, never an R error", {
  # ls() returns a name parsed from code (donn<e9>es) with unknown encoding, which R's radix
  # sort refuses: env_diff() threw after the code had run. R parses such a name only in a UTF-8
  # locale.
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "non-ASCII names parse only in a UTF-8 locale")
  e = new.env()
  res = expect_no_warning(eval_r(paste0("donn\u00e9es = 1:3\n",
                                        "assign(rawToChar(as.raw(c(0x61, 0xff))), 2)"), e))
  expect_equal(res$status, "ok")
  expect_equal(e[["donn\u00e9es"]], 1:3)
  expect_length(res$changes$objects$added, 2L)
  lines = res$changes$objects$lines
  expect_true(all(validUTF8(lines)))
  expect_equal(lines, c("+ a<ff> <numeric length 1>", "+ donn\u00e9es <integer length 3>"))
  res = eval_r("donn\u00e9es[1] = 0L\nrm(list = rawToChar(as.raw(c(0x61, 0xff))))", e)
  expect_equal(res$status, "ok")
  expect_equal(res$changes$objects$lines, c("~ donn\u00e9es <integer> modified", "- a<ff> removed"))
})

test_that("code that is not valid UTF-8 is a parse error, not an R error", {
  # In other locales as_utf8() reads the bytes as native text, which makes them valid UTF-8
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "bytes are invalid UTF-8 only in a UTF-8 locale")
  e = new.env()
  bad = rawToChar(as.raw(c(0x78, 0x20, 0x3d, 0x20, 0x27, 0xff, 0x27)))
  res = expect_no_warning(eval_r(bad, e))
  expect_s3_class(res, "gptr_eval_result")
  expect_equal(res$status, "parse_error")
  expect_equal(res$n_total, 0L)
  expect_match(ev_of(res, "error")[[1]]$message, "^<gptr>: the code is not valid UTF-8")
  expect_false(exists("x", envir = e, inherits = FALSE))
})

test_that("a message sink the code leaves open is undone, also over the user's own one", {
  # eval_r() stops at the first error, so code that diverts messages and fails before its reset
  # line left the user's later errors and messages going into the code's file (review round 1)
  e = new.env()
  n_msg = sink.number(type = "message")
  conns = nrow(showConnections())
  mine = NULL
  withr::defer({
    if (sink.number(type = "message") != n_msg) sink(type = "message")
    for (con in list(e$zz1, e$zz2, mine)) {
      if (inherits(con, "connection")) try(close(con), silent = TRUE)
    }
  })
  f1 = withr::local_tempfile()
  f2 = withr::local_tempfile()
  code = "%s = file('%s', 'w'); sink(%s, type = 'message'); message('m'); stop('failed')"
  res = eval_r(sprintf(code, "zz1", gsub("\\\\", "/", f1), "zz1"), e)
  expect_equal(res$status, "error")
  expect_equal(vapply(ev_of(res, "message"), function(ev) ev$text, ""), "m\n")
  expect_equal(sink.number(type = "message"), n_msg)
  expect_true(isOpen(e$zz1))
  # The user's own message sink, replaced by the code's, is pointed back to
  mine = textConnection(NULL, "w")
  sink(mine, type = "message")
  n_mine = sink.number(type = "message")
  res = eval_r(sprintf(code, "zz2", gsub("\\\\", "/", f2), "zz2"), e)
  n_after = sink.number(type = "message")
  cat("user line\n", file = stderr())
  sink(type = "message")
  user = textConnectionValue(mine)
  expect_equal(res$status, "error")
  expect_equal(n_after, n_mine)
  expect_equal(user, "user line")
  close(mine)
  close(e$zz1)
  close(e$zz2)
  expect_equal(readLines(f1), character())
  expect_equal(readLines(f2), character())
  expect_equal(sink.number(type = "message"), n_msg)
  expect_equal(nrow(showConnections()), conns)
})

test_that("a message sink on the capture connection is undone before that connection closes", {
  # While output is captured, stdout() is the capture connection, so sink(stdout(), type =
  # 'message') pointed messages at it, and closing it threw from eval_r() before the options,
  # the plot device and the message sink were restored (review round 2)
  n_msg = sink.number(type = "message")
  conns = nrow(showConnections())
  dev = grDevices::dev.cur()
  devs = grDevices::dev.list()
  before = getAllConnections()
  opts = lapply(stats::setNames(nm = c("width", "max.print", "askYesNo", "try.outFile")),
                getOption)
  tidy = function() {
    if (sink.number(type = "message") != n_msg) sink(type = "message")
    options(opts)
    for (d in setdiff(grDevices::dev.list(), devs)) grDevices::dev.off(d)
    for (k in setdiff(getAllConnections(), before)) try(close(getConnection(k)), silent = TRUE)
  }
  mine = NULL
  withr::defer({
    tidy()
    if (inherits(mine, "connection")) try(close(mine), silent = TRUE)
  })
  codes = c(ok = "sink(stdout(), type = 'message'); message('m'); x = 1",
            error = "sink(stdout(), type = 'message'); message('m'); stop('failed')")
  for (tee in c(FALSE, TRUE)) {
    for (status in names(codes)) {
      e = new.env()
      res = tryCatch(eval_r(codes[[status]], e, plots = "capture", tee = tee),
                     error = function(err) err)
      expect_s3_class(res, "gptr_eval_result")
      expect_equal(res$status, status)
      expect_equal(sink.number(type = "message"), n_msg)
      expect_equal(getOption("width"), opts$width)
      expect_identical(getOption("askYesNo"), opts$askYesNo)
      expect_equal(grDevices::dev.cur(), dev)
      expect_equal(nrow(showConnections()), conns)
      tidy()
    }
  }
  # Over the user's own message sink: messages go back to it, not into a closed capture file
  mine = textConnection(NULL, "w")
  sink(mine, type = "message")
  n_mine = sink.number(type = "message")
  res = tryCatch(eval_r(codes[["error"]], new.env()), error = function(err) err)
  n_after = sink.number(type = "message")
  cat("user line\n", file = stderr())
  sink(type = "message")
  user = textConnectionValue(mine)
  close(mine)
  mine = NULL
  expect_s3_class(res, "gptr_eval_result")
  expect_equal(n_after, n_mine)
  expect_equal(user, "user line")
  expect_equal(sink.number(type = "message"), n_msg)
  expect_equal(nrow(showConnections()), conns)
  # The code closes the user's message sink and the capture connection; the reopened capture
  # connection takes the user's number, and messages must not be pointed at it
  mine = textConnection(NULL, "w")
  sink(mine, type = "message")
  code = paste0("{ con = stdout(); sink(); close(con); sink(type = 'message'); ",
                "close(getConnection(%d)) }\ncat('o\\n'); x = 1")
  res = tryCatch(eval_r(sprintf(code, sink.number(type = "message")), new.env()),
                 error = function(err) err)
  n_after = sink.number(type = "message")
  conns_after = nrow(showConnections())
  tidy()
  mine = NULL
  expect_s3_class(res, "gptr_eval_result")
  expect_equal(res$status, "ok")
  expect_equal(n_after, 2L)
  expect_equal(conns_after, conns)
})

test_that("a visible value is printed with the print methods visible from envir", {
  # As at the console (R's PrintValueEnv()): print(x) is evaluated in a child of the home, so a
  # method defined in a function-frame home or an overlay prints `x`, `(x)` and `f(x)` alike
  # (review round 1)
  code = paste("print.gptrzz = function(x, ...) cat('custom zz\\n')",
               "x = structure(1, class = 'gptrzz')", "x", "(x)", "identity(x)", sep = "\n")
  h = function() eval_r(code, environment())
  res = h()
  expect_equal(res$status, "ok")
  expect_equal(res$outputs, list(character(), character(), "custom zz", "custom zz", "custom zz"))
  home = new.env(parent = globalenv())
  overlay = new.env(parent = home)
  res = eval_r(code, overlay)
  expect_equal(res$outputs, list(character(), character(), "custom zz", "custom zz", "custom zz"))
  expect_setequal(ls(overlay, all.names = TRUE), c("print.gptrzz", "x"))
  expect_length(ls(home, all.names = TRUE), 0L)
  res = eval_r("structure(2, class = 'gptrzz')\nprint.gptrzz = function(x, ...) stop('bad')",
               new.env())
  expect_equal(res$outputs[[1]], c("[1] 2", "attr(,\"class\")", "[1] \"gptrzz\""))
  res = eval_r("print.gptrzz = function(x, ...) stop('bad print')\nstructure(2, class = 'gptrzz')",
               new.env())
  expect_equal(res$status, "error")
  expect_equal(ev_of(res, "error")[[1]]$message, "bad print")
  expect_equal(c(res$n_done, res$n_total), c(1L, 2L))
  # The console dispatches print() for objects and functions only: the empty symbol (an
  # argument without a default) prints as a blank line, and a function uses the home's method
  # (review round 2)
  home = new.env(parent = globalenv())
  code = paste("f = function(a, b = 2) NULL", "formals(f)$a", "alist(a = )$a",
               "print.function = function(x, ...) cat('custom fn\\n')", "(f)", "after = 1",
               sep = "\n")
  res = eval_r(code, home)
  expect_equal(res$status, "ok")
  expect_equal(c(res$n_done, res$n_total), c(6L, 6L))
  expect_equal(home$after, 1)
  expect_equal(res$outputs, list(character(), character(), character(), character(), "custom fn",
                                 character()))
})

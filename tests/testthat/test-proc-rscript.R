# Fixed R entry points use the existing process engine without changing caller state.
test_that("Rscript workers use a fixed bootstrap and explicit installed library", {
  dir = withr::local_tempdir()
  got = NULL
  handle = new.env(parent = emptyenv())
  lib = normalizePath(tempdir(), winslash = "/")
  local_mocked_bindings(proc_rscript_library = function() lib,
    proc_spawn = function(command, args, env, ...) {
      got <<- list(command = command, args = args, env = env, dots = list(...))
      handle
    })
  withr::local_seed(20261011)
  before = list(env = Sys.getenv(), options = options(), wd = getwd(),
                seed = get(".Random.seed", globalenv()))
  input = list(file.path(dir, "spec.rds"), file.path(dir, "result.rds"))
  env = c(GPTR_TEST_EMPTY = "", GPTR_TEST_TEXT = "\u03bb-\u96ea")
  p = proc_rscript("worker", input, dir = dir, env = env, stdin = "|")
  after = list(env = Sys.getenv(), options = options(), wd = getwd(),
               seed = get(".Random.seed", globalenv()))
  expect_identical(after, before)
  expect_identical(p, handle)
  expect_identical(got$command, rscript_path())
  expect_identical(got$args[[1L]], "--vanilla")
  expect_identical(got$env, env)
  expect_identical(got$dots$stdin, "|")
  payload = readRDS(got$args[[3L]])
  expect_named(payload, c("entry", "args", "libpaths", "library"))
  expect_identical(payload$entry, "worker")
  expect_identical(payload$args, input)
  expect_identical(payload$libpaths, .libPaths())
  expect_identical(payload$library, lib)
  expect_false(any(vapply(payload, is.function, logical(1))))
  script = paste(readLines(got$args[[2L]], warn = FALSE), collapse = "\n")
  expect_match(script, "loadNamespace", fixed = TRUE)
  expect_match(script, "include.site = FALSE", fixed = TRUE)
  expect_false(grepl("pkgload|Sys.setenv|Sys.unsetenv|source[(]", script))
})

test_that("the coaching child entry loads the installed namespace as a worker does (P29)", {
  dir = withr::local_tempdir()
  got = NULL
  lib = normalizePath(tempdir(), winslash = "/")
  local_mocked_bindings(proc_rscript_library = function() lib,
    proc_spawn = function(command, args, env, ...) {
      got <<- list(args = args)
      new.env(parent = emptyenv())
    })
  input = list(file.path(dir, "spec.rds"), file.path(dir, "result.json"))
  proc_rscript("child", input, dir = dir, env = character())
  payload = readRDS(got$args[[3L]])
  expect_named(payload, c("entry", "args", "libpaths", "library"))
  expect_identical(payload$entry, "child")
  expect_identical(payload$args, input)
  expect_identical(payload$library, lib)
  script = paste(readLines(got$args[[2L]], warn = FALSE), collapse = "\n")
  expect_match(script, "c('worker', 'child')", fixed = TRUE)
  expect_true(is.function(get(paste0(payload$entry, "_main"), envir = asNamespace("gptr"))))
})

test_that("artifact bootstrap is detached from the caller and gptr namespace", {
  dir = withr::local_tempdir()
  got = NULL
  local_mocked_bindings(proc_spawn = function(command, args, env, ...) {
    got <<- list(args = args, env = env)
    new.env(parent = emptyenv())
  })
  proc_rscript("artifact", list(dir = dir, token = "SYNTHETIC-ARTIFACT-TOKEN"),
               dir = dir, env = c(PATH = "synthetic path"), .fun = artifact_serve)
  payload = readRDS(got$args[[3L]])
  expect_named(payload, c("entry", "args", "libpaths", "fun"))
  expect_identical(environment(payload$fun), baseenv())
  expect_length(grepRaw("srcfile", serialize(payload$fun, NULL), fixed = TRUE), 0L)
  expect_length(grepRaw("namespace:gptr", serialize(payload$fun, NULL), fixed = TRUE), 0L)
  expect_false(any(grepl("SYNTHETIC-ARTIFACT-TOKEN", got$args, fixed = TRUE)))
  expect_identical(got$env, c(PATH = "synthetic path"))
  if (!is_windows()) {
    expect_identical(as.integer(file.info(got$args[[3L]])$mode), strtoi("600", 8L))
    expect_identical(as.integer(file.info(got$args[[2L]])$mode), strtoi("600", 8L))
  }
})

test_that("Rscript bootstrap refuses unknown entries and reused launch files", {
  dir = withr::local_tempdir()
  expect_error(proc_rscript("other", list(), dir, env = character()),
               class = "gptr_error_invalid_argument")
  writeLines("foreign", file.path(dir, "bootstrap.R"))
  expect_error(proc_rscript("artifact", list(), dir, env = character()),
               class = "gptr_error_invalid_argument")
  expect_identical(readLines(file.path(dir, "bootstrap.R")), "foreign")
})

test_that("Rscript spawn errors retain owned launch files for confirmed cleanup", {
  dir = withr::local_tempdir()
  local_mocked_bindings(proc_spawn = function(...) stop("synthetic launch failure"))
  before = Sys.getenv()
  expect_error(proc_rscript("artifact", list(), dir, env = c(GPTR_TEST_EMPTY = ""),
                            .fun = artifact_serve),
               "synthetic launch failure", fixed = TRUE)
  expect_identical(Sys.getenv(), before)
  expect_true(file.exists(file.path(dir, "bootstrap.rds")))
  expect_true(file.exists(file.path(dir, "bootstrap.R")))
})

test_that("a native process handle is captured before marker registration can fail", {
  p = new.env(parent = emptyenv())
  seen = NULL
  settled = 0L
  local_mocked_bindings(proc_mark = function(...) stop("synthetic marker failure"),
    kill_all = function(process, ...) {
      settled <<- settled + 1L
      TRUE
    })
  local_mocked_bindings(process = list(new = function(...) p), .package = "processx")
  expect_error(proc_spawn(rscript_path(), .on_spawn = function(process) seen <<- process),
               "synthetic marker failure", fixed = TRUE)
  expect_identical(seen, p)
  expect_identical(settled, 1L)
})


test_that("registration rollback preserves the original error even when cleanup interrupts", {
  original = structure(list(message = "owned marker failure", call = NULL),
                       class = c("owned_marker_error", "error", "condition"))
  p = new.env(parent = emptyenv())
  local_mocked_bindings(proc_mark = function(...) stop(original),
    kill_all = function(...) {
      signalCondition(structure(list(message = "cleanup interrupt"),
                                class = c("interrupt", "condition")))
    })
  local_mocked_bindings(process = list(new = function(...) p), .package = "processx")
  error = tryCatch(proc_spawn(rscript_path()), error = identity,
                   interrupt = function(e) e)
  expect_identical(error, original)
})

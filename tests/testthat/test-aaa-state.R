# Package state, load-time registry and redaction hook (Task 2); service table (Task 3).

source_root = function() {
  candidates = c(
    testthat::test_path("..", ".."),
    testthat::test_path("..", "..", "00_pkg_src", "gptr")
  )
  for (dir in candidates) {
    if (file.exists(file.path(dir, "DESCRIPTION")) && dir.exists(file.path(dir, "R"))) {
      return(normalizePath(dir, winslash = "/"))
    }
  }
  NULL
}

test_that("`the` holds P01's fields and %||% is the null default", {
  expect_true(is.environment(the))
  for (field in c("on_load", "on_unload", "once", "out", "services", "redactor", "load_errors")) {
    expect_true(exists(field, envir = the, inherits = FALSE), label = field)
  }
  expect_identical(NULL %||% 2, 2)
  expect_identical(1 %||% 2, 1)
})

test_that("on_load() stores the expression unevaluated with its environment", {
  entries = the$on_load
  withr::defer({
    the$on_load = entries
  })
  the$on_load = list()
  on_load(this_function_does_not_exist_yet())
  expect_length(the$on_load, 1L)
  expect_identical(the$on_load[[1]]$expr, quote(this_function_does_not_exist_yet()))
  expect_identical(the$on_load[[1]]$env, environment())
})

test_that("on_load_run() evaluates in order and records failures", {
  errors = the$load_errors
  withr::defer({
    the$load_errors = errors
  })
  box = new.env()
  entries = list(
    list(expr = quote(assign("x", 1, envir = box)), env = environment()),
    list(expr = quote(stop("broken declaration")), env = environment()),
    list(expr = quote(assign("y", box$x + 1, envir = box)), env = environment())
  )
  expect_false(on_load_run(entries))
  expect_identical(box$y, 2)
  expect_match(conditionMessage(the$load_errors[[length(the$load_errors)]]$error), "broken")
})

test_that("on_unload() accepts only functions", {
  expect_error(on_unload("not a function"), class = "gptr_error_invalid_argument")
})

test_that("redact_hook() is the identity until a redactor is installed (IC-34)", {
  expect_identical(redact_hook("key sk-123"), "key sk-123")
  old = redactor_set(function(x, profile = "persist") gsub("sk-[0-9]+", "[secret:KEY]", x))
  withr::defer(redactor_set(old))
  expect_identical(redact_hook("key sk-123"), "key [secret:KEY]")
  redactor_set(function(x, profile = "persist") stop("redactor broke"))
  expect_identical(redact_hook(c("a", "b")), c("[redaction failed]", "[redaction failed]"))
  expect_error(redactor_set("redact"), class = "gptr_error_invalid_argument")
})

test_that("a later-collating file can call on_load() at top level when installed (IC-32)", {
  skip_on_cran()
  src = source_root()
  skip_if(is.null(src), "package sources not found")
  skip_if_not(file.exists(file.path(src, "NAMESPACE")), "NAMESPACE not generated yet")
  tmp = withr::local_tempdir()
  pkg = file.path(tmp, "gptr")
  lib = file.path(tmp, "lib")
  dir.create(pkg)
  dir.create(lib)
  file.copy(file.path(src, c("DESCRIPTION", "NAMESPACE")), pkg)
  file.copy(file.path(src, "R"), pkg, recursive = TRUE)
  writeLines(
    "on_load(assign(\"probe\", \"loaded at .onLoad\", envir = the))",
    file.path(pkg, "R", "zz-probe.R")
  )
  env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  exe = if (.Platform$OS.type == "windows") ".exe" else ""
  install = processx::run(
    file.path(R.home("bin"), paste0("R", exe)),
    c("CMD", "INSTALL", "--no-docs", "--no-multiarch", paste0("--library=", lib), pkg),
    env = env, error_on_status = FALSE, timeout = 300
  )
  expect_identical(install$status, 0L, info = install$stderr)
  code = sprintf(
    "library(gptr, lib.loc = '%s'); cat(get('the', asNamespace('gptr'))$probe)",
    normalizePath(lib, winslash = "/")
  )
  loaded = processx::run(
    file.path(R.home("bin"), paste0("Rscript", exe)), c("--vanilla", "-e", code),
    env = env, error_on_status = FALSE, timeout = 120
  )
  expect_identical(loaded$stdout, "loaded at .onLoad")
})

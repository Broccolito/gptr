library(testthat)

checker_path = testthat::test_path("check-connections.R")
checker = new.env(parent = baseenv())
if (file.exists(checker_path)) sys.source(checker_path, envir = checker)

test_that("connection gate permits unchanged and explicitly closed connections", {
  expect_equal(checker$check_connections(42), 42)
  expect_null(checker$check_connections({
    con = file(tempfile(), open = "w")
    close(con)
    NULL
  }))
})

test_that("connection gate rejects a deliberately leaked connection", {
  con = NULL
  withr::defer(if (!is.null(con)) close(con))
  expect_error(checker$check_connections({
    con = file(tempfile(), open = "w")
    NULL
  }), "R connection table changed", fixed = TRUE)
})

test_that("connection gate preserves a failing suite's error", {
  expect_error(checker$check_connections(stop("test suite failed")), "test suite failed")
})

test_that("connection gate uses check-mode supervision and restores the caller's option", {
  withr::local_options(gptr.supervise = TRUE)
  expect_false(checker$check_connections(getOption("gptr.supervise")))
  expect_true(getOption("gptr.supervise"))
  expect_error(checker$check_connections({
    expect_false(getOption("gptr.supervise"))
    stop("test suite failed")
  }), "test suite failed")
  expect_true(getOption("gptr.supervise"))
})

test_that("connection gate compares the tables before reporting failed tests", {
  con = NULL
  withr::defer(if (!is.null(con)) close(con))
  cnd = tryCatch(checker$check_connections({
    con = file(tempfile(), open = "w")
    "results"
  }, failures = function(value) 3L), error = identity)
  expect_s3_class(cnd, "error")
  expect_match(conditionMessage(cnd), "3 failed test(s)", fixed = TRUE)
  expect_match(conditionMessage(cnd), "R connection table changed", fixed = TRUE)
})

test_that("connection gate fails on failed tests even when no connection leaked", {
  expect_error(checker$check_connections("results", failures = function(value) 2L),
               "2 failed test(s)", fixed = TRUE)
  expect_identical(checker$check_connections("results", failures = function(value) 0L),
                   "results")
})

test_that("connection gate still compares the tables when the suite errors", {
  con = NULL
  withr::defer(if (!is.null(con)) close(con))
  cnd = tryCatch(checker$check_connections({
    con = file(tempfile(), open = "w")
    stop("test suite failed")
  }), error = identity)
  expect_match(conditionMessage(cnd), "test suite failed", fixed = TRUE)
  expect_match(conditionMessage(cnd), "R connection table changed", fixed = TRUE)
})

test_that("suite_failures() counts failed expectations and errored tests", {
  dir = withr::local_tempdir()
  file = file.path(dir, "test-sample.R")
  writeLines(c(
    "test_that(\"passes\", expect_true(TRUE))",
    "test_that(\"fails twice\", {",
    "  expect_true(FALSE)",
    "  expect_identical(1, 2)",
    "})",
    "test_that(\"errors\", stop(\"boom\"))",
    "test_that(\"skips\", skip(\"not here\"))"
  ), file)
  results = testthat::test_file(file, reporter = "silent", stop_on_failure = FALSE)
  expect_identical(checker$suite_failures(results), 3L)
})

test_that("the gate runs the whole suite, then fails on its failures and leaks", {
  seen = new.env()
  fake_test = function(...) {
    seen$args = list(...)
    "results"
  }
  expect_error(checker$run_gate(fake_test, failures = function(value) 1L),
               "1 failed test(s)", fixed = TRUE)
  expect_identical(seen$args, list(stop_on_failure = FALSE))
  expect_identical(checker$run_gate(fake_test, failures = function(value) 0L), "results")
})

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

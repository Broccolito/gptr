checker = new.env(parent = baseenv())
sys.source(testthat::test_path("check-connections.R"), envir = checker)

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

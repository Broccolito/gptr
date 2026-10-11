# Real Windows coverage of D-019; Unix executes the same control cases. The only skip is
# the repository-required CRAN process-test gate. A separate parent bounds native hangs.
test_that("real child duplex backpressure preserves every 4 MB stdout and stderr line", {
  skip_on_cran()
  x = bp_run("duplex")
  if (!bp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$complete)
  expect_identical(x$result$output_lines, 40000L)
  expect_identical(x$result$error_lines, 40000L)
  expect_true(x$result$exact_stdout)
  expect_true(x$result$exact_stderr)
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

test_that("a real no-reader child returns the typed stdin timeout under external bounds", {
  skip_on_cran()
  x = bp_run("timeout")
  if (!bp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$timeout_class)
  expect_identical(x$result$what, "stdin")
  expect_identical(x$result$seconds, 2)
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("a real queued 4 MB write leaves reactor cancellation responsive with no late exit", {
  skip_on_cran()
  x = bp_run("cancel")
  if (!bp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$queued)
  expect_true(x$result$complete)
  expect_true(x$result$cancelled)
  expect_identical(x$result$exit_callbacks, 0L)
})

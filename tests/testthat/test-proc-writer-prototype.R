# Experimental test transport, not proof that the current package runtime is repaired.
# Every case runs on the actual host OS inside the independent D-019 watchdog.
test_that("owned writer prototype preserves every 4 MB duplex stdout and stderr line", {
  skip_on_cran()
  x = wp_run("duplex")
  if (!wp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$complete)
  expect_identical(x$result$accepted_bytes, 4000000L)
  expect_identical(x$result$output_lines, 40000L)
  expect_identical(x$result$error_lines, 40000L)
  expect_true(x$result$exact_stdout)
  expect_true(x$result$exact_stderr)
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

test_that("owned writer prototype returns a typed no-reader stdin timeout", {
  skip_on_cran()
  x = wp_run("timeout")
  if (!wp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$complete)
  expect_true(x$result$timeout_class)
  expect_identical(x$result$what, "stdin")
  expect_identical(x$result$seconds, 2)
  expect_lt(x$result$accepted_bytes, x$result$input_bytes)
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("owned writer prototype cancels a queued 4 MB write without a late exit", {
  skip_on_cran()
  x = wp_run("cancel")
  if (!wp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$complete)
  expect_true(x$result$queued)
  expect_true(x$result$cancelled)
  expect_lt(x$result$accepted_bytes, x$result$input_bytes)
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("owned writer prototype preserves queued binary NUL and UTF-8 bytes", {
  skip_on_cran()
  x = wp_run("binary")
  if (!wp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$complete)
  expect_true(x$result$binary_exact)
  expect_identical(x$result$accepted_bytes, x$result$input_bytes)
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

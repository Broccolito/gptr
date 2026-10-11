test_that("backpressure enumeration tolerates only a dead original parent exit race", {
  handle = new.env(parent = emptyenv())
  error = structure(list(message = "parent exited", call = NULL),
    class = c("no_such_process", "error", "condition"))
  children = function(p, recursive) {
    expect_identical(p, handle)
    expect_true(recursive)
    stop(error)
  }
  alive = function(p) {
    expect_identical(p, handle)
    FALSE
  }
  expect_identical(bp_child_handles(handle, children, alive), list())
})

test_that("backpressure enumeration preserves the returned original child handles", {
  handle = new.env(parent = emptyenv())
  child = new.env(parent = emptyenv())
  children = function(p, recursive) {
    expect_identical(p, handle)
    expect_true(recursive)
    list(child)
  }
  alive = function(p) stop("No recovery check is needed after successful enumeration.")
  expect_identical(bp_child_handles(handle, children, alive), list(child))
})

test_that("backpressure enumeration fails closed for live and unknown parent identities", {
  handle = new.env(parent = emptyenv())
  error = structure(list(message = "observation unavailable", call = NULL, errno = 13L),
    class = c("os_error", "ps_error", "error", "condition"))
  children = function(p, recursive) {
    expect_identical(p, handle)
    expect_true(recursive)
    stop(error)
  }
  for (state in c(TRUE, NA)) {
    alive = function(p) {
      expect_identical(p, handle)
      state
    }
    actual = tryCatch(bp_child_handles(handle, children, alive), error = identity)
    expect_identical(actual, error)
  }
})

test_that("backpressure sample diagnostics are bounded and omit arbitrary messages", {
  error = structure(list(message = "FAKE-sampler-message-canary", call = NULL,
    errno = 2L, pid = 123L, path = "FAKE-sampler-path-canary"),
    class = c("os_error", "ps_error", "error", "condition"))
  actual = bp_sample_error("children", error)
  expect_identical(actual, list(stage = "children",
    class = c("os_error", "ps_error", "error", "condition"), errno = 2L, pid = 123L))
  expect_false(any(grepl("canary", unlist(actual), fixed = TRUE)))
  error$errno = c(2L, 3L)
  error$pid = NA_real_
  class(error) = c(paste0("class", seq_len(20L)), strrep("x", 65L), "bad class")
  actual = bp_sample_error("memory", error)
  expect_length(actual$class, 8L)
  expect_null(actual$errno)
  expect_null(actual$pid)
  expect_lte(max(nchar(actual$class, type = "bytes")), 64L)
})

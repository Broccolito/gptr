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


test_that("backpressure observer diagnostics retain only current fixed reason codes", {
  source = readLines(test_path("fixtures", "bp-disk-observer.py"))
  lines = grep("raise ObservationError", source, value = TRUE, fixed = TRUE)
  codes = sort(unique(sub(".*ObservationError\\(\"([a-z-]+)\"\\).*", "\\1", lines)))
  expect_length(codes, 40L)
  prefixes = c("", "ObservationError: ", "gptr_owned_disk_observer.ObservationError: ")
  for (code in codes) {
    for (prefix in prefixes) {
      error = structure(list(message = paste0(prefix, code, "\r\nFAKE-private-path"),
        call = NULL), class = c("gptr_owned_disk_observer.ObservationError", "error", "condition"))
      actual = bp_sample_error("files", error)
      expect_identical(actual$observer_reason, code)
    }
  }
})

test_that("backpressure observer diagnostics reject unknown or private message forms", {
  messages = c("", "observer-new-unknown", "FAKE-private-path: observer-entry-limit",
    "other.ObservationError: observer-entry-limit", " observer-entry-limit",
    "gptr_owned_disk_observer.ObservationError: ObservationError: observer-entry-limit",
    "observer-entry-limit FAKE-private-path", "observer-entry-limit/FAKE-private-path",
    paste0("observer-entry-limit", strrep("x", 8192L)))
  for (message in messages) {
    error = structure(list(message = message, call = NULL),
      class = c("gptr_owned_disk_observer.ObservationError", "error", "condition"))
    actual = bp_sample_error("files", error)
    expect_identical(names(actual), c("stage", "class", "errno", "pid", "observer_reason"))
    expect_null(actual$observer_reason)
    expect_false(any(grepl("FAKE-private", unlist(actual), fixed = TRUE)))
  }
  error = structure(list(message = "observer-entry-limit", call = NULL),
    class = c("gptr_owned_disk_observer.ObservationError", "error", "condition"))
  expect_identical(names(bp_sample_error("memory", error)), c("stage", "class", "errno", "pid"))
  class(error) = c("other.ObservationError", "error", "condition")
  expect_identical(names(bp_sample_error("files", error)), c("stage", "class", "errno", "pid"))
})

test_that("backpressure observer diagnostics preserve the original typed failure", {
  error = structure(list(message = paste0("gptr_owned_disk_observer.ObservationError: ",
    "observer-entry-disappearance-uncertain\nFAKE-private-path"), call = NULL,
    errno = 13L, pid = 123L),
    class = c("gptr_owned_disk_observer.ObservationError", "error", "condition"))
  before = serialize(error, NULL)
  actual = bp_sample_error("files", error)
  expect_identical(actual$observer_reason, "observer-entry-disappearance-uncertain")
  expect_identical(actual$stage, "files")
  expect_identical(actual$class, class(error))
  expect_identical(actual$errno, 13L)
  expect_identical(actual$pid, 123L)
  expect_identical(serialize(error, NULL), before)
  caught = tryCatch(stop(error), error = identity)
  expect_identical(caught, error)
  expect_false(any(grepl("FAKE-private", unlist(actual), fixed = TRUE)))
  old_scope = environment(bp_observer_reason)
  for (mode in c("malformed", "error", "interrupt")) {
    seen = new.env(parent = emptyenv())
    seen$calls = 0L
    scope = new.env(parent = old_scope)
    scope$conditionMessage = function(input) {
      seen$calls = seen$calls + 1L
      seen$input = input
      if (identical(mode, "malformed")) return(list("FAKE-private-path"))
      signal = structure(list(message = "FAKE-formatter-condition", call = NULL),
        class = c(if (mode == "interrupt") "interrupt" else "error", "condition"))
      stop(signal)
    }
    reason = bp_observer_reason
    environment(reason) = scope
    expect_null(reason("files", error))
    expect_identical(seen$calls, 1L)
    expect_identical(seen$input, error)
    expect_identical(serialize(error, NULL), before)
    expect_identical(environment(bp_observer_reason), old_scope)
  }
})

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
  # Evaluate the actual ordinary sampler branch without launching a child.
  walk = function(expression) {
    if (missing(expression)) return(list())
    found = list()
    if (is.call(expression) && length(expression) == 4L &&
        identical(expression[[1L]], as.name("if")) &&
        identical(expression[[2L]], as.name("observer_enabled"))) {
      other = expression[[4L]]
      if (is.call(other) && length(other) >= 2L &&
          is.call(other[[2L]]) && identical(other[[2L]][[1L]], as.name("=")) &&
          identical(other[[2L]][[2L]], as.name("files"))) found = list(other)
    }
    if (is.call(expression) || is.expression(expression) || is.pairlist(expression)) {
      for (part in as.list(expression)) found = c(found, walk(part))
    }
    found
  }
  branches = walk(body(bp_run))
  expect_length(branches, 1L)
  selected = branches[[1L]]
  sample = function(paths, present, sizes, declaration =
      list(list(entry = "dangling-file", target = "missing-target"))) {
    scope = new.env(parent = baseenv())
    scope$root = "owned"
    scope$rss = c(2, 3)
    scope$declared_links = declaration
    seen = new.env(parent = emptyenv())
    seen$info = character()
    scope$list.files = function(path, ...) {
      expect_identical(path, "owned")
      paths
    }
    scope$file.exists = function(path) {
      unname(present[match(path, names(present))])
    }
    scope$file.info = function(path, extra_cols) {
      expect_false(extra_cols)
      seen$info = path
      values = unname(sizes[match(path, names(sizes))])
      if (any(is.na(values) & !scope$file.exists(path))) warning("PUBLIC-MISSING-ENTRY")
      list(size = values)
    }
    value = eval(selected, envir = scope)
    list(value = value, info = seen$info)
  }
  paths = c("owned/keep", "owned/dangling-file")
  present = c("owned/keep" = TRUE, "owned/dangling-file" = FALSE,
    "owned/missing-target" = FALSE)
  sizes = c("owned/keep" = 7, "owned/dangling-file" = NA_real_)
  observed = new.env(parent = emptyenv())
  expect_warning({
    observed$value = sample(paths, present, sizes)
  }, NA)
  expect_identical(observed$value$value, c(rss = 5, disk = 7))
  expect_identical(observed$value$info, "owned/keep")
  # A replaced/present entry is measured, even at the declared name.
  present[["owned/dangling-file"]] = TRUE
  sizes[["owned/dangling-file"]] = 11
  observed$value = sample(paths, present, sizes)
  expect_identical(observed$value$value, c(rss = 5, disk = 18))
  expect_identical(observed$value$info, paths)
  # Unknown metadata for an existing entry retains the original fatal gate.
  sizes[["owned/dangling-file"]] = NA_real_
  expect_error(sample(paths, present, sizes), "Could not measure owned case files.", fixed = TRUE)
  present[["owned/dangling-file"]] = FALSE
  # A target that exists does not qualify for the narrow missing-pair filter.
  present[["owned/missing-target"]] = TRUE
  expect_warning({
    observed$value = sample(paths, present, sizes)
  }, "PUBLIC-MISSING-ENTRY")
  expect_identical(observed$value$info, paths)
  present[["owned/missing-target"]] = FALSE
  # Undeclared missing entries keep their visible warning and legacy measurement path.
  expect_warning({
    observed$value = sample(paths, present, sizes, declaration = list())
  }, "PUBLIC-MISSING-ENTRY")
  expect_identical(observed$value$info, paths)
  expect_error(sample(paths, present, sizes,
    declaration = list(list(entry = "other", target = "missing-target"))))
  present[["owned/dangling-file"]] = NA
  expect_error(sample(paths, present, sizes))
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

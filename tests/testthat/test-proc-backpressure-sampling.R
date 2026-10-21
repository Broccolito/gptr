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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
  source = readLines(test_path("fixtures", "bp-disk-observer.py"))
  lines = grep("raise (ObservationError|_EntryAbsent)", source, value = TRUE)
  codes = sort(unique(sub(".*(ObservationError|_EntryAbsent)\\(\"([a-z-]+)\"\\).*",
    "\\2", lines)))
  expect_length(codes, 47L)
  base_lines = grep("raise ObservationError", lines, value = TRUE, fixed = TRUE)
  base_codes = sub(".*ObservationError\\(\"([a-z-]+)\"\\).*", "\\1", base_lines)
  expect_identical(setdiff(codes, base_codes), "observer-parent-entry-absent")
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
  skip_on_cran()
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
  skip_on_cran()
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


test_that("backpressure census retries one ENOENT only with the same live parent", {
  skip_on_cran()
  handle = new.env(parent = emptyenv())
  child = new.env(parent = emptyenv())
  first = structure(list(message = "PUBLIC-CENSUS-ENOENT", call = NULL, errno = 2L),
    class = c("os_error", "ps_error", "error", "condition"))
  seen = new.env(parent = emptyenv())
  seen$calls = seen$checks = seen$recoveries = 0L
  children = function(p, recursive) {
    expect_identical(p, handle)
    expect_true(recursive)
    seen$calls = seen$calls + 1L
    if (seen$calls == 1L) stop(first)
    list(child)
  }
  alive = function(p) {
    expect_identical(p, handle)
    seen$checks = seen$checks + 1L
    TRUE
  }
  value = bp_child_handles(handle, children, alive)
  expect_identical(value, list(child))
  expect_identical(seen$calls, 2L)
  expect_identical(seen$checks, 2L)
  expect_identical(seen$recoveries, 0L)
  seen$calls = seen$checks = 0L
  value = bp_child_handles(handle, children, alive, recovered = function() {
    seen$recoveries = seen$recoveries + 1L
  })
  expect_identical(value, list(child))
  expect_identical(seen$calls, 2L)
  expect_identical(seen$checks, 2L)
  expect_identical(seen$recoveries, 1L)
  walk = function(expression) {
    if (missing(expression)) return(list())
    found = if (is.call(expression)) list(expression) else list()
    if (is.call(expression) || is.expression(expression) || is.pairlist(expression)) {
      for (part in as.list(expression)) found = c(found, walk(part))
    }
    found
  }
  calls = walk(body(bp_run))
  increments = Filter(function(call) {
    length(call) == 3L &&
      identical(call[[1L]], as.name("=")) &&
      identical(call[[2L]], quote(tracked$census_retries)) &&
      identical(call[[3L]], quote(tracked$census_retries + 1L))
  }, calls)
  expect_length(increments, 1L)
  witnesses = Filter(function(call) {
    identical(call[[1L]], as.name("list")) && "census_retries" %in% names(call)
  }, calls)
  expect_length(witnesses, 1L)
  expect_identical(witnesses[[1L]][["census_retries"]], quote(tracked$census_retries))
})

test_that("backpressure census preserves permission and uncertain parent observations", {
  skip_on_cran()
  handle = new.env(parent = emptyenv())
  first = structure(list(message = "PUBLIC-CENSUS-ENOENT", call = NULL, errno = 2L),
    class = c("os_error", "ps_error", "error", "condition"))
  variants = list(first, simpleError("PUBLIC-CENSUS-UNKNOWN"),
    structure(list(message = "PUBLIC-CENSUS-PERMISSION", call = NULL, errno = 13L),
      class = c("os_error", "ps_error", "error", "condition")))
  for (failure in variants) {
    for (state in list(FALSE, NA)) {
      seen = new.env(parent = emptyenv())
      seen$calls = 0L
      children = function(p, recursive) {
        seen$calls = seen$calls + 1L
        stop(failure)
      }
      actual = tryCatch(bp_child_handles(handle, children, function(p) state), error = identity)
      expect_identical(actual, failure)
      expect_identical(seen$calls, 1L)
    }
  }
  for (state in list(simpleError("PUBLIC-IDENTITY-ERROR"),
      structure(list(message = "PUBLIC-IDENTITY-INTERRUPT", call = NULL),
        class = c("interrupt", "condition")))) {
    children = function(p, recursive) stop(first)
    actual = tryCatch(bp_child_handles(handle, children, function(p) stop(state)),
      error = identity, interrupt = identity)
    expect_identical(actual, first)
  }
  for (errno in list(NULL, NA_real_, c(2L, 2L), TRUE, 13L)) {
    first$errno = errno
    seen = new.env(parent = emptyenv())
    seen$calls = 0L
    children = function(p, recursive) {
      seen$calls = seen$calls + 1L
      stop(first)
    }
    actual = tryCatch(bp_child_handles(handle, children, function(p) TRUE), error = identity)
    expect_identical(actual, first)
    expect_identical(seen$calls, 1L)
  }
})

test_that("backpressure census keeps the first condition when its sole retry is incomplete", {
  skip_on_cran()
  handle = new.env(parent = emptyenv())
  child = new.env(parent = emptyenv())
  first = structure(list(message = "PUBLIC-CENSUS-ENOENT", call = NULL, errno = 2L),
    class = c("os_error", "ps_error", "error", "condition"))
  variants = list(first, simpleError("PUBLIC-SECOND-ERROR"),
    structure(list(message = "PUBLIC-SECOND-INTERRUPT", call = NULL),
      class = c("interrupt", "condition")), FALSE)
  for (second in variants) {
    seen = new.env(parent = emptyenv())
    seen$calls = seen$recoveries = 0L
    children = function(p, recursive) {
      seen$calls = seen$calls + 1L
      if (seen$calls == 1L) stop(first)
      if (inherits(second, "condition")) stop(second)
      second
    }
    actual = tryCatch(bp_child_handles(handle, children, function(p) TRUE,
      recovered = function() seen$recoveries = seen$recoveries + 1L),
      error = identity, interrupt = identity)
    expect_identical(actual, first)
    expect_identical(seen$calls, 2L)
    expect_identical(seen$recoveries, 0L)
  }
  for (state in list(FALSE, NA)) {
    seen = new.env(parent = emptyenv())
    seen$calls = seen$checks = 0L
    children = function(p, recursive) {
      seen$calls = seen$calls + 1L
      if (seen$calls == 1L) stop(first)
      list(child)
    }
    alive = function(p) {
      seen$checks = seen$checks + 1L
      if (seen$checks == 1L) TRUE else state
    }
    actual = tryCatch(bp_child_handles(handle, children, alive), error = identity)
    expect_identical(actual, first)
    expect_identical(seen$calls, 2L)
  }
  seen = new.env(parent = emptyenv())
  seen$calls = 0L
  children = function(p, recursive) {
    seen$calls = seen$calls + 1L
    if (seen$calls == 1L) stop(first)
    warning("PUBLIC-RETRY-WARNING")
    list(child)
  }
  expect_warning({
    value = bp_child_handles(handle, children, function(p) TRUE)
  }, "PUBLIC-RETRY-WARNING", fixed = TRUE)
  expect_identical(value, list(child))
  children = function(p, recursive) {
    seen$calls = seen$calls + 1L
    if (seen$calls == 1L) stop(first)
    list(child)
  }
  for (failure in list(simpleError("PUBLIC-RETRY-PUBLICATION"),
      structure(list(message = "PUBLIC-RETRY-INTERRUPT", call = NULL),
        class = c("interrupt", "condition")))) {
    seen$calls = 0L
    actual = tryCatch(bp_child_handles(handle, children, function(p) TRUE,
      recovered = function() stop(failure)), error = identity, interrupt = identity)
    expect_identical(actual, first)
  }
})


test_that("backpressure census retries one ESRCH without changing failure ownership", {
  skip_on_cran()
  handle = new.env(parent = emptyenv())
  child = new.env(parent = emptyenv())
  first = structure(list(message = "PUBLIC-CENSUS-ESRCH", call = NULL, errno = 3L),
    class = c("os_error", "ps_error", "error", "condition"))
  before = serialize(first, NULL)
  seen = new.env(parent = emptyenv())
  seen$calls = seen$checks = seen$recoveries = 0L
  children = function(p, recursive) {
    expect_identical(p, handle)
    expect_true(recursive)
    seen$calls = seen$calls + 1L
    if (seen$calls == 1L) stop(first)
    list(child)
  }
  alive = function(p) {
    expect_identical(p, handle)
    seen$checks = seen$checks + 1L
    TRUE
  }
  recovered = function() seen$recoveries = seen$recoveries + 1L
  actual = tryCatch(bp_child_handles(handle, children, alive, recovered = recovered),
    error = identity, interrupt = identity)
  expect_identical(actual, list(child))
  expect_identical(seen$calls, 2L)
  expect_identical(seen$checks, 2L)
  expect_identical(seen$recoveries, 1L)
  for (state in list(FALSE, NA)) {
    seen$calls = seen$checks = seen$recoveries = 0L
    actual = tryCatch(bp_child_handles(handle, children, function(p) state,
      recovered = recovered), error = identity, interrupt = identity)
    expect_identical(actual, first)
    expect_identical(seen$calls, 1L)
    expect_identical(seen$recoveries, 0L)
  }
  for (state in list(simpleError("PUBLIC-ESRCH-IDENTITY-ERROR"),
      structure(list(message = "PUBLIC-ESRCH-IDENTITY-INTERRUPT", call = NULL),
        class = c("interrupt", "condition")))) {
    seen$calls = seen$recoveries = 0L
    actual = tryCatch(bp_child_handles(handle, children, function(p) stop(state),
      recovered = recovered), error = identity, interrupt = identity)
    expect_identical(actual, first)
    expect_identical(seen$calls, 1L)
    expect_identical(seen$recoveries, 0L)
  }
  for (failure in list(
      structure(list(message = "PUBLIC-ESRCH-PERMISSION", call = NULL, errno = 13L),
        class = c("os_error", "ps_error", "error", "condition")),
      structure(list(message = "PUBLIC-ESRCH-WRONG-CLASS", call = NULL, errno = 3L),
        class = c("os_error", "error", "condition")),
      structure(list(message = "PUBLIC-ESRCH-NONSCALAR", call = NULL, errno = c(3L, 3L)),
        class = c("os_error", "ps_error", "error", "condition")))) {
    seen$calls = 0L
    blocked = function(p, recursive) {
      seen$calls = seen$calls + 1L
      stop(failure)
    }
    actual = tryCatch(bp_child_handles(handle, blocked, function(p) TRUE),
      error = identity, interrupt = identity)
    expect_identical(actual, failure)
    expect_identical(seen$calls, 1L)
  }
  for (second in list(simpleError("PUBLIC-ESRCH-RETRY-ERROR"),
      structure(list(message = "PUBLIC-ESRCH-RETRY-INTERRUPT", call = NULL),
        class = c("interrupt", "condition")), FALSE)) {
    seen$calls = seen$checks = seen$recoveries = 0L
    retry = function(p, recursive) {
      seen$calls = seen$calls + 1L
      if (seen$calls == 1L) stop(first)
      if (inherits(second, "condition")) stop(second)
      second
    }
    actual = tryCatch(bp_child_handles(handle, retry, alive, recovered = recovered),
      error = identity, interrupt = identity)
    expect_identical(actual, first)
    expect_identical(seen$calls, 2L)
    expect_identical(seen$checks, 1L)
    expect_identical(seen$recoveries, 0L)
  }
  for (state in list(FALSE, NA)) {
    seen$calls = seen$checks = seen$recoveries = 0L
    checked = function(p) {
      seen$checks = seen$checks + 1L
      if (seen$checks == 1L) TRUE else state
    }
    actual = tryCatch(bp_child_handles(handle, children, checked, recovered = recovered),
      error = identity, interrupt = identity)
    expect_identical(actual, first)
    expect_identical(seen$calls, 2L)
    expect_identical(seen$checks, 2L)
    expect_identical(seen$recoveries, 0L)
  }
  for (failure in list(simpleError("PUBLIC-ESRCH-RECOVERY-ERROR"),
      structure(list(message = "PUBLIC-ESRCH-RECOVERY-INTERRUPT", call = NULL),
        class = c("interrupt", "condition")))) {
    seen$calls = seen$checks = seen$recoveries = 0L
    publication = function() {
      seen$recoveries = seen$recoveries + 1L
      stop(failure)
    }
    actual = tryCatch(bp_child_handles(handle, children, alive, recovered = publication),
      error = identity, interrupt = identity)
    expect_identical(actual, first)
    expect_identical(seen$calls, 2L)
    expect_identical(seen$checks, 2L)
    expect_identical(seen$recoveries, 1L)
  }
  expect_identical(serialize(first, NULL), before)
})



test_that("backpressure failed observer metrics retain bounded fields and fatal routing", {
  skip_on_cran()
  failure = structure(list(message = "observer-snapshot-deadline\nFAKE-private-path", call = NULL),
    class = c("gptr_owned_disk_observer.ObservationError", "error", "condition"))
  before = serialize(failure, NULL)
  record = list(entries = 251L, directories = 8L, declared_links = 0L,
    disappeared = 0L, bytes = 8602L, max_depth = 2L, operation = "directory-identity",
    elapsed_s = 1.05, elapsed_capped = FALSE, max_seconds = 1, counters_capped = FALSE)
  observe = local({
    observer = new.env(parent = emptyenv())
    function() stop("The diagnostic must not run another snapshot.")
  })
  seen = new.env(parent = emptyenv())
  seen$reads = 0L
  read = function(object) {
    expect(identical(object, get("observer", environment(observe), inherits = FALSE)),
      "The diagnostic read must use the exact private observer.")
    seen$reads = seen$reads + 1L
    record
  }
  # Evaluate the actual fatal sampler branch without starting a child or Python.
  walk = function(expression) {
    if (missing(expression)) return(list())
    found = list()
    if (is.call(expression) && identical(expression[[1L]], as.name("if")) &&
        identical(expression[[2L]], quote(inherits(sample, "condition")))) found = list(expression)
    if (is.call(expression) || is.expression(expression) || is.pairlist(expression)) {
      for (part in as.list(expression)) found = c(found, walk(part))
    }
    found
  }
  branches = walk(body(bp_run))
  expect(identical(length(branches), 1L), "The sampler must keep one original failure branch.")
  scope = new.env(parent = baseenv())
  scope$sample = failure
  scope$sample_stage = "files"
  scope$observer_enabled = TRUE
  scope$observe = observe
  scope$sampling_errors = 0L
  scope$sample_error = scope$guard = NULL
  scope$case = "timeout"
  scope$bp_rss_capture = function(...) invisible(NULL)
  scope$bp_sample_error = function(stage, error, observe = NULL) {
    # An old branch has no observer argument and retains its legacy record.
    if (is.null(observe)) {
      bp_sample_error(stage, error)
    } else {
      bp_sample_error(stage, error, observe = observe, read = read)
    }
  }
  eval(call("for", as.name("iteration"), 1L, branches[[1L]]), envir = scope)
  expect(identical(scope$sampling_errors, 1L), "An observer failure must remain a sampling error.")
  expect(identical(scope$guard, "resource_observation"), "The resource gate must remain fatal.")
  expect(identical(seen$reads, 1L), "The failed scan must read its diagnostics exactly once.")
  expect(identical(scope$sample_error$observer_failure, record),
    "The failed scan must publish its bounded structural metrics.")
  expect(identical(scope$sample_error$observer_reason, "observer-snapshot-deadline"),
    "The original fixed observer reason must remain unchanged.")
  expect(identical(scope$sample_error$class, class(failure)),
    "The original observer condition classes must remain unchanged.")
  expect(identical(serialize(failure, NULL), before),
    "The diagnostic must not modify the original observer condition.")
  expect(!any(grepl("FAKE-private", unlist(scope$sample_error), fixed = TRUE)),
    "The witness must omit private condition text and paths.")
})


test_that("backpressure failed observer metrics reject malformed and unavailable records", {
  skip_on_cran()
  failure = structure(list(message = "observer-snapshot-deadline", call = NULL),
    class = c("gptr_owned_disk_observer.ObservationError", "error", "condition"))
  before = serialize(failure, NULL)
  record = list(entries = 1L, directories = 1L, declared_links = 0L,
    disappeared = 0L, bytes = 0L, max_depth = 0L, operation = "walk-boundary",
    elapsed_s = 1, elapsed_capped = FALSE, max_seconds = 1, counters_capped = FALSE)
  observe = local({
    observer = new.env(parent = emptyenv())
    function() NULL
  })
  old = bp_sample_error("files", failure)
  variants = list(NULL, list(), record[-1L], c(record, list(path = "FAKE-private-path")),
    c(record, list(entries = 1L)), structure(record, private = "FAKE-private-path"))
  replacements = list(entries = list(-1, 4098, 1.5, Inf, NA_real_, TRUE, "1", c(1, 2)),
    directories = list(4098), declared_links = list(18), disappeared = list(4098),
    bytes = list(64 * 1024^2 + 2), max_depth = list(33),
    operation = list("FAKE-private-path", NA_character_, c("walk-boundary", "link-target")),
    elapsed_s = list(-1, 61, Inf, "1"), max_seconds = list(0, 2, NA_real_),
    elapsed_capped = list(NA, 1L), counters_capped = list(NA, c(FALSE, TRUE)))
  for (name in names(replacements)) {
    for (value in replacements[[name]]) {
      malformed = record
      malformed[[name]] = value
      variants[[length(variants) + 1L]] = malformed
    }
  }
  malformed = record
  malformed$entries = structure(1L, private = "FAKE-private-path")
  variants[[length(variants) + 1L]] = malformed
  for (value in variants) {
    actual = tryCatch(bp_sample_error("files", failure, observe = observe,
      read = function(object) value), error = identity, interrupt = identity)
    expect(identical(actual, old), "Unavailable or invalid metrics must retain the legacy witness.")
  }
  # A sampler from an older fixture need not expose the private observer binding.
  legacy = function() NULL
  environment(legacy) = new.env(parent = baseenv())
  actual = tryCatch(bp_sample_error("files", failure, observe = legacy,
    read = function(object) stop("This read must not occur.")), error = identity)
  expect(identical(actual, old), "A missing private observer must retain the legacy witness.")
  for (kind in c("error", "interrupt")) {
    secondary = structure(list(message = "FAKE-private-secondary", call = NULL),
      class = c(kind, "condition"))
    actual = tryCatch(bp_sample_error("files", failure, observe = observe,
      read = function(object) stop(secondary)), error = identity, interrupt = identity)
    expect(identical(actual, old), "A diagnostic condition must not replace the original failure.")
  }
  expect(identical(serialize(failure, NULL), before),
    "Rejected diagnostics must not modify the original condition.")
  expect(identical(tryCatch(stop(failure), error = identity), failure),
    "The original observer failure must remain rethrowable unchanged.")
})


test_that("backpressure failed observer metrics never read outside the typed file failure", {
  failure = structure(list(message = "observer-snapshot-deadline", call = NULL),
    class = c("gptr_owned_disk_observer.ObservationError", "error", "condition"))
  seen = new.env(parent = emptyenv())
  seen$reads = 0L
  observe = local({
    observer = new.env(parent = emptyenv())
    function() NULL
  })
  read = function(object) {
    seen$reads = seen$reads + 1L
    stop("Forbidden diagnostic read.")
  }
  for (stage in c("children", "memory")) {
    actual = tryCatch(bp_sample_error(stage, failure, observe = observe, read = read),
      error = identity)
    expect(identical(actual, bp_sample_error(stage, failure)),
      "Non-file failures must retain their original witness.")
  }
  class(failure) = c("other.ObservationError", "error", "condition")
  actual = tryCatch(bp_sample_error("files", failure, observe = observe, read = read),
    error = identity)
  expect(identical(actual, bp_sample_error("files", failure)),
    "Other observer classes must retain their original witness.")
  expect(identical(seen$reads, 0L),
    "Diagnostics must not read outside the exact typed file failure.")
})

observer_error = function(reason) {
  structure(list(message = reason, call = NULL),
    class = c("gptr_owned_disk_observer.ObservationError", "error", "condition"))
}

test_that("backpressure observation retries fixed transient observer reasons for one deadline", {
  skip_on_cran()
  sample = list(entries = 1)
  seen = new.env(parent = emptyenv())
  observe = function(errors) {
    seen$calls = 0L
    seen$retried = character()
    tryCatch(bp_observe(function() {
      seen$calls = seen$calls + 1L
      if (seen$calls <= length(errors)) stop(errors[[seen$calls]])
      sample
    }, function(reason) seen$retried = c(seen$retried, reason)), error = identity)
  }
  second = observer_error("observer-byte-limit")
  transient = c("observer-metadata-invalid", "observer-snapshot-deadline",
                "observer-initial-deadline", "observer-parent-entry-absent",
                "observer-link-entry-absent", "observer-entry-disappearance-uncertain")
  for (reason in transient) {
    expect_identical(observe(list(observer_error(reason))), sample)
    expect_identical(seen$calls, 2L)
    expect_identical(seen$retried, reason)
    expect_identical(observe(list(observer_error(reason), second)), second)
    expect_identical(seen$calls, 2L)
  }
  # Repeated transients that clear within the deadline, in any order, complete the sample.
  expect_identical(observe(lapply(transient, observer_error)), sample)
  expect_identical(seen$calls, 7L)
  expect_identical(seen$retried, transient)
  expect_identical(observe(c(lapply(transient[1:2], observer_error), list(second))), second)
  expect_identical(seen$calls, 3L)
  expect_identical(seen$retried, transient[1:2])
  # A transient that outlasts the 1 s deadline ends the sample with its last snapshot's condition.
  seen$calls = 0L
  seen$retried = character()
  started = proc.time()[["elapsed"]]
  actual = tryCatch(bp_observe(function() {
    seen$calls = seen$calls + 1L
    stop(structure(list(message = "observer-metadata-invalid", call = NULL, attempt = seen$calls),
      class = c("gptr_owned_disk_observer.ObservationError", "error", "condition")))
  }, function(reason) seen$retried = c(seen$retried, reason)), error = identity)
  expect_gte(proc.time()[["elapsed"]] - started, 1)
  expect_identical(actual$attempt, seen$calls)
  expect_identical(seen$retried, rep("observer-metadata-invalid", seen$calls - 1L))
  # Retries are paced at 100 ms, not a busy loop.
  expect_gte(length(seen$retried), 2L)
  expect_lt(length(seen$retried), 20L)
  # Bound, identity and link failures, untyped errors and unknown text are never retried.
  for (error in list(second, observer_error("observer-entry-limit"),
                     observer_error("observer-initial-entry-limit"),
                     observer_error("observer-undeclared-reparse-entry"),
                     observer_error("observer-link-target-differs"),
                     observer_error("observer-directory-identity-changed"),
                     observer_error("observer-listed-metadata-changed"),
                     observer_error("observer-metadata-invalid FAKE-private-path"),
                     simpleError("observer-metadata-invalid"))) {
    expect_identical(observe(list(error)), error)
    expect_identical(seen$calls, 1L)
    expect_length(seen$retried, 0L)
  }
})

test_that("a retried transient observer failure completes the case and is witnessed", {
  skip_on_cran()
  withr::local_envvar(GPTR_OPTIONAL_NOFOLLOW_OBSERVER = "true")
  run = function(..., initial = list()) {
    errors = list(...)
    seen = new.env(parent = emptyenv())
    seen$calls = 0L
    seen$constructions = 0L
    scope = new.env(parent = environment(bp_run))
    runner = bp_run
    environment(runner) = scope
    # A base R child and a scripted observer: only the sampler's observation path is real.
    scope$bp_loader = function() "NULL"
    scope$bp_child_case = function(case, root, failure) list(case = case)
    scope$bp_disk_observer = function(root, declarations, declared_only) {
      seen$constructions = seen$constructions + 1L
      if (seen$constructions <= length(initial)) stop(initial[[seen$constructions]])
      function() {
        seen$calls = seen$calls + 1L
        if (seen$calls <= length(errors)) stop(errors[[seen$calls]])
        list(entries = 1, directories = 1, declared_links = 0, disappeared = 0, bytes = 0,
             max_depth = 0, elapsed_s = 0)
      }
    }
    runner("observer-retry")
  }
  x = run(observer_error("observer-metadata-invalid"))
  expect_true(x$complete)
  expect_null(x$guard)
  expect_identical(x$sampling_errors, 0L)
  expect_identical(x$observer_retries, 1L)
  expect_identical(x$observer_retry_reason, "observer-metadata-invalid")
  expect_identical(x$result, list(case = "observer-retry"))
  # The witness counts every retry and keeps the first reason.
  x = run(observer_error("observer-snapshot-deadline"),
          observer_error("observer-metadata-invalid"), observer_error("observer-metadata-invalid"))
  expect_true(x$complete)
  expect_identical(x$sampling_errors, 0L)
  expect_identical(x$observer_retries, 3L)
  expect_identical(x$observer_retry_reason, "observer-snapshot-deadline")
  # Any other reason, also after a retry, stays one fatal sampling error.
  x = run(observer_error("observer-byte-limit"))
  expect_false(x$complete)
  expect_identical(x$guard, "resource_observation")
  expect_identical(x$sampling_errors, 1L)
  expect_identical(x$observer_retries, 0L)
  expect_identical(x$sample_error$observer_reason, "observer-byte-limit")
  x = run(observer_error("observer-snapshot-deadline"), observer_error("observer-byte-limit"))
  expect_false(x$complete)
  expect_identical(x$guard, "resource_observation")
  expect_identical(x$sampling_errors, 1L)
  expect_identical(x$observer_retries, 1L)
  expect_identical(x$observer_retry_reason, "observer-snapshot-deadline")
  expect_identical(x$sample_error$observer_reason, "observer-byte-limit")
  # So does a transient that persists past the deadline (more failures than it allows).
  x = do.call(run, rep(list(observer_error("observer-metadata-invalid")), 100L))
  expect_false(x$complete)
  expect_identical(x$guard, "resource_observation")
  expect_identical(x$sampling_errors, 1L)
  expect_gte(x$observer_retries, 2L)
  expect_identical(x$observer_retry_reason, "observer-metadata-invalid")
  expect_identical(x$sample_error$observer_reason, "observer-metadata-invalid")
  # Construction retries its initial deadline the same way and is witnessed with the samples.
  x = run(observer_error("observer-snapshot-deadline"),
          initial = list(observer_error("observer-initial-deadline")))
  expect_true(x$complete)
  expect_identical(x$sampling_errors, 0L)
  expect_identical(x$observer_retries, 2L)
  expect_identical(x$observer_retry_reason, "observer-initial-deadline")
  # Its entry limit, and an initial deadline that outlasts the 1 s retry, stay fatal.
  bound = observer_error("observer-initial-entry-limit")
  expect_identical(tryCatch(run(initial = list(bound)), error = identity), bound)
  persisting = rep(list(observer_error("observer-initial-deadline")), 100L)
  expect_identical(tryCatch(run(initial = persisting), error = identity), persisting[[1L]])
})

test_that("the observer's supervisor counts toward the cap only by its growth in the case", {
  skip_on_cran()
  withr::local_envvar(GPTR_OPTIONAL_NOFOLLOW_OBSERVER = "true")
  # The supervisor is this test process: its RSS before the case is earlier tests' memory.
  run = function(supervisor) {
    seen = new.env(parent = emptyenv())
    seen$reads = 0L
    local_mocked_bindings(ps_memory_info = function(p) {
      if (ps::ps_pid(p) != Sys.getpid()) return(c(rss = 2^28))
      seen$reads = seen$reads + 1L
      c(rss = supervisor[[min(seen$reads, length(supervisor))]])
    }, .package = "ps")
    scope = new.env(parent = environment(bp_run))
    runner = bp_run
    environment(runner) = scope
    scope$bp_loader = function() "NULL"
    scope$bp_child_case = function(case, root, failure) {
      Sys.sleep(1)
      list(case = case)
    }
    scope$bp_disk_observer = function(root, declarations, declared_only) {
      function() {
        list(entries = 1, directories = 1, declared_links = 0, disappeared = 0, bytes = 0,
             max_depth = 0, elapsed_s = 0)
      }
    }
    runner("supervisor-growth")
  }
  x = run(c(2, 2, 2) * 1024^3)
  expect_true(x$complete)
  expect_null(x$guard)
  expect_gte(x$peak_rss, 2^28)
  expect_identical(x$disk_observer$peak_supervisor_rss, 2 * 1024^3)
  # Growth during the case and the owned family share the unchanged cap.
  x = run(c(2, 2, 2.9) * 1024^3)
  expect_false(x$complete)
  expect_identical(x$guard, "resource_limit")
  expect_gte(x$peak_rss, 2^28)
  expect_lte(x$peak_rss, 1024^3)
  expect_error(run(c(2, 3) * 1024^3 + c(0, 1)),
    "initialization exceeded its unchanged resource bound", fixed = TRUE)
})

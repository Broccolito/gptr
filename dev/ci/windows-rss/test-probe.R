local({
  support = new.env(parent = baseenv())
  sys.source("gc-observation.R", support)
  sys.source("probe.R", support)
  sys.source("../optional-integrations.R", support)
  testthat::test_that("RSS comparison collects once only at the real ordered writer boundary", {
    root = withr::local_tempdir()
    calls = 0L
    capture = support$rss_capture(root, TRUE, gc_observation = function(rss) {
      calls <<- calls + 1L
      list(before_rss = rss(), after_rss = rss(), diagnostic_only = TRUE,
        product_acceptance = FALSE)
    }, snapshot = function() list(), flags = function(before, after) TRUE)
    capture$callback("before_observer", list(case = "ordered", writer = FALSE), function() 1)
    capture$callback("before_observer", list(case = "ordered", writer = TRUE), function() 1)
    capture$callback("before_observer", list(case = "binary", writer = TRUE), function() 1)
    testthat::expect_identical(calls, 1L)
    testthat::expect_identical(capture$state$collections, 1L)
    testthat::expect_error(capture$callback("before_observer",
      list(case = "ordered", writer = TRUE), function() 1))
  })
  testthat::test_that("RSS comparison retains a prior fatal during its one diagnostic collection", {
    root = withr::local_tempdir()
    calls = 0L
    capture = support$rss_capture(root, TRUE, gc_observation = function(rss) {
      calls <<- calls + 1L
      list(diagnostic_only = TRUE, product_acceptance = FALSE)
    }, snapshot = function() list(), flags = function(before, after) TRUE)
    capture$callback("initialization", list(case = "prior", resource_failure = TRUE,
      before_rss = 1024^3 + 1, after_rss = 1, elapsed = 0.01))
    testthat::expect_true(capture$state$fatal_seen)
    capture$callback("before_observer", list(case = "ordered", writer = TRUE), function() 1)
    testthat::expect_identical(calls, 1L)
    testthat::expect_true(capture$state$fatal_seen)
    rows = readLines(file.path(root, "rss-events.jsonl"))
    testthat::expect_identical(length(rows), 2L)
    testthat::expect_true(jsonlite::fromJSON(rows[[1L]])$prior_fatal_retained)
  })
  testthat::test_that("RSS collection preserves the original error and exact caller-state gate", {
    root = withr::local_tempdir()
    original = simpleError("Fixed original GC failure")
    capture = support$rss_capture(root, TRUE, gc_observation = function(rss) stop(original),
      snapshot = function() list(), flags = function(before, after) TRUE)
    caught = tryCatch(capture$callback("before_observer",
      list(case = "ordered", writer = TRUE), function() 1), error = identity)
    testthat::expect_identical(caught, original)
    testthat::expect_identical(capture$state$collections, 0L)
    capture = support$rss_capture(root, TRUE, gc_observation = function(rss) list(),
      snapshot = function() list(), flags = function(before, after) FALSE)
    testthat::expect_error(capture$callback("before_observer",
      list(case = "ordered", writer = TRUE), function() 1))
    testthat::expect_identical(capture$state$collections, 0L)
  })
  testthat::test_that("RSS sampling accepts only exact-handle confirmed death after RSS failure", {
    handle = new.env(parent = emptyenv())
    original = simpleError("Fixed RSS query failure")
    calls = 0L
    alive = function(handle) {
      calls <<- calls + 1L
      calls == 1L
    }
    value = support$rss_memory(handle, 7, create_time = function(handle) 7,
      alive = alive, memory_info = function(handle) stop(original))
    testthat::expect_identical(value, 0)
    testthat::expect_identical(calls, 2L)
    calls = 0L
    alive = function(handle) {
      calls <<- calls + 1L
      if (calls == 1L) TRUE else NA
    }
    caught = tryCatch(support$rss_memory(handle, 7, create_time = function(handle) 7,
      alive = alive, memory_info = function(handle) stop(original)), error = base::identity)
    testthat::expect_identical(caught, original)
    testthat::expect_identical(calls, 2L)
  })
  testthat::test_that("RSS cleanup attempts all stages and retains the original first condition", {
    calls = character()
    original = simpleError("Fixed original owned kill failure")
    secondary = structure(list(message = "Fixed marker interrupt"), class = c("interrupt",
      "condition"))
    value = support$rss_cleanup(function() {
      calls <<- c(calls, "root")
      stop(original)
    }, function() {
      calls <<- c(calls, "marked")
      stop(secondary)
    }, function() {
      calls <<- c(calls, "settle")
      list(settled = TRUE)
    }, function() {
      calls <<- c(calls, "known")
      TRUE
    }, FALSE)
    testthat::expect_identical(calls, c("root", "marked", "settle", "known"))
    testthat::expect_identical(value$error, original)
    testthat::expect_false(value$complete)
    testthat::expect_true(value$family$settled)
  })
  testthat::test_that("RSS settlement waits for a remembered handle after root and marker death", {
    clock = new.env(parent = emptyenv())
    clock$time = 0
    clock$observations = 0L
    value = support$optional_wait_family(function() TRUE, function() list(),
      now = function() clock$time, pause = function(seconds) {
        clock$time = clock$time + seconds
      }, known_stopped = function() {
        clock$observations = clock$observations + 1L
        clock$time >= 0.1
      })
    testthat::expect(isTRUE(value$settled), "Remembered handle must die before settlement")
    testthat::expect(identical(value$root_stopped, TRUE), "Root death must remain independent")
    testthat::expect(identical(value$remaining_marked_processes, 0L), "Marker tree must be empty")
    testthat::expect(clock$time >= 0.1 && clock$time < 5, "Known death must fit the old bound")
    testthat::expect(clock$observations > 1L, "Known death must be observed after the first poll")
  })
  testthat::test_that(
    "RSS persistent remembered handles remain fatal at the same five-second bound", {
    clock = new.env(parent = emptyenv())
    clock$time = 0
    value = support$rss_cleanup(function() NULL, function() NULL, function() {
      support$optional_wait_family(function() TRUE, function() list(),
        now = function() clock$time, pause = function(seconds) {
          clock$time = clock$time + seconds
        }, known_stopped = function() FALSE)
    }, function() FALSE, FALSE)
    testthat::expect(identical(value$complete, FALSE), "A live remembered handle must stay fatal")
    testthat::expect(inherits(value$error, "error"), "Failure must retain a condition")
    testthat::expect(identical(value$family$settled, FALSE), "Joint settlement must fail")
    testthat::expect(identical(value$family$root_stopped, TRUE), "Root status must stay exact")
    testthat::expect(identical(value$family$remaining_marked_processes, 0L),
      "Marker count stays exact")
    testthat::expect(identical(clock$time, 5), "The existing five-second budget must not increase")
  })
  testthat::test_that("RSS unknown remembered status and original conditions cannot imply death", {
    for (unknown in list(NA, NULL, 1, c(TRUE, FALSE))) {
      observed = new.env(parent = emptyenv())
      observed$calls = 0L
      caught = tryCatch(support$optional_wait_family(function() TRUE, function() list(),
        known_stopped = function() {
          observed$calls = observed$calls + 1L
          unknown
        }), error = base::identity)
      testthat::expect(inherits(caught, "error"), "Unknown known-handle status must be fatal")
      testthat::expect(identical(observed$calls, 1L), "Status must be checked without retries")
    }
    for (original in list(simpleError("Fixed known-handle query failure"),
      structure(list(message = "Fixed known-handle interrupt"),
        class = c("interrupt", "condition")))) {
      caught = tryCatch(support$optional_wait_family(function() TRUE, function() list(),
        known_stopped = function() stop(original)),
        error = base::identity, interrupt = base::identity)
      testthat::expect(identical(caught, original),
        "The original query condition must stay identical")
    }
  })
  testthat::test_that("RSS remembered death never bypasses root or marker settlement", {
    for (state in list(list(root = FALSE, marked = list()),
      list(root = TRUE, marked = list(TRUE)))) {
      clock = new.env(parent = emptyenv())
      clock$time = 0
      value = support$optional_wait_family(function() state$root, function() state$marked,
        seconds = 0.1, now = function() clock$time, pause = function(seconds) {
          clock$time = clock$time + seconds
        }, known_stopped = function() TRUE)
      testthat::expect(identical(value$settled, FALSE), "Root and marker gates remain mandatory")
      testthat::expect(identical(value$root_stopped, state$root), "Original root field stays exact")
      testthat::expect(identical(value$remaining_marked_processes, length(state$marked)),
        "Original marker count stays exact")
      testthat::expect(identical(clock$time, 0.1), "The caller's original bound stays exact")
    }
    value = support$optional_wait_family(function() TRUE, function() list())
    testthat::expect(isTRUE(value$settled),
      "Unchanged callers retain the default known-dead predicate")
  })

})

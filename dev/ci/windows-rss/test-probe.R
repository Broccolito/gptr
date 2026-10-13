local({
  support = new.env(parent = baseenv())
  sys.source("gc-observation.R", support)
  sys.source("probe.R", support)
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

})

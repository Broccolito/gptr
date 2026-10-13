local({
  support = new.env(parent = baseenv())
  sys.source("gc-observation.R", support)
  sys.source("probe.R", support)
  sys.source("../optional-integrations.R", support)
  # RED uses the literal prior controller census; GREEN uses the actual probe helper.
  if (exists("rss_census", support, inherits = FALSE)) {
    census = support$rss_census
  } else {
    census_source = new.env(parent = emptyenv())
    census_source$expressions = list()
    root_check = quote(stopifnot(identical(
      as.numeric(ps::ps_create_time(root_handle)), root_time)))
    marker_loop = quote(for (handle in ps::ps_find_tree(marker)) remember(handle))
    collect = function(expr) {
      if (!is.call(expr)) return(invisible(NULL))
      if ((identical(expr[[1L]], quote(`=`)) && identical(expr[[2L]], quote(remember))) ||
          identical(expr, root_check) || identical(expr, marker_loop)) {
        census_source$expressions[[length(census_source$expressions) + 1L]] = expr
      }
      for (part in as.list(expr)) collect(part)
      invisible(NULL)
    }
    for (expr in as.list(parse("controller.R", keep.source = FALSE))) collect(expr)
    expected_remember = parse(text = c("remember = function(handle) {",
      "time = as.numeric(ps::ps_create_time(handle))", "stopifnot(is.finite(time))",
      'key = paste(ps::ps_pid(handle), time, sep = ":")',
      "handles[[key]] <<- list(handle = handle, time = time)", "}"),
      keep.source = FALSE)[[1L]]
    stopifnot(length(census_source$expressions) == 3L,
      identical(census_source$expressions[[1L]], expected_remember),
      identical(census_source$expressions[[2L]], root_check),
      identical(census_source$expressions[[3L]], marker_loop))
    queries = list(quote(ps::ps_create_time(handle)), quote(ps::ps_pid(handle)),
      quote(ps::ps_create_time(root_handle)), quote(ps::ps_find_tree(marker)))
    injected = list(quote(create_time(handle)), quote(pid(handle)),
      quote(create_time(root_handle)), quote(marked(marker)))
    replace_queries = function(expr) {
      for (i in seq_along(queries)) if (identical(expr, queries[[i]])) return(injected[[i]])
      if (!is.call(expr)) return(expr)
      as.call(lapply(as.list(expr), replace_queries))
    }
    census_source$expressions = lapply(census_source$expressions, replace_queries)
    census = function(root, root_pid, root_time, marker, remembered = list(),
                      children, marked, pid, create_time, alive, supervisor_pid) {
      scope = list2env(list(handles = list(), root_handle = root, root_time = root_time,
        marker = marker, marked = marked, pid = pid, create_time = create_time),
        parent = baseenv())
      eval(census_source$expressions[[1L]], scope)
      eval(quote(remember(root_handle)), scope)
      for (row in remembered) {
        key = paste(row$pid, row$time, sep = ":")
        scope$handles[[key]] = list(handle = row$handle, time = row$time)
      }
      eval(census_source$expressions[[2L]], scope)
      eval(census_source$expressions[[3L]], scope)
      unname(lapply(scope$handles, function(row) {
        list(handle = row$handle, pid = as.integer(pid(row$handle)), time = row$time)
      }))
    }
  }
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
  testthat::test_that("RSS census counts unmarked descendants once with remembered handles", {
    root = list(pid = 10L, time = 1)
    worker = list(pid = 20L, time = 2)
    grandchild = list(pid = 30L, time = 3)
    dead = list(pid = 40L, time = 4)
    rows = census(root, 10L, 1, "fixed", remembered = list(
      list(handle = dead, pid = 40L, time = 4)), children = function(handle, recursive) {
      stopifnot(identical(handle, root), identical(recursive, TRUE))
      list(worker, grandchild)
    }, marked = function(marker) {
      stopifnot(identical(marker, "fixed"))
      list(root, grandchild)
    }, pid = function(handle) handle$pid, create_time = function(handle) handle$time,
      alive = function(handle) TRUE, supervisor_pid = 1L)
    testthat::expect(identical(vapply(rows, function(row) row$pid, integer(1)),
      c(10L, 40L, 20L, 30L)), "Owned union must include the marker-free worker once")
    values = vapply(rows, function(row) {
      support$rss_memory(row$handle, row$time,
        create_time = function(handle) handle$time,
        alive = function(handle) handle$pid != 40L,
        memory_info = function(handle) c(rss = as.numeric(handle$pid)))
    }, numeric(1))
    testthat::expect(identical(sum(values), 60), "RSS must count each live admitted instance once")
    testthat::expect(identical(values[[2L]], 0), "Remembered exact dead handles contribute zero")
  })
  testthat::test_that("RSS census retains remembered and marked handles after exact root death", {
    root = list(pid = 10L, time = 1)
    orphan = list(pid = 20L, time = 2)
    seen = new.env(parent = emptyenv())
    seen$descendants = 0L
    rows = census(root, 10L, 1, "fixed", remembered = list(
      list(handle = orphan, pid = 20L, time = 2)), children = function(handle, recursive) {
      seen$descendants = seen$descendants + 1L
      stop("Dead root must not be queried for descendants")
    }, marked = function(marker) list(orphan), pid = function(handle) handle$pid,
      create_time = function(handle) handle$time, alive = function(handle) FALSE,
      supervisor_pid = 1L)
    testthat::expect(identical(seen$descendants, 0L), "A dead exact root must not start a census")
    testthat::expect(identical(vapply(rows, function(row) row$pid, integer(1)), c(10L, 20L)),
      "A dead root must not erase admitted or marked orphan handles")
  })
  testthat::test_that("RSS census refuses unknown or changed root identity before discovery", {
    root = list(pid = 10L, time = 1)
    seen = new.env(parent = emptyenv())
    seen$queries = 0L
    query = function(...) {
      seen$queries = seen$queries + 1L
      list()
    }
    for (running in list(NA, NULL, 1, c(TRUE, FALSE))) {
      caught = tryCatch(census(root, 10L, 1, "fixed", children = query,
        marked = query, pid = function(handle) handle$pid,
        create_time = function(handle) handle$time, alive = function(handle) running,
        supervisor_pid = 1L), error = base::identity)
      testthat::expect(inherits(caught, "error"), "Unknown root status must remain fatal")
    }
    for (pair in list(c(11, 1), c(10, 2), c(1, 1))) {
      caught = tryCatch(census(root, pair[[1L]], pair[[2L]], "fixed",
        children = query, marked = query, pid = function(handle) handle$pid,
        create_time = function(handle) handle$time, alive = function(handle) TRUE,
        supervisor_pid = 1L), error = base::identity)
      testthat::expect(inherits(caught, "error"), "Unadmitted root PID or time must be fatal")
    }
    testthat::expect(identical(seen$queries, 0L), "Invalid roots must not discover any processes")
    changed = list2env(root, parent = emptyenv())
    caught = tryCatch(census(changed, 10L, 1, "fixed",
      children = function(handle, recursive) {
        changed$time = 2
        list()
      }, marked = query, pid = function(handle) handle$pid,
      create_time = function(handle) handle$time, alive = function(handle) TRUE,
      supervisor_pid = 1L), error = base::identity)
    testthat::expect(inherits(caught, "error"), "Root identity must survive descendant discovery")
    testthat::expect(identical(seen$queries, 0L), "Changed roots must not start the marker census")
  })
  testthat::test_that("RSS census rejects reused PIDs and retains the exact admitted handle", {
    root = list(pid = 10L, time = 1)
    old = list(pid = 20L, time = 2, original = TRUE)
    remembered = list(list(handle = old, pid = 20L, time = 2))
    rows = census(root, 10L, 1, "fixed", remembered,
      children = function(handle, recursive) list(list(pid = 20L, time = 2)),
      marked = function(marker) list(), pid = function(handle) handle$pid,
      create_time = function(handle) handle$time, alive = function(handle) TRUE,
      supervisor_pid = 1L)
    testthat::expect(identical(rows[[2L]]$handle, old), "Duplicate discovery must keep admission")
    caught = tryCatch(census(root, 10L, 1, "fixed", remembered,
      children = function(handle, recursive) list(list(pid = 20L, time = 3)),
      marked = function(marker) list(), pid = function(handle) handle$pid,
      create_time = function(handle) handle$time, alive = function(handle) TRUE,
      supervisor_pid = 1L), error = base::identity)
    testthat::expect(inherits(caught, "error"), "A reused PID must never replace an owned handle")
    caught = tryCatch(census(root, 10L, 1, "fixed", remembered,
      children = function(handle, recursive) list(list(pid = 1L, time = 3)),
      marked = function(marker) list(), pid = function(handle) handle$pid,
      create_time = function(handle) handle$time, alive = function(handle) TRUE,
      supervisor_pid = 1L), error = base::identity)
    testthat::expect(inherits(caught, "error"), "The outer supervisor must not enter its child sum")
    for (invalid in list(list(pid = NA_integer_, time = 3), list(pid = 0L, time = 3),
      list(pid = 30L, time = NA_real_), list(pid = 30L, time = Inf))) {
      caught = tryCatch(census(root, 10L, 1, "fixed", remembered,
        children = function(handle, recursive) list(invalid),
        marked = function(marker) list(), pid = function(handle) handle$pid,
        create_time = function(handle) handle$time, alive = function(handle) TRUE,
        supervisor_pid = 1L), error = base::identity)
      testthat::expect(inherits(caught, "error"), "Unknown discovered identity must remain fatal")
    }
    testthat::expect(identical(remembered[[1L]]$handle, old), "Failure must preserve admission")
  })
  testthat::test_that("RSS census preserves query errors and interrupts without partial success", {
    root = list(pid = 10L, time = 1)
    for (stage in c("children", "marked")) {
      for (original in list(simpleError("Fixed census query failure"),
        structure(list(message = "Fixed census interrupt"), class = c("interrupt", "condition")))) {
        query = function(...) stop(original)
        caught = tryCatch(census(root, 10L, 1, "fixed",
          children = if (stage == "children") query else function(...) list(),
          marked = if (stage == "marked") query else function(...) list(),
          pid = function(handle) handle$pid, create_time = function(handle) handle$time,
          alive = function(handle) TRUE, supervisor_pid = 1L),
          error = base::identity, interrupt = base::identity)
        testthat::expect(identical(caught, original), "Original query conditions must propagate")
      }
    }
    for (stage in c("children", "marked")) {
      caught = tryCatch(census(root, 10L, 1, "fixed",
        children = if (stage == "children") function(...) 1 else function(...) list(),
        marked = if (stage == "marked") function(...) 1 else function(...) list(),
        pid = function(handle) handle$pid, create_time = function(handle) handle$time,
        alive = function(handle) TRUE, supervisor_pid = 1L), error = base::identity)
      testthat::expect(inherits(caught, "error"), "Malformed census results must remain fatal")
    }
  })

})

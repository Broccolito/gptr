test_that("reactor_get() creates one gptr_reactor per process", {
  r = reactor_get()
  expect_s3_class(r, "gptr_reactor")
  expect_identical(reactor_get(), r)
  expect_identical(reactor_depth(), 0L)
  expect_null(reactor_tool_run())
  expect_type(reactor_now(), "double")
  id = reactor_timer(reactor_now() + 60, function() NULL)
  expect_match(id, "^t[0-9]+$")
  expect_identical(reactor_cancel(id), 1L)
})

test_that("timers fire once, in time order, and the pump honours its timeout", {
  st = new.env()
  st$log = character()
  now = reactor_now()
  reactor_timer(now + 0.2, function() st$log = c(st$log, "b"))
  reactor_timer(now + 0.1, function() st$log = c(st$log, "a"))
  expect_true(reactor_pump(until = function() length(st$log) == 2L, timeout = 5))
  expect_identical(st$log, c("a", "b"))
  t0 = reactor_now()
  expect_false(reactor_pump(timeout = 0.2))
  expect_gte(reactor_now() - t0, 0.19)
  expect_identical(st$log, c("a", "b"))
})

test_that("tasks run each iteration until FALSE; a number delays the next call", {
  st = new.env()
  st$n = 0L
  st$m = 0L
  reactor_task(function() {
    st$n = st$n + 1L
    st$n < 3L
  })
  reactor_task(function() {
    st$m = st$m + 1L
    if (st$m >= 2L) FALSE else 0.3
  })
  t0 = reactor_now()
  expect_true(reactor_pump(until = function() st$n == 3L && st$m == 2L, timeout = 5))
  expect_gte(reactor_now() - t0, 0.25)
  expect_length(ls(reactor_get()$tasks), 0L)
})

test_that("a task that keeps returning TRUE does not make the pump spin", {
  st = new.env()
  st$n = 0L
  id = reactor_task(function() {
    st$n = st$n + 1L
    TRUE
  })
  withr::defer(reactor_cancel(id))
  expect_false(reactor_pump(timeout = 0.5))
  # about 100 iterations of 5 ms; a busy loop would call the task tens of thousands of times
  expect_gte(st$n, 5L)
  expect_lt(st$n, 1000L)
})

test_that("a task is never re-entered by a pump nested inside its own call", {
  # an inprocess generator whose events reach a hook that calls System 1 pumps the reactor
  # from inside its task (IC-57): the nested pump must not call the generator again
  st = new.env()
  st$calls = 0L
  st$inside = FALSE
  st$reentered = FALSE
  reactor_task(function() {
    if (st$inside) st$reentered = TRUE
    st$calls = st$calls + 1L
    if (st$calls == 1L) {
      st$inside = TRUE
      on.exit({
        st$inside = FALSE
      }, add = TRUE)
      reactor_pump(timeout = 0.3)
    }
    st$calls < 3L
  })
  expect_true(reactor_pump(until = function() st$calls >= 3L, timeout = 5))
  expect_false(st$reentered)
  expect_length(ls(reactor_get()$tasks), 0L)
})

test_that("a nested pump inside a FIFO tool never runs a sibling's tool nor later::run_now(0)", {
  st = new.env()
  st$log = character()
  st$later = integer()
  local_mocked_bindings(later_run_now = function() {
    st$later = c(st$later, reactor_depth())
    invisible(FALSE)
  })
  reactor_enqueue_tool("u-a", function() {
    st$log = c(st$log, "a-start")
    st$inner = reactor_tool_run()
    st$nested = FALSE
    reactor_timer(reactor_now() + 0.3, function() st$nested = TRUE)
    reactor_pump(until = function() st$nested, timeout = 5)
    st$log = c(st$log, "a-end")
  })
  reactor_enqueue_tool("u-b", function() st$log = c(st$log, "b"))
  expect_true(reactor_pump(until = function() "b" %in% st$log, timeout = 10))
  expect_identical(st$log, c("a-start", "a-end", "b"))
  expect_identical(st$inner, "u-a")
  expect_null(reactor_tool_run())
  expect_gt(length(st$later), 0L)
  expect_true(all(st$later == 1L))
})

test_that("a nested pump runs the tools of the runs it names in allow_runs", {
  st = new.env()
  st$log = character()
  reactor_enqueue_tool("u-c", function() {
    reactor_enqueue_tool("u-d", function() st$log = c(st$log, "d"))
    reactor_pump(until = function() "d" %in% st$log, allow_runs = "u-d", timeout = 5)
    st$log = c(st$log, "c-end")
  })
  expect_true(reactor_pump(until = function() "c-end" %in% st$log, timeout = 10))
  expect_identical(st$log, c("d", "c-end"))
})

test_that("a nested pump waiting for a served CLI run keeps servicing later", {
  st = new.env()
  st$later = integer()
  local_mocked_bindings(later_run_now = function() {
    st$later = c(st$later, reactor_depth())
    invisible(FALSE)
  })
  reactor_served("u-cli")
  withr::defer(reactor_served("u-cli", FALSE))
  reactor_enqueue_tool("u-e", function() {
    st$go = FALSE
    reactor_timer(reactor_now() + 0.2, function() st$go = TRUE)
    reactor_pump(until = function() st$go, allow_runs = "u-cli", timeout = 5)
    st$done = TRUE
  })
  expect_true(reactor_pump(until = function() isTRUE(st$done), timeout = 10))
  expect_true(2L %in% st$later)
})

test_that("reactor_cancel() removes timers, tasks and FIFO items", {
  st = new.env()
  st$fired = FALSE
  timer = reactor_timer(reactor_now() + 0.1, function() st$fired = TRUE)
  task = reactor_task(function() {
    st$fired = TRUE
    TRUE
  })
  tool = reactor_enqueue_tool("u-x", function() st$fired = TRUE)
  expect_identical(reactor_cancel(c(timer, task, tool, "t999999")), 3L)
  reactor_pump(timeout = 0.3)
  expect_false(st$fired)
  expect_error(reactor_cancel(1), class = "gptr_error_invalid_argument")
})

test_that("failing timers, tasks and tools become diagnostics and the pump continues", {
  st = new.env()
  st$ok = FALSE
  st$diag = character()
  local_mocked_bindings(registry_diagnostic = function(source, event, class, message) {
    st$diag = c(st$diag, paste(source, event, message))
    invisible(NULL)
  })
  reactor_timer(reactor_now(), function() stop("boom timer"))
  reactor_task(function() stop("boom task"))
  reactor_enqueue_tool("u-f", function() stop("boom tool"))
  reactor_timer(reactor_now() + 0.1, function() st$ok = TRUE)
  expect_true(reactor_pump(until = function() st$ok, timeout = 5))
  expect_setequal(st$diag, c("reactor timer boom timer", "reactor task boom task",
                             "reactor tool boom tool"))
  expect_null(reactor_tool_run())
})

test_that("an error in a later callback becomes a diagnostic, not a pump failure", {
  skip_if_not_installed("later")
  st = new.env()
  st$diag = character()
  local_mocked_bindings(registry_diagnostic = function(source, event, class, message) {
    st$diag = c(st$diag, paste(source, event, message))
    invisible(NULL)
  })
  later::later(function() stop("boom later"), 0)
  expect_false(reactor_pump(timeout = 0.3))
  expect_identical(st$diag, "reactor later boom later")
})

test_that("runs are held strongly until removed", {
  run = new.env()
  run$id = "u-hold"
  reactor_run_add(run)
  expect_true(exists("u-hold", envir = reactor_get()$runs, inherits = FALSE))
  reactor_served(run)
  reactor_run_remove(run)
  expect_false(exists("u-hold", envir = reactor_get()$runs, inherits = FALSE))
  expect_false("u-hold" %in% reactor_get()$served)
  expect_identical(reactor_run_id(list(id = "u-1")), "u-1")
  expect_identical(reactor_run_id("u-2"), "u-2")
  expect_true(is.na(reactor_run_id(NULL)))
})

test_that("an error in until() leaves the pump depth balanced", {
  expect_error(reactor_pump(until = function() stop("until failed"), timeout = 1),
               "until failed")
  expect_identical(reactor_depth(), 0L)
  expect_length(reactor_get()$allow_stack, 0L)
})

test_that("a pump nested in a reactor callback runs no FIFO tool unless allow_runs names it", {
  st = new.env()
  st$log = character()
  reactor_timer(reactor_now(), function() {
    reactor_enqueue_tool("u-h", function() st$log = c(st$log, "h"))
    reactor_pump(timeout = 0.3)
    st$log = c(st$log, "timer-end")
  })
  expect_true(reactor_pump(until = function() "h" %in% st$log, timeout = 10))
  expect_identical(st$log, c("timer-end", "h"))
})

test_that("reactor_allow_runs() is NULL in the outermost pump and the nested runs inside", {
  expect_null(reactor_allow_runs())
  st = new.env()
  st$seen = FALSE
  reactor_enqueue_tool("u-g", function() {
    st$outer = reactor_allow_runs()
    reactor_timer(reactor_now(), function() {
      st$inner = reactor_allow_runs()
      st$seen = TRUE
    })
    reactor_pump(until = function() st$seen, allow_runs = "u-cli2", timeout = 5)
  })
  expect_true(reactor_pump(until = function() st$seen, timeout = 10))
  expect_null(st$outer)
  expect_identical(st$inner, "u-cli2")
  expect_null(reactor_allow_runs())
})

test_that("callbacks may cancel pending work without resurrecting it", {
  st = new.env()
  st$log = character()
  first = reactor_timer(reactor_now(), function() {
    st$log = c(st$log, "first")
    reactor_cancel(st$second)
  })
  st$second = reactor_timer(reactor_now(), function() st$log = c(st$log, "second"))
  st$task = reactor_task(function() {
    st$log = c(st$log, "task")
    reactor_cancel(st$task)
    TRUE
  })
  expect_true(reactor_pump(until = function() "task" %in% st$log, timeout = 5))
  expect_identical(st$log, c("first", "task"))
  expect_identical(reactor_cancel(c(first, st$second, st$task)), 0L)
})

test_that("interrupts unwind callback marks and pump stacks without diagnostics", {
  interrupt = function() {
    stop(structure(list(message = "test interrupt", call = NULL),
                   class = c("interrupt", "condition")))
  }
  r = reactor_get()
  task = reactor_task(interrupt)
  withr::defer(reactor_cancel(task))
  caught = tryCatch(reactor_pump(timeout = 5), interrupt = identity)
  expect_s3_class(caught, "interrupt")
  expect_false(r$tasks[[task]]$busy)
  expect_identical(reactor_depth(), 0L)
  expect_length(r$allow_stack, 0L)
  reactor_cancel(task)
  reactor_enqueue_tool("u-interrupt", interrupt)
  caught = tryCatch(reactor_pump(timeout = 5), interrupt = identity)
  expect_s3_class(caught, "interrupt")
  expect_null(reactor_tool_run())
  expect_identical(reactor_depth(), 0L)
  expect_length(r$allow_stack, 0L)
})

test_that("callback failures reach the real registry diagnostics", {
  registry = registry_env()
  before = length(registry$diag$rows)
  reactor_task(function() stop("reactor integration sentinel"))
  expect_true(reactor_pump(until = function() {
    length(registry$diag$rows) > before
  }, timeout = 5))
  row = registry$diag$rows[[length(registry$diag$rows)]]
  expect_identical(row$source, "reactor")
  expect_identical(row$event, "task")
  expect_identical(row$message, "reactor integration sentinel")
  expect_length(ls(reactor_get()$tasks), 0L)
})

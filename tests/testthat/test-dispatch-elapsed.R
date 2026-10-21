source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

test_that("reported tool duration excludes approval and includes execution", {
  local_fake_provider(list("ok"))
  local_permissive()
  clock = new.env(parent = emptyenv())
  clock$time = 100
  local_mocked_bindings(reactor_now = function() clock$time,
                        perm_check = function(call, run) {
                          clock$time = clock$time + 14
                          list(decision = "allow", risk = list(level = 0L))
                        })
  local_tool("elapsed", function(input, ctx) {
    clock$time = clock$time + 0.25
    "calculated"
  })
  events = local_events(c("tool_execution_start", "tool_execution_end"))
  s = test_session()
  x = dispatch(s, list(block_tool_call("elapsed-1", "elapsed", json_obj())))
  ends = Filter(function(e) identical(e$type, "tool_execution_end"), events(s))
  expect_length(ends, 1L)
  expect_identical(ends[[1L]]$elapsed, 0.25)
  expect_identical(msg_text(x$msgs[[1L]]), "calculated")
  expect_false(x$msgs[[1L]]$is_error)
})

test_that("an unexecuted tool has zero execution duration after a delayed denial", {
  local_fake_provider(list("ok"))
  clock = new.env(parent = emptyenv())
  clock$time = 100
  clock$ran = FALSE
  local_mocked_bindings(reactor_now = function() clock$time,
                        perm_check = function(call, run) {
                          clock$time = clock$time + 14
                          list(decision = "deny", reason = "declined", risk = list(level = 2L))
                        })
  local_tool("elapsed", function(input, ctx) {
    clock$ran = TRUE
    "not reached"
  })
  events = local_events("tool_execution_end")
  s = test_session()
  x = dispatch(s, list(block_tool_call("elapsed-1", "elapsed", json_obj())))
  expect_length(events(s), 1L)
  expect_identical(events(s)[[1L]]$elapsed, 0)
  expect_false(clock$ran)
  expect_true(x$msgs[[1L]]$is_error)
})

test_that("an interrupted tool reports execution duration without earlier approval time", {
  local_fake_provider(list("ok"))
  local_permissive()
  clock = new.env(parent = emptyenv())
  clock$time = 100
  local_mocked_bindings(reactor_now = function() clock$time,
                        perm_check = function(call, run) {
                          clock$time = clock$time + 14
                          list(decision = "allow", risk = list(level = 0L))
                        })
  local_tool("elapsed", function(input, ctx) {
    clock$time = clock$time + 0.75
    signalCondition(structure(list(message = "", call = NULL),
                              class = c("interrupt", "condition")))
    "not reached"
  })
  events = local_events("tool_execution_end")
  s = test_session()
  outcome = tryCatch({
    dispatch(s, list(block_tool_call("elapsed-1", "elapsed", json_obj())))
    "returned"
  }, interrupt = function(e) "interrupted")
  expect_identical(outcome, "interrupted")
  expect_length(events(s), 1L)
  expect_identical(events(s)[[1L]]$elapsed, 0.75)
  expect_match(msg_text(tool_results(s)[[1L]]), "Interrupted after 0.8 s", fixed = TRUE)
})

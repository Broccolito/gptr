source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# ---------------------------------------------------------------- run records (04 section 7.6)

test_that("run_new() builds a queued gptr_run with the contract fields", {
  home = new.env()
  s = test_session(mode = "edits", home = home)
  run = run_new(s, list(agent = "main"), NULL)
  expect_s3_class(run, "gptr_run")
  expect_match(run$id, "^u[0-9a-f]{8}$")
  expect_identical(run$session, session_data(s)$id)
  expect_identical(run$status, "queued")
  expect_identical(run$turn, 0L)
  expect_identical(run$mode, "edits")
  expect_identical(run$depth, 0L)
  expect_null(run$parent_run)
  expect_identical(run$children, character())
  expect_false(run$signal$aborted)
  expect_s3_class(run$started, "POSIXct")
  expect_identical(run$max_turns, 50L)
  expect_identical(run_eval_env(run), home)
})

test_that("the safety options are snapshotted at the start of a root run (IC-53)", {
  local_gptr_options(noninteractive_ask = "deny", unsafe_no_permissions = FALSE)
  s = test_session()
  run = run_new(s, list(), NULL)
  options(gptr.noninteractive_ask = "stop", gptr.unsafe_no_permissions = TRUE)
  expect_identical(run$opts$safety$noninteractive_ask, "deny")
  expect_false(run$opts$safety$unsafe_no_permissions)
  expect_named(run$opts$safety, c("ui", "interactive", "critical_guard", "secret_guard",
                                  "noninteractive_ask", "protect_size", "mode",
                                  "unsafe_no_permissions", "can_prompt", "has_human"))
})

test_that("a nested run tightens the mode, inherits the snapshot and links to the outer run", {
  outer_s = test_session(mode = "manual")
  outer = run_new(outer_s, list(), NULL)
  child = test_session(mode = "auto", kind = "child", parent = outer_s)
  inner = run_new(child, list(), outer)
  expect_identical(inner$mode, "manual")
  expect_identical(inner$opts$safety, outer$opts$safety)
  expect_identical(inner$parent_run, outer$id)
  expect_identical(inner$depth, 1L)
  expect_true(session_data(child)$id %in% outer$children)
  expect_identical(run_mode_tighter("auto", "plan"), "plan")
})

test_that("plan mode evaluates in a scratch overlay of the home (IC-15)", {
  home = new.env()
  s = test_session(mode = "plan", home = home)
  run = run_new(s, list(), NULL)
  env = run_eval_env(run)
  expect_false(identical(env, home))
  expect_identical(parent.env(env), home)
  expect_null(run_eval_env(NULL))
})

test_that("the gateway's evaluation environment wins over the kept home (IC-40)", {
  home = new.env()
  frame = new.env()
  s = test_session(home = home)
  call = new.env()
  call$envir = frame
  expect_identical(run_eval_env(run_new(s, list(call = call), NULL)), frame)
})

test_that("run_current() finds the innermost frame that marks a running tool", {
  s = test_session()
  run = run_new(s, list(), NULL)
  expect_null(run_current())
  inner = function() run_current()
  tool_frame = function() {
    .gptr_tool_run = run
    inner()
  }
  expect_identical(tool_frame(), run)
  expect_null(run_current())
})

test_that("run_emit() and session_emit() dispatch events with the section 4.5 fields", {
  s = test_session()
  sid = session_data(s)$id
  got = new.env()
  local_hook("turn_start", function(event, ctx) {
    got$ev = event
    got$ctx = ctx
    NULL
  }, session = sid)
  run = test_run(s, list(agent = "stats"))
  run_emit(run, "turn_start")
  expect_identical(got$ev$type, "turn_start")
  expect_identical(got$ev$session, sid)
  expect_identical(got$ev$run, run$id)
  expect_identical(got$ev$agent, "stats")
  expect_identical(got$ev$turn, 0L)
  expect_true(is.numeric(got$ev$ts))
  expect_identical(got$ctx, session_live(s)$ctx)
  session_emit(s, "turn_start")
  expect_identical(got$ev$run, run$id)
})

test_that("run_ui() is NULL without the ui.get service and the service's UI otherwise", {
  local_without_services("ui.get")
  s = test_session()
  run = run_new(s, list(), NULL)
  expect_null(run_ui(run))
  local_service("ui.get", function(session = NULL) {
    list(name = "scripted", has_ui = function() TRUE)
  })
  expect_identical(run_ui(run)$name, "scripted")
})

test_that("interactive = FALSE in the run options means nobody can answer the run's gate", {
  local_gptr_options(interactive = TRUE)
  s = test_session()
  expect_true(run_new(s, list(), NULL)$opts$safety$can_prompt)
  expect_false(run_new(s, list(interactive = FALSE), NULL)$opts$safety$can_prompt)
})

# ---------------------------------------------------------------- additions to the plan's tests

test_that("session_emit() outside a run names no run and the main agent", {
  s = test_session()
  got = new.env()
  local_hook("turn_start", function(event, ctx) {
    got$ev = event
    NULL
  }, session = session_data(s)$id)
  session_emit(s, "turn_start")
  expect_null(got$ev$run)
  expect_identical(got$ev$agent, "main")
  expect_identical(got$ev$session, session_data(s)$id)
})

test_that("the agent-area accessors reach the run's session for the L2 dispatcher", {
  s = test_session()
  sid = session_data(s)$id
  run = run_new(s, list(), NULL)
  expect_identical(run_data(run), session_data(s))
  expect_identical(run_live(run), session_live(s))
  expect_identical(run_ctx(run), session_live(s)$ctx)
  expect_identical(run_ctx_sid(run_ctx(run)), sid)
  expect_null(run_ctx_sid(ctx_new(NULL)))
  id = run_append_message(run, msg_user("hello"))
  expect_match(id, "^[0-9a-f]{8}$")
  d = session_data(s)
  expect_identical(d$leaf, id)
  expect_identical(d$entries[[length(d$entries)]]$message$role, "user")
  cid = run_append_custom(run, "gptr.budget", list(kind = "cost", budget = 5, used = 6))
  e = d$entries[[length(d$entries)]]
  expect_identical(d$leaf, cid)
  expect_identical(e$custom_type, "gptr.budget")
  expect_identical(e$data$kind, "cost")
})

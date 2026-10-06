# tests/testthat/test-gptr-sdk.R (Task 10: create)
# test-gptr-sdk.R -- the session SDK verbs on the fake provider (plan P08).

# A temporary project with a private user config directory; the process settings layer is
# restored when the test ends.
local_gw = function(workspace = TRUE, .env = parent.frame()) {
  cfg = withr::local_tempdir("gptr-config-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = cfg, .local_envir = .env)
  old = the$settings_session
  withr::defer({
    the$settings_session = old
  }, envir = .env)
  local_project(gptr = workspace, .env = .env)
}

# A stand-in for the run that run_current() returns while model code runs.
fake_run = function(session = "s0000000000", mode = "manual", depth = 0L) {
  run = new.env(parent = emptyenv())
  run$id = "u00000000"
  run$session = session
  run$mode = mode
  run$depth = depth
  run$opts = list()
  run$signal = new.env(parent = emptyenv())
  run
}

# A direct tool whose execute() runs `fun(ctx)` (tests only)
test_tool = function(name, fun) {
  gptr_tool(name, paste("Test tool", name),
            parameters = list(type = "object", properties = json_obj()),
            execute = function(input, ctx) fun(ctx))
}

test_that("gptr_step() starts a pending session; with nothing queued it is a no-op", {
  local_gw()
  fake = local_fake_provider(list("Plan: ..."))
  s = peter("Plan the analysis", model = fake, .run = FALSE, envir = new.env())
  expect_identical(s$turns, 0L)
  expect_invisible(gptr_step(s))
  expect_identical(s$turns, 1L)
  expect_identical(s$status, "idle")
  expect_identical(s$text, "Plan: ...")
  expect_false(gateway_pending_has(s$id))
  expect_invisible(gptr_step(s))
  expect_identical(s |> gptr_step(), s)
  expect_identical(s$turns, 1L)
  expect_length(fake_requests(fake), 1L)
})

test_that("gptr_step(turns = 1) stops after one turn; turns = Inf runs to settlement", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  noop = test_tool("noop", function(ctx) "ok")
  fake = local_fake_provider(list(fake_tool("noop"), fake_tool("noop"), "done"))
  s = peter("go", model = fake, tools = list(noop), .run = FALSE, envir = new.env())
  gptr_step(s, turns = 1L)
  expect_identical(s$turns, 1L)
  expect_identical(s$status, "running")
  gptr_step(s, turns = Inf)
  expect_identical(s$status, "idle")
  expect_identical(s$text, "done")
})

test_that("the call record of a pending session is held until its run settles [R2]", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = peter("x", model = fake, .run = FALSE, envir = new.env())
  call = get0(s$id, envir = gateway_state()$pending, inherits = FALSE)$call
  expect_true(isTRUE(call$hold))
  expect_true(is.environment(call$envir))
  gptr_step(s)
  expect_false(isTRUE(call$hold))
  expect_null(call$envir)
})

test_that("gptr_wait() starts queued sessions and waits for all of them", {
  local_gw()
  fake = local_fake_provider(list("a"))
  runs = list(a = peter("one", model = fake, .run = FALSE, envir = new.env()),
              b = peter("two", model = fake, .run = FALSE, envir = new.env()))
  expect_invisible(gptr_wait(runs, timeout = 10))
  expect_identical(vapply(runs, function(x) x$status, ""), c(a = "idle", b = "idle"))
  expect_identical(vapply(runs, function(x) x$turns, 0L), c(a = 1L, b = 1L))
})

test_that("gptr_wait() on one failed session signals its condition", {
  local_gw()
  fake = local_fake_provider(list(fake_error("bad request", status = 400L)))
  s = peter("x", model = fake, .run = FALSE, envir = new.env())
  cnd = expect_error(gptr_wait(s), class = "gptr_error_provider")
  expect_identical(cnd$session, s)
})

test_that("gptr_wait() returns at the timeout; gptr_cancel() then aborts the run", {
  local_gw()
  fake = local_fake_provider(list(list(hang = TRUE)))
  s = peter("long task", model = fake, .run = FALSE, envir = new.env())
  expect_invisible(gptr_cancel(s))
  expect_identical(s$status, "idle")
  gptr_wait(s, timeout = 0.2)
  expect_identical(s$status, "running")
  expect_invisible(gptr_cancel(s))
  expect_identical(s$status, "aborted")
})

test_that("gptr_steer() queues a follow-up delivered when the agent would stop", {
  local_gw()
  fake = local_fake_provider(list("first", "second"))
  s = peter("Summarise mtcars", model = fake, .run = FALSE, envir = new.env())
  expect_invisible(gptr_steer(s, "Use only the mpg column", as = "follow_up"))
  gptr_wait(s)
  users = Filter(function(m) identical(m$role, "user"), s$messages)
  expect_identical(vapply(users, msg_text, ""), c("Summarise mtcars", "Use only the mpg column"))
  expect_identical(s$text, "second")
})

test_that("gptr_steer() redacts with the context profile and queues an api_user item", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = peter("x", model = fake, .run = FALSE, envir = new.env())
  box = new.env()
  local_mocked_bindings(redact = function(x, profile = "persist") {
    box$profile = profile
    "[redacted]"
  })
  gptr_steer(s, "the key is sk-test-123", as = "follow_up")
  queue = session_data(s)$queue$follow_up
  expect_length(queue, 2L)
  item = queue[[2L]]
  expect_identical(box$profile, "context")
  expect_identical(item$text, "[redacted]")
  expect_identical(item$source, "api_user")
})

test_that("the verbs validate their arguments", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = peter("x", model = fake, .run = FALSE, envir = new.env())
  expect_error(gptr_steer(s, 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_steer(s, "x", as = "later"), class = "gptr_error_invalid_argument")
  expect_error(gptr_steer("s", "x"), class = "gptr_error_invalid_argument")
  expect_error(gptr_step(s, turns = 0), class = "gptr_error_invalid_argument")
  expect_error(gptr_step(s, turns = 1.5), class = "gptr_error_invalid_argument")
  expect_error(gptr_wait(list(1)), class = "gptr_error_invalid_argument")
  expect_error(gptr_cancel(NULL), class = "gptr_error_invalid_argument")
  expect_error(gptr_on(s, "turn_end", "not a function"), class = "gptr_error_invalid_argument")
})

test_that("model code may not steer or cancel another session, nor add listeners (IC-53)", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = peter("x", model = fake, .run = FALSE, envir = new.env())
  run = fake_run(session = "s9999999999")
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_steer(s, "x"), class = "gptr_error_permission")
  expect_error(gptr_cancel(s), class = "gptr_error_permission")
  expect_error(gptr_on(s, "turn_end", function(event, ctx) NULL), class = "gptr_error_permission")
  run$signal$control = "gptr_cancel"
  expect_invisible(gptr_cancel(s))
})

test_that("gptr_on() registers a session listener and returns its remover", {
  local_gw()
  # bound first: a local_*() helper called inside the `model =` expression would attach its
  # cleanup to the gateway's alias mask (it is evaluated there), not to this test
  fake = local_fake_provider(list("hello"))
  s = peter("hi", model = fake, .run = FALSE, envir = new.env())
  log = new.env()
  log$roles = character()
  off = gptr_on(s, "message_end", function(event, ctx) {
    log$roles = c(log$roles, event$message$role)
    NULL
  })
  expect_true(is.function(off))
  gptr_step(s)
  expect_true("assistant" %in% log$roles)
  off()
  n = length(log$roles)
  s |> peter("again")
  expect_length(log$roles, n)
  expect_error(gptr_on(s, "PreToolUse", function(event, ctx) NULL),
               class = "gptr_error_invalid_argument")
})

test_that("gptr_return() outside a run returns its argument invisibly (IC-48)", {
  expect_invisible(gptr_return(1:3))
  expect_identical(gptr_return(1:3), 1:3)
  local_gptr_options(quiet = FALSE)
  withr::local_envvar(GPTR_REPLAY = "replay")
  expect_silent(gptr_return("quiet while replaying"))
})

test_that("gptr_return() designates the run's value from R code during a run", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  designate = test_tool("designate", function(ctx) {
    gptr_return(c(a = 1, b = 2))
    "designated"
  })
  fake = local_fake_provider(list(fake_tool("designate"), "done"))
  s = peter("designate it", model = fake, tools = list(designate), envir = new.env())
  expect_identical(s$value, c(a = 1, b = 2))
})

# ------------------------------------------------------------------ adaptations (Task 10)

test_that("a pending run freezes its safety record when a verb starts it (07 section 5)", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  box = new.env()
  box$seen = list()
  probe = test_tool("probe_safety", function(ctx) {
    box$seen[[length(box$seen) + 1L]] = run_current()$opts$safety
    "seen"
  })
  queue = function() {
    fake = gptr_fake_provider(list(fake_tool("probe_safety"), "done"))
    peter("check", model = fake, tools = list(probe), .run = FALSE, envir = new.env())
  }
  # queued while the human layer keeps local-only inference, started after a human relaxed it
  s1 = queue()
  settings_write("session", list(providers = list(ollama = list(local_only = FALSE))))
  gptr_step(s1, turns = Inf)
  expect_identical(s1$text, "done")
  expect_identical(box$seen[[1L]]$ollama_local_only, FALSE)
  # queued while relaxed, started after the human tightened it again
  s2 = queue()
  settings_write("session", list(providers = list(ollama = list(local_only = TRUE))))
  gptr_wait(s2)
  expect_identical(box$seen[[2L]]$ollama_local_only, TRUE)
  expect_true(isTRUE(box$seen[[2L]]$unsafe_no_permissions))
  # options set between queueing and starting never relax it; the session layer, which is above
  # the option layer, is cleared first so that only the options could relax it
  the$settings_session$providers = NULL
  s3 = queue()
  local_gptr_options(providers = list(ollama = list(local_only = FALSE)),
                     providers.ollama.local_only = FALSE)
  gptr_step(s3, turns = Inf)
  expect_identical(box$seen[[3L]]$ollama_local_only, TRUE)
})

test_that("starting a pending run re-checks egress and replay; a refusal keeps it pending", {
  local_gw()
  local_gptr_options(replay = "auto")
  withr::local_envvar(GPTR_REPLAY = "auto")
  live = gptr_fake_provider(list("live answer"), name = "livefake")
  live$offline = FALSE
  settings_write("user", list(egress = list(livefake = "ack")))
  s = peter("x", model = live, .run = FALSE, envir = new.env())
  expect_true(gateway_pending_has(s$id))
  # the acknowledgement was withdrawn before the run started
  settings_write("user", list(egress = json_obj()))
  cnd = expect_error(gptr_step(s), class = "gptr_error_egress")
  expect_identical(cnd$provider, "livefake")
  expect_identical(s$status, "idle")
  expect_true(gateway_pending_has(s$id))
  # acknowledged again, but the process now replays
  settings_write("user", list(egress = list(livefake = "ack")))
  local_gptr_options(replay = "replay")
  expect_error(gptr_wait(s), class = "gptr_error_not_recorded")
  expect_true(gateway_pending_has(s$id))
  expect_length(fake_requests(live), 0L)
  # once both allow it, the pending call runs with its own run options and call record
  local_gptr_options(replay = "auto")
  gptr_step(s)
  expect_identical(s$text, "live answer")
  expect_length(fake_requests(live), 1L)
  expect_false(gateway_pending_has(s$id))
})

test_that("gptr_wait() checks every session before it starts any; a refusal starts none", {
  local_gw()
  local_gptr_options(replay = "auto")
  withr::local_envvar(GPTR_REPLAY = "auto")
  fake = local_fake_provider(list("offline answer"))
  live = gptr_fake_provider(list("live answer"), name = "livefake")
  live$offline = FALSE
  settings_write("user", list(egress = list(livefake = "ack")))
  a = peter("one", model = fake, .run = FALSE, envir = new.env())
  b = peter("two", model = live, .run = FALSE, envir = new.env())
  # the acknowledgement of b's provider was withdrawn before the wait
  settings_write("user", list(egress = json_obj()))
  cnd = expect_error(gptr_wait(list(a, b)), class = "gptr_error_egress")
  expect_identical(cnd$provider, "livefake")
  expect_identical(c(a$status, b$status), c("idle", "idle"))
  expect_null(sdk_run_of(a))
  expect_identical(a$turns, 0L)
  expect_true(gateway_pending_has(a$id))
  expect_true(gateway_pending_has(b$id))
  expect_length(fake_requests(fake), 0L)
  expect_length(fake_requests(live), 0L)
  # acknowledged again: one wait starts both with their own pending calls and settles them
  settings_write("user", list(egress = list(livefake = "ack")))
  gptr_wait(list(a, b))
  expect_identical(c(a$text, b$text), c("offline answer", "live answer"))
  expect_false(gateway_pending_has(a$id) || gateway_pending_has(b$id))
})

test_that("a follow-up on a session without a kept home runs in the verb's caller [R2]", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  box = new.env()
  probe = test_tool("probe_home", function(ctx) {
    box$home = run_current()$home
    "seen"
  })
  fake = local_fake_provider(list("first", fake_tool("probe_home"), "second"))
  make = function() peter("first", model = fake, tools = list(probe))
  s = make()
  expect_null(session_home(s))
  gptr_steer(s, "now probe", as = "follow_up")
  step = function() {
    here = environment()
    gptr_step(s, turns = Inf)
    here
  }
  frame = step()
  expect_identical(box$home, frame)
  expect_identical(s$text, "second")
  expect_identical(s$turns, 2L)
  expect_null(get0(s$id, envir = gateway_state()$held, inherits = FALSE))
})

test_that("gptr_return() keeps a name bound in the kept home by name (03 5.1)", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  home = new.env()
  home$fit = c(1, 2, 3)
  box = new.env()
  designate = test_tool("designate", function(ctx) {
    box$ret = eval(quote(gptr_return(fit)), home)
    "designated"
  })
  fake = local_fake_provider(list(fake_tool("designate"), "done"))
  s = peter("designate fit", model = fake, tools = list(designate), envir = home)
  expect_null(box$ret)
  expect_identical(s$value, c(1, 2, 3))
  entry = gateway_last_custom(session_data(s), "gptr.value")
  expect_identical(entry$name, "fit")
  expect_identical(entry$mode, "copy")
})

test_that("one approved gptr_cancel() call may cancel a list of other sessions (IC-53)", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  a = peter("a", model = fake, .run = FALSE, envir = new.env())
  b = peter("b", model = fake, .run = FALSE, envir = new.env())
  run = fake_run(session = "s9999999999")
  local_mocked_bindings(run_current = function() run)
  run$signal$control = "gptr_cancel"
  expect_invisible(gptr_cancel(list(a, b)))
  expect_length(run$signal$control, 0L)
  expect_error(gptr_cancel(list(a, b)), class = "gptr_error_permission")
  # the running session itself needs no approval
  run$session = a$id
  expect_invisible(gptr_cancel(a))
})

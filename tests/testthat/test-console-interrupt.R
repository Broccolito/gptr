# tests/testthat/test-console-interrupt.R -- the interrupt policy and the pause menu (plan P14).
# Task 3: menu, steering, abort and nesting with simulated interrupts. Task 7 appends the
# INFRA-03 test with real SIGINTs.

# A simulated Ctrl-C: an `interrupt` condition with a `resume` restart, as R's onintr() signals
# it during a computation (report 18 section 2.2.1). One that is neither resumed nor caught fails
# the test instead of jumping to the top level.
fake_interrupt = function() {
  cnd = structure(class = c("interrupt", "condition"), list(message = "", call = NULL))
  resumed = withRestarts({
    signalCondition(cnd)
    FALSE
  }, resume = function() TRUE)
  if (!isTRUE(resumed)) stop("the interrupt was neither resumed nor caught")
  invisible(TRUE)
}

# Menu answers for gptr_readline(), in order (a function answer is called: it may signal a
# second interrupt); a terminal front end where someone can answer
local_menu_answers = function(answers, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$answers = as.list(answers)
  log$prompts = character()
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    log$prompts = c(log$prompts, prompt)
    a = if (length(log$answers)) log$answers[[1L]] else "a"
    log$answers = log$answers[-1L]
    if (is.function(a)) a() else a
  }, front_end = function() "terminal", .env = .env)
  local_gptr_options(interactive = TRUE, .env = .env)
  log
}

# run_abort() replaced by a recorder (the runs below are stand-ins with the 04 section 7.6
# fields the policy reads: id, status, opts)
local_abort_log = function(.env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$aborted = character()
  testthat::local_mocked_bindings(run_abort = function(run, reason = "user") {
    log$aborted = c(log$aborted, run$id)
    run$status = "aborted"
    invisible(run)
  }, .env = .env)
  log
}

stand_in_run = function(id = "u0000run1", status = "streaming", background = FALSE) {
  run = new.env(parent = emptyenv())
  run$id = id
  run$status = status
  run$opts = list(background = background)
  class(run) = "gptr_run"
  run
}

policy_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
}

local_tracked = function(run, s, .env = parent.frame()) {
  console_track(run$id, s)
  withr::defer(console_drop(run$id), envir = .env)
  invisible(run)
}

notices = function(expr) {
  utils::capture.output(expr, type = "message")
}

test_that("continue resumes the interrupted computation", {
  log = local_menu_answers("c")
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "finished"
    }, list(), mode = "call")
  })
  expect_identical(res, "finished")
  expect_true(any(grepl("[gptr] paused: [c]ontinue, [a]bort", err, fixed = TRUE)))
  expect_true(any(grepl("[gptr] continuing", err, fixed = TRUE)))
})

test_that("steer and follow-up queue the text with source pause_menu (IC-55)", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  log = local_menu_answers(c("s", "use only mpg", "f", "then plot it"))
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      fake_interrupt()
      "done"
    }, list(run), mode = "call")
  })
  expect_identical(res, "done")
  q = session_data(s)$queue
  expect_identical(q$steer[[1L]]$text, "use only mpg")
  expect_identical(q$steer[[1L]]$source, "pause_menu")
  texts = vapply(q$follow_up, function(i) i$text, "")
  expect_true("then plot it" %in% texts)
  expect_true(any(grepl("[s]teer, [f]ollow-up, [c]ontinue, [a]bort", err, fixed = TRUE)))
  expect_identical(log$prompts, c("? ", "steer> ", "? ", "follow-up> "))
})

test_that("pause-menu text passes the input event with source steer", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  off = gptr_register(gptr_hook("input", function(event, ctx) {
    if (identical(event$source, "steer")) list(action = "transform", text = toupper(event$text))
  }))
  withr::defer(off())
  local_menu_answers(c("s", "use mpg"))
  notices(with_interrupt_policy(function() fake_interrupt(), list(run), mode = "call"))
  expect_identical(session_data(s)$queue$steer[[1L]]$text, "USE MPG")
})

test_that("abort in mode repl aborts the runs and returns NULL", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  local_menu_answers("a")
  res = "not set"
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "not reached"
    }, list(run), mode = "repl")
  })
  expect_null(res)
  expect_identical(aborted$aborted, "u0000run1")
  expect_true(any(grepl("[gptr] aborted; the session is kept.", err, fixed = TRUE)))
})

test_that("abort in mode call re-signals the interrupt so loops stop", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  local_menu_answers("a")
  res = NULL
  notices({
    res = tryCatch(with_interrupt_policy(function() {
      fake_interrupt()
      "not reached"
    }, list(run), mode = "call"), interrupt = function(e) "outer handler saw it")
  })
  expect_identical(res, "outer handler saw it")
  expect_identical(aborted$aborted, "u0000run1")
})

test_that("a second Ctrl-C while the menu waits aborts", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  second = function() {
    signalCondition(structure(class = c("interrupt", "condition"),
                              list(message = "", call = NULL)))
    "c"
  }
  local_menu_answers(list(second))
  res = "not set"
  notices({
    res = with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl")
  })
  expect_null(res)
  expect_identical(aborted$aborted, "u0000run1")
})

test_that("the policy is abort-only where resuming is unverified (RStudio, Rgui, Jupyter)", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  log = local_menu_answers("c")
  for (fe in c("rstudio", "rgui", "jupyter")) {
    local_mocked_bindings(front_end = function() fe)
    run$status = "streaming"
    res = "not set"
    notices({
      res = with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl")
    })
    expect_null(res)
  }
  expect_identical(log$prompts, character())
  expect_identical(aborted$aborted, rep("u0000run1", 3L))
})

test_that("nested policies show one menu and the inner runs join the outer one", {
  s = policy_session()
  outer_run = local_tracked(stand_in_run("u0000run1"), s)
  inner_run = local_tracked(stand_in_run("u0000run2"), s)
  aborted = local_abort_log()
  log = local_menu_answers("a")
  box = new.env(parent = emptyenv())
  res = "not set"
  notices({
    res = with_interrupt_policy(function() {
      with_interrupt_policy(function() {
        box$seen = vapply(policy_find()$runs, function(r) r$id, "")
        fake_interrupt()
      }, list(inner_run), mode = "call")
    }, list(outer_run), mode = "repl")
  })
  expect_null(res)
  expect_identical(box$seen, c("u0000run1", "u0000run2"))
  expect_identical(log$prompts, "? ")
  expect_setequal(aborted$aborted, c("u0000run1", "u0000run2"))
})

test_that("[b]ackground hands a foreground run to bg.register (P21) and resumes", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  old = the$services
  withr::defer({
    the$services = old
  })
  got = new.env(parent = emptyenv())
  ext_service_set("bg.register", function(session) {
    got$session = session
    invisible(session)
  }, provided_by = "test")
  local_menu_answers("b")
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "kept running"
    }, list(run), mode = "call")
  })
  expect_identical(res, "kept running")
  expect_identical(got$session, s)
  expect_true(any(grepl("[b]ackground", err, fixed = TRUE)))
  local_menu_answers(c("b", "c"))
  err = notices(with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl"))
  expect_false(any(grepl("[b]ackground", err, fixed = TRUE)))
})

test_that("a steer typed while a tool runs is queued once no tool is on the stack", {
  s = policy_session()
  tool_run = stand_in_run("u0000tool")
  local({
    local_mocked_bindings(run_current = function() tool_run)
    notices(policy_enqueue(s, "after the tool", "steer"))
    expect_length(session_data(s)$queue$steer, 0L)
  })
  reactor_pump(until = function() length(session_data(s)$queue$steer) > 0L, slice_ms = 10L,
               timeout = 5)
  expect_identical(session_data(s)$queue$steer[[1L]]$text, "after the tool")
  expect_identical(session_data(s)$queue$steer[[1L]]$source, "pause_menu")
})

test_that("a steer typed while a tool runs reaches the request after the tool result", {
  local_project()
  local_gptr_options(unsafe_no_permissions = TRUE)
  off = gptr_register(gptr_tool("slow", "Test tool slow", execute = function(input, ctx) {
    fake_interrupt()
    "slow done"
  }))
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("slow"), "ack", "done"))
  s = session_new("fake/fake-1", "auto", home = new.env())
  local_menu_answers(c("s", "use mpg"))
  run = local_tracked(run_start(s, msg_user("go")), s)
  notices(with_interrupt_policy(function() run_wait(run), list(run), mode = "call"))
  msgs = fake_requests(fake)[[2L]]$messages
  expect_identical(msgs[[length(msgs)]]$role, "operator")
  expect_match(json_encode(msgs[[length(msgs)]]), "use mpg", fixed = TRUE)
})

test_that("a steer typed in a tool and then aborted is listed as dropped, never sent later", {
  local_project()
  local_gptr_options(unsafe_no_permissions = TRUE)
  off = gptr_register(gptr_tool("slow", "Test tool slow", execute = function(input, ctx) {
    fake_interrupt()
    fake_interrupt()
    "slow done"
  }))
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("slow"), "done", "done"))
  s = session_new("fake/fake-1", "auto", home = new.env())
  local_menu_answers(c("s", "use mpg", "a"))
  run = local_tracked(run_start(s, msg_user("go")), s)
  err = notices({
    with_interrupt_policy(function() run_wait(run), list(run), mode = "repl")
    run_wait(run_start(s, msg_user("an unrelated prompt")))
  })
  expect_identical(run$status, "aborted")
  expect_true(any(grepl("[gptr] dropped queued messages: 'use mpg'", err, fixed = TRUE)))
  expect_length(session_data(s)$queue$steer, 0L)
  reqs = fake_requests(fake)
  expect_no_match(json_encode(reqs[[length(reqs)]]$messages), "use mpg", fixed = TRUE)
})

test_that("a steer typed in a tool that pumps the reactor reaches the next request", {
  local_project()
  local_gptr_options(unsafe_no_permissions = TRUE)
  off = gptr_register(gptr_tool("slow", "Test tool slow", execute = function(input, ctx) {
    fake_interrupt()
    reactor_pump(slice_ms = 1L, allow_runs = character(), timeout = 0.001)
    "slow done"
  }))
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("slow"), "ack", "done"))
  s = session_new("fake/fake-1", "auto", home = new.env())
  # the tool_execution_end hook of builtin:console (Task 7); the steer is queued when it returns
  box = new.env(parent = emptyenv())
  off_hook = gptr_register(gptr_hook("tool_execution_end", function(event, ctx) {
    console_on_tool_end(event, ctx)
    box$queued = length(session_data(s)$queue$steer)
    NULL
  }))
  withr::defer(off_hook())
  local_menu_answers(c("s", "use mpg"))
  run = local_tracked(run_start(s, msg_user("go")), s)
  notices(with_interrupt_policy(function() run_wait(run), list(run), mode = "call"))
  expect_identical(box$queued, 1L)
  msgs = fake_requests(fake)[[2L]]$messages
  expect_identical(msgs[[length(msgs)]]$role, "operator")
  expect_match(json_encode(msgs[[length(msgs)]]), "use mpg", fixed = TRUE)
})

test_that("a [b]ackground refusal is a notice and the menu asks again", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  old = the$services
  withr::defer({
    the$services = old
  })
  ext_service_set("bg.register", function(session) {
    gptr_abort("Background sessions need the 'later' package.", "missing_package")
  }, provided_by = "test")
  log = local_menu_answers(c("b", "c"))
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "kept running"
    }, list(run), mode = "call")
  })
  expect_identical(res, "kept running")
  expect_true(any(grepl("[gptr] cannot run in the background: Background sessions need",
                        err, fixed = TRUE)))
  expect_identical(log$prompts, c("? ", "? "))
})

test_that("the policy is the console.interrupt_policy service of builtin:console", {
  expect_identical(the$services[["console.interrupt_policy"]]$provided_by, "P14")
  expect_identical(the$services[["console.interrupt_policy"]]$builtin, "console")
  expect_identical(names(formals(the$services[["console.interrupt_policy"]]$fun)),
                   c("expr_fun", "runs", "mode"))
})

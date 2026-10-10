# Normal notebook progress belongs to stdout; failures and other front ends keep messages.
jupyter_progress_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_gptr_options(quiet = FALSE, verbose = 1L, .env = .env)
  withr::local_options(
    jupyter.in_kernel = TRUE, knitr.in.progress = NULL, cli.dynamic = FALSE,
    cli.unicode = FALSE, cli.num_colors = 1L, .local_envir = .env
  )
  s = peter("offline progress", model = gptr_fake_provider(list("unused")),
            .run = FALSE, envir = new.env())
  rec = console_track("ujupyter-progress", s)
  withr::defer(console_drop("ujupyter-progress"), envir = .env)
  rec
}

jupyter_progress_capture = function(expr) {
  messages = character()
  output = utils::capture.output({
    messages = testthat::capture_messages(force(expr))
  })
  list(output = output, messages = messages)
}

jupyter_progress_event = function(type, rec, ...) {
  ev_new(type, session = rec$session$id, run = "ujupyter-progress", ...)
}

jupyter_progress_normal = function(rec) {
  console_wait_start(rec)
  console_on_tool_start(jupyter_progress_event("tool_execution_start", rec,
    tool_call_id = "c1", tool_name = "r", input = list(code = "dim(dat)")), NULL)
  console_on_agent_end(jupyter_progress_event("agent_end", rec, status = "idle",
    turns = 1L, usage = list(input = 10, output = 5, cost = NA_real_)), NULL)
}

test_that("IRkernel waiting feedback is stdout at verbosity 1 and 2", {
  rec = jupyter_progress_session()
  for (level in c(1L, 2L)) {
    local_gptr_options(verbose = level)
    captured = jupyter_progress_capture(console_wait_start(rec))
    expect_identical(captured$output, "gptr: thinking")
    expect_identical(captured$messages, character())
  }
})

test_that("IRkernel normal tool and successful completion progress is stdout", {
  rec = jupyter_progress_session()
  captured = jupyter_progress_capture(jupyter_progress_normal(rec))
  expect_identical(captured$output, c("gptr: thinking", "gptr: r  dim(dat)",
                                     "gptr: done | 1 turn | 15 tokens | unknown cost"))
  expect_identical(captured$messages, character())
  expect_null(console_record(list(run = "ujupyter-progress")))
})

test_that("quiet and verbosity zero suppress normal notebook progress", {
  for (quiet in c(TRUE, FALSE)) {
    rec = jupyter_progress_session()
    local_gptr_options(quiet = quiet, verbose = if (quiet) 1L else 0L)
    captured = jupyter_progress_capture(jupyter_progress_normal(rec))
    expect_identical(captured$output, character())
    expect_identical(captured$messages, character())
    expect_null(console_record(list(run = "ujupyter-progress")))
  }
  rec = jupyter_progress_session()
  local_gptr_options(quiet = TRUE, verbose = 2L)
  captured = jupyter_progress_capture(console_wait_start(rec))
  expect_identical(captured$output, character())
  expect_identical(captured$messages, character())
})

test_that("IRkernel tool failure and abnormal completion remain stderr messages", {
  rec = jupyter_progress_session()
  captured = jupyter_progress_capture({
    console_on_tool_end(jupyter_progress_event("tool_execution_end", rec,
      tool_call_id = "c1", tool_name = "r", is_error = TRUE), NULL)
    console_on_agent_end(jupyter_progress_event("agent_end", rec, status = "error",
      reason = "synthetic failure", turns = 1L, usage = NULL), NULL)
  })
  expect_identical(captured$output, character())
  expect_identical(captured$messages, c("gptr: r failed\n",
    "gptr: error: synthetic failure | 1 turn | 0 tokens | $0.0000\n"))
  expect_null(console_record(list(run = "ujupyter-progress")))
})

test_that("nonkernel and knitr progress keeps its existing stderr route", {
  for (knitting in c(FALSE, TRUE)) {
    rec = jupyter_progress_session()
    withr::local_options(jupyter.in_kernel = knitting, knitr.in.progress = knitting)
    captured = jupyter_progress_capture(jupyter_progress_normal(rec))
    expect_identical(captured$output, character())
    expect_identical(captured$messages, c("gptr: thinking\n", "gptr: r  dim(dat)\n",
      "gptr: done | 1 turn | 15 tokens | unknown cost\n"))
    expect_null(console_record(list(run = "ujupyter-progress")))
  }
})

test_that("background sessions and nested tools stay silent in IRkernel", {
  rec = jupyter_progress_session()
  live = session_live(rec$session)
  live$background = list(id = "offline-background")
  withr::defer({
    live$background = NULL
  })
  captured = jupyter_progress_capture(jupyter_progress_normal(rec))
  expect_identical(captured$output, character())
  expect_identical(captured$messages, character())

  rec = jupyter_progress_session()
  local_mocked_bindings(run_current = function() structure(new.env(), class = "gptr_run"))
  captured = jupyter_progress_capture(jupyter_progress_normal(rec))
  expect_identical(captured$output, character())
  expect_identical(captured$messages, character())
})

test_that("notebook tool progress prints escaped input without interpreting braces", {
  rec = jupyter_progress_session()
  captured = jupyter_progress_capture(console_on_tool_start(
    jupyter_progress_event("tool_execution_start", rec, tool_call_id = "c1", tool_name = "r",
      input = list(code = "x = '{not_an_expression}' # \033[31m")), NULL))
  expect_identical(captured$output, "gptr: r  x = '{not_an_expression}' # <U+001B>[31m")
  expect_identical(captured$messages, character())
})

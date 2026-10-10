# Waiting feedback must precede live inference, remain outside captured R-tool output, and
# survive a resumed pause. These tests drive renderer hooks directly; no request is sent.
wait_record = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_fake_provider(list("ok"), .env = .env)
  s = session_new("fake/fake-1", "auto", home = new.env())
  run = new.env(parent = emptyenv())
  run$id = "u0000wait"
  run$status = "streaming"
  run$opts = list(background = FALSE)
  class(run) = "gptr_run"
  live = session_live(s)
  live$run = run
  ctx = live$ctx
  console_on_agent_start(ev_new("agent_start", run = run$id), ctx)
  withr::defer({
    console_drop(run$id)
    live$run = NULL
  }, envir = .env)
  list(s = s, live = live, ctx = ctx, run = run, rec = console_record(list(run = run$id)))
}

wait_request = function(w) {
  console_on_before_request(ev_new("before_request", run = w$run$id, request_id = "q-wait",
                                  model = "fake/fake-1", tokens_est = 10), w$ctx)
}

wait_delta = function(w, text) {
  console_on_message_update(ev_new("message_update", run = w$run$id, index = 1L,
                                  kind = "text", delta = text), w$ctx)
}

wait_interrupt = function() {
  cnd = structure(list(message = "", call = NULL), class = c("interrupt", "condition"))
  withRestarts(signalCondition(cnd), resume = function() invisible(NULL))
}

test_that("verbosity 1 announces inference on stderr without animation", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 1L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  out = utils::capture.output({
    expect_message(wait_request(w), "gptr: thinking", fixed = TRUE)
  })
  expect_identical(out, character())
  expect_null(w$rec$task)
  expect_null(w$rec$spinner)
})

test_that("a non-dynamic streamed console receives a concise waiting message", {
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = FALSE)
  w = wait_record()
  expect_message(wait_request(w), "gptr: thinking", fixed = TRUE)
  expect_null(w$rec$task)
  expect_null(w$rec$spinner)
})

test_that("verbosity zero and background requests produce no waiting feedback", {
  local_gptr_options(verbose = 0L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  expect_no_message(expect_output(wait_request(w), NA))
  expect_null(w$rec$task)
  local_gptr_options(verbose = 2L)
  w$live$background = list(id = "b-wait")
  expect_no_message(expect_output(wait_request(w), NA))
  expect_null(w$rec$task)
})

test_that("a dynamic spinner starts immediately and survives buffered text", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  first = utils::capture.output(invisible(wait_request(w)))
  expect_true(any(grepl("thinking", first, fixed = TRUE)))
  for (delta in c("", "\n", " \t", "```r")) {
    utils::capture.output(invisible(wait_delta(w, delta)))
    expect_false(is.null(w$rec$task))
    expect_false(is.null(w$rec$spinner))
  }
  visible = utils::capture.output(invisible(wait_delta(w, "\nx = 1\n")))
  expect_true(any(grepl("x = 1", visible, fixed = TRUE)))
  expect_null(w$rec$task)
  expect_null(w$rec$spinner)
})

test_that("spinner redraws cannot enter a nested R tool's captured output", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  utils::capture.output(invisible(wait_request(w)))
  task = get(w$rec$task, envir = reactor_get()$tasks)
  w$rec$spinner$last = 0
  nested = function() {
    .gptr_tool_run = w$run
    force(.gptr_tool_run)
    utils::capture.output(invisible(task$fn()))
  }
  expect_identical(nested(), character())
  expect_false(is.null(w$rec$task))
  w$rec$spinner$last = 0
  w$live$background = list(id = "b-wait")
  expect_identical(utils::capture.output(invisible(task$fn())), character())
})

test_that("an abort-only IDE console advertises its stop key without promising steering", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, interactive = TRUE)
  withr::local_options(cli.dynamic = TRUE)
  testthat::local_mocked_bindings(front_end = function() "rstudio")
  w = wait_record()
  out = utils::capture.output(invisible(wait_request(w)))
  expect_true(any(grepl("Esc to stop", out, fixed = TRUE)))
  expect_false(any(grepl("steer", out, fixed = TRUE)))
})

test_that("continue and queued pause messages restore a pending request's spinner", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, interactive = TRUE, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  answers = new.env(parent = emptyenv())
  answers$left = c("c", "s", "use only x", "f", "then summarize")
  testthat::local_mocked_bindings(front_end = function() "terminal",
    gptr_readline = function(prompt = "") {
      ans = answers$left[[1L]]
      answers$left = answers$left[-1L]
      ans
    })
  utils::capture.output(invisible(wait_request(w)))
  for (i in seq_len(3L)) {
    utils::capture.output({
      utils::capture.output({
        with_interrupt_policy(wait_interrupt, list(w$run), mode = "call")
      }, type = "message")
    })
    expect_false(is.null(w$rec$task))
    expect_false(is.null(w$rec$spinner))
  }
  expect_identical(length(session_data(w$s)$queue$steer), 1L)
  expect_identical(length(session_data(w$s)$queue$follow_up), 1L)
})

test_that("message completion and agent errors cancel waiting tasks", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  utils::capture.output(invisible(wait_request(w)))
  task = w$rec$task
  utils::capture.output(invisible(console_on_message_end(
    ev_new("message_end", run = w$run$id,
           message = msg_assistant("", api = "fake", provider = "fake", model = "fake-1")),
    w$ctx)))
  expect_null(w$rec$task)
  expect_false(exists(task, envir = reactor_get()$tasks, inherits = FALSE))
  utils::capture.output(invisible(wait_request(w)))
  task = w$rec$task
  utils::capture.output(invisible(console_on_agent_end(
    ev_new("agent_end", run = w$run$id, status = "error", reason = "synthetic error"), w$ctx)))
  expect_null(console_record(list(run = w$run$id)))
  expect_false(exists(task, envir = reactor_get()$tasks, inherits = FALSE))
})

test_that("background notices remove all synthetic bidi and invisible controls", {
  controls = c(0x061CL, 0x2060L:0x2065L, 0x2066L:0x2069L, 0xFEFFL)
  for (cp in controls) {
    expect_identical(bg_clean(paste0("left", intToUtf8(cp), "right")), "left right")
  }
  expect_identical(bg_clean("literal <U+2060>"), "literal <U+2060>")
  expect_identical(bg_clean(c(NA_character_, "safe")), c("", "safe"))
})

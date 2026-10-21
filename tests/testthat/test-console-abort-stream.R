# Resumable pauses keep the redactor intact; only terminal abort may drain its safe tail.
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

abort_stream_run = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_vault(.env = .env)
  local_gptr_options(unsafe_no_permissions = TRUE, .env = .env)
  local_fake_provider(list(list(hang = TRUE)), .env = .env)
  s = session_new("fake/fake-1", "auto", home = new.env())
  run = run_start(s, msg_user("Show the streamed answer."))
  withr::defer({
    if (!isTRUE(run$settled)) run_abort(run, "test cleanup")
    console_drop(run$id)
  }, envir = .env)
  reactor_pump(until = function() identical(run$status, "streaming"), timeout = 10)
  expect_identical(run$status, "streaming")
  run
}

abort_stream_delta = function(run, text) {
  run_on_event(run, ev_new("text_delta", index = 1L, delta = text))
}

test_that("abort labels a redactor tail received after a pause without printing it twice", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  run = abort_stream_run()
  out = utils::capture.output({
    abort_stream_delta(run, "Hello world")
    console_render_pause()
    run_abort(run, "user")
    run_abort(run, "user")
  })
  expect_identical(utils::head(out, 3L), c("Hello", "[gptr] final received text:", "world"))
  expect_identical(sum(out == "[gptr] final received text:"), 1L)
  expect_identical(sum(out == "world"), 1L)
  expect_identical(msg_text(utils::tail(run$shell$messages, 1L)[[1L]]), "Hello world")
  expect_null(console_record(list(run = run$id)))
})

test_that("continuing a pause never adds an abort-tail label", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  run = abort_stream_run()
  out = utils::capture.output({
    abort_stream_delta(run, "Hello world")
    console_render_pause()
    console_render_resume(list(run))
    abort_stream_delta(run, " again.")
    run_abort(run, "user")
  })
  expect_false(any(grepl("final received text", out, fixed = TRUE)))
  expect_identical(msg_text(utils::tail(run$shell$messages, 1L)[[1L]]), "Hello world again.")
})

test_that("a synthetic secret split across pause and resume stays protected", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  run = abort_stream_run()
  secret = paste0("pause-", strrep("FAKE", 8L))
  secret_register(secret, "PAUSE_TEST_TOKEN", source = "test")
  first = substr(secret, 1L, 13L)
  before = utils::capture.output({
    abort_stream_delta(run, paste0("Before ", first))
    console_render_pause()
  })
  expect_false(any(grepl(first, before, fixed = TRUE)))
  after = utils::capture.output({
    console_render_resume(list(run))
    abort_stream_delta(run, substring(secret, 14L))
    run_abort(run, "user")
  })
  expect_false(any(grepl(first, after, fixed = TRUE)))
  expect_false(any(grepl(secret, after, fixed = TRUE)))
  expect_true(any(grepl("[secret:PAUSE_TEST_TOKEN]", after, fixed = TRUE)))
})

test_that("aborting an in-flight request records unknown usage once", {
  local_gptr_options(verbose = 0L)
  run = abort_stream_run()
  abort_stream_delta(run, "Partial answer")
  run_abort(run, "user")
  run_abort(run, "user")
  usage = session_usage_rows(run$shell)
  expect_equal(nrow(usage), 1L)
  expect_identical(usage$request_id, run$request_id)
  expect_identical(usage$stop_reason, "aborted")
  expect_true(all(is.na(unlist(usage[usage_token_columns]))))
  expect_false(usage$estimated)
  expect_identical(unname(attr(usage, "totals")[["requests"]]), 1)
  expect_match(session_footer(run$shell), "unknown tokens.*unknown cost")
})

test_that("aborting preserves explicitly known partial usage and CLI cost", {
  local_gptr_options(verbose = 0L)
  run = abort_stream_run()
  msg = run$acc$message()
  msg$route = "plan-cli"
  msg$usage = list(input = 100, output = 20, cache_read = 0, cache_write_5m = 0,
                   cache_write_1h = 0, reasoning = 0, images = 0,
                   cost = list(total = 0.125))
  run$acc$message = function() msg
  run_abort(run, "user")
  usage = session_usage_rows(run$shell)
  expect_equal(nrow(usage), 1L)
  expect_identical(usage$input, 100)
  expect_identical(usage$output, 20)
  expect_identical(usage$cost, 0.125)
  expect_identical(usage$request_id, run$request_id)
})

test_that("missing fields of partial usage are unknown rather than legacy zeros", {
  local_gptr_options(verbose = 0L)
  run = abort_stream_run()
  msg = run$acc$message()
  msg$usage = list(input = 100)
  run$acc$message = function() msg
  run_abort(run, "user")
  usage = session_usage_rows(run$shell)
  expect_equal(nrow(usage), 1L)
  expect_identical(usage$input, 100)
  expect_true(all(is.na(unlist(usage[setdiff(usage_token_columns, "input")]))))
})

test_that("partial API counters do not establish the final request charge", {
  local_gptr_options(verbose = 0L)
  run = abort_stream_run()
  msg = run$acc$message()
  msg$usage = list(input = 100, output = 20, cache_read = 0, cache_write_5m = 0,
                   cache_write_1h = 0, reasoning = 0, images = 0)
  run$acc$message = function() msg
  run_abort(run, "user")
  usage = session_usage_rows(run$shell)
  expect_identical(usage$input, 100)
  expect_identical(usage$output, 20)
  expect_true(is.na(usage$cost))
})

test_that("abort keeps an existing request usage row and does not duplicate it", {
  local_gptr_options(verbose = 0L)
  run = abort_stream_run()
  msg = run$acc$message()
  msg$request_id = run$request_id
  msg$usage = usage_new(input = 100, output = 20)
  row = usage_row(msg, session = run$shell$id, agent = "main", parent_id = NA_character_,
                  started = run$request_started, seconds = 1, multiplier = 1)
  usage_add(run$shell, row)
  run_abort(run, "user")
  expect_equal(nrow(session_usage_rows(run$shell)), 1L)
  expect_identical(session_usage_rows(run$shell)$input, 100)
})

test_that("a queued run aborted before any request does not invent a usage row", {
  local_project()
  local_gptr_options(unsafe_no_permissions = TRUE, verbose = 0L)
  local_fake_provider(list("never requested"))
  s = session_new("fake/fake-1", "auto", home = new.env())
  run = run_start(s, msg_user("Do not start."))
  expect_identical(run$status, "queued")
  run_abort(run, "user")
  expect_equal(nrow(session_usage_rows(s)), 0L)
})

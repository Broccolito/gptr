# Block boundaries must reach the console in provider order, including the redactor's held
# tail. The fake request waits after its start event; the tests then supply normalized events
# through the same callbacks as an HTTP or CLI provider. No network or real CLI is used.
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

stream_order_run = function(.env = parent.frame()) {
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

stream_order_block = function(run, index, chunks, kind = "text", end = TRUE) {
  run_on_event(run, ev_new(paste0(kind, "_start"), index = index))
  for (delta in chunks) {
    run_on_event(run, ev_new(paste0(kind, "_delta"), index = index, delta = delta))
  }
  text = paste(chunks, collapse = "")
  block = if (identical(kind, "thinking")) block_thinking(text) else block_text(text)
  if (end) run_on_event(run, ev_new(paste0(kind, "_end"), index = index, block = block))
  invisible(block)
}

stream_order_finish = function(run) {
  msg = run$acc$message()
  run_on_event(run, ev_new("done", reason = "stop", message = msg, usage = msg$usage))
  run_on_done(run, msg)
  reactor_pump(until = function() isTRUE(run$settled), timeout = 10)
  expect_identical(run$shell$status, "idle")
  invisible(msg)
}

stream_order_text = function(events) paste(vapply(events, function(ev) ev$delta, ""), collapse = "")

test_that("a text block's held tail is emitted at its end before the next block", {
  local_gptr_options(verbose = 0L)
  updates = local_events("message_update")
  run = stream_order_run()
  stream_order_block(run, 1L, c("First ", "tail"))
  expect_identical(stream_order_text(updates(run$shell)), "First tail")
  stream_order_block(run, 2L, "\nSecond ending")
  expect_identical(stream_order_text(updates(run$shell)), "First tail\nSecond ending")
  stream_order_finish(run)
  expect_identical(stream_order_text(updates(run$shell)), "First tail\nSecond ending")
})

test_that("thinking finishes visibly before the answer without a second thinking header", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 3L)
  updates = local_events("message_update")
  run = stream_order_run()
  out = utils::capture.output({
    stream_order_block(run, 1L, "Plan finished", kind = "thinking")
    stream_order_block(run, 2L, "Answer complete")
    stream_order_finish(run)
  })
  ev = updates(run$shell)
  expect_identical(vapply(ev, function(e) e$kind, ""), c("thinking", "thinking", "text", "text"))
  expect_identical(utils::head(out, 3L), c("  (thinking)", "Plan finished", "Answer complete"))
  expect_identical(sum(grepl("(thinking)", out, fixed = TRUE)), 1L)
})

test_that("more than nine completed blocks keep their numeric provider order", {
  local_gptr_options(verbose = 0L)
  updates = local_events("message_update")
  run = stream_order_run()
  words = sprintf("block%02d", seq_len(12L))
  for (i in seq_along(words)) stream_order_block(run, i, words[[i]])
  expect_identical(vapply(updates(run$shell), function(ev) ev$index, 1L), seq_len(12L))
  stream_order_finish(run)
  expect_identical(vapply(updates(run$shell), function(ev) ev$index, 1L), seq_len(12L))
  expect_identical(stream_order_text(updates(run$shell)), paste(words, collapse = ""))
})

test_that("completion without block ends flushes open tails in provider order", {
  local_gptr_options(verbose = 0L)
  updates = local_events("message_update")
  run = stream_order_run()
  words = sprintf("open%02d", seq_len(12L))
  for (i in seq_along(words)) stream_order_block(run, i, words[[i]], end = FALSE)
  expect_length(updates(run$shell), 0L)
  stream_order_finish(run)
  expect_identical(vapply(updates(run$shell), function(ev) ev$index, 1L), seq_len(12L))
  expect_identical(stream_order_text(updates(run$shell)), paste(words, collapse = ""))
})

test_that("block end and request completion never emit a held tail twice", {
  local_gptr_options(verbose = 0L)
  updates = local_events("message_update")
  run = stream_order_run()
  block = stream_order_block(run, 1L, "Only once")
  expect_identical(stream_order_text(updates(run$shell)), "Only once")
  run_on_event(run, ev_new("text_end", index = 1L, block = block))
  run_flush_deltas(run)
  run_flush_deltas(run)
  msg = stream_order_finish(run)
  run_on_done(run, msg)
  expect_identical(stream_order_text(updates(run$shell)), "Only once")
  expect_identical(vapply(updates(run$shell), function(ev) ev$delta, ""), c("Only ", "once"))
})

test_that("a synthetic secret split across deltas stays redacted when its block closes", {
  local_gptr_options(verbose = 0L)
  updates = local_events("message_update")
  run = stream_order_run()
  secret = paste0("offline-", strrep("FAKE", 8L))
  secret_register(secret, "STREAM_ORDER_TOKEN", source = "test")
  chunks = c("Use ", substr(secret, 1L, 13L), substr(secret, 14L, nchar(secret)))
  stream_order_block(run, 1L, chunks)
  expect_identical(stream_order_text(updates(run$shell)), "Use [secret:STREAM_ORDER_TOKEN]")
  stream_order_finish(run)
  text = stream_order_text(updates(run$shell))
  expect_identical(text, "Use [secret:STREAM_ORDER_TOKEN]")
  expect_false(grepl(secret, text, fixed = TRUE))
  expect_false(any(vapply(updates(run$shell), function(ev) {
    grepl(substr(secret, 1L, 13L), ev$delta, fixed = TRUE)
  }, NA)))
})

test_that("cancelling a streamed answer displays the complete safe partial tail", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  updates = local_events("message_update")
  run = stream_order_run()
  out = utils::capture.output({
    stream_order_block(run, 1L, "Hello world", end = FALSE)
    run_abort(run, "user")
  })
  expect_identical(out[[1L]], "Hello world")
  expect_identical(stream_order_text(updates(run$shell)), "Hello world")
  last = utils::tail(run$shell$messages, 1L)[[1L]]
  expect_identical(msg_text(last), "Hello world")
  expect_identical(last$stop_reason, "aborted")
  expect_identical(run$shell$status, "aborted")
  expect_null(session_live(run$shell)$run)
  expect_null(console_record(list(run = run$id)))
})

test_that("cancellation flushes a held synthetic secret safely and only once", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  updates = local_events("message_update")
  run = stream_order_run()
  secret = paste0("cancel-", strrep("FAKE", 8L))
  secret_register(secret, "STREAM_CANCEL_TOKEN", source = "test")
  out = utils::capture.output({
    stream_order_block(run, 1L, c("Before ", secret), end = FALSE)
    run_abort(run, "user")
    run_abort(run, "user")
  })
  want = "Before [secret:STREAM_CANCEL_TOKEN]"
  expect_identical(out[[1L]], want)
  expect_identical(stream_order_text(updates(run$shell)), want)
  expect_false(any(grepl(secret, out, fixed = TRUE)))
})

test_that("a failed-closed redactor never releases held bytes on end or completion", {
  local_gptr_options(verbose = 0L, stream_hold_max = 4L)
  updates = local_events("message_update")
  run = stream_order_run()
  run_on_event(run, ev_new("text_start", index = 1L))
  expect_error(run_on_event(run, ev_new("text_delta", index = 1L, delta = "too-long")),
               class = "gptr_error_redaction_limit")
  run_on_event(run, ev_new("text_end", index = 1L, block = block_text("too-long")))
  stream_order_finish(run)
  expect_length(updates(run$shell), 0L)
})

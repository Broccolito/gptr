# Deferred, offline checkpoint requests must not turn a finite wait into cancellation.
# A fixed reactor abort bounds the uncorrected nested wait; the outer runner remains 30 s.

cp_wait_fixture = function(script, budget = NULL, should = TRUE, .env = parent.frame()) {
  check_flag(should, "should")
  local_project(.env = .env)
  local_gptr_options(quiet = TRUE, compact_at = Inf, .env = .env)
  fake = local_fake_provider(script, .env = .env)
  home = new.env(parent = baseenv())
  home$dat = datasets::mtcars
  home$beta = stats::coef(stats::lm(mpg ~ wt + hp, data = home$dat))
  s = session_new("fake/fake-1", "auto", home = home)
  session_append(s, list(type = "message", message = msg_user("Keep the public-data fit.")))
  events = new.env(parent = emptyenv())
  events$types = character()
  subscribe = function(type) {
    off = gptr_register(gptr_hook(type, function(event, ctx) {
      events$types = c(events$types, event$type)
      NULL
    }))
    withr::defer(off(), envir = .env)
  }
  for (type in c("session_before_compact", "before_request", "usage", "session_compact",
                 "agent_end")) subscribe(type)
  local_service("compact.should", function(s, tokens, idle) should, .env = .env)
  run = run_start(s, msg_user("Continue without changing the objects."), list(budget = budget))
  before = session_data(s)$entries
  guard_at = reactor_now() + 0.8
  guard = reactor_timer(guard_at, function() run_abort(run, "fixture-guard"))
  withr::defer({
    reactor_cancel(guard)
    gptr_cancel(s)
  }, envir = .env)
  list(s = s, run = run, fake = fake, home = home, before = before, events = events,
       guard = guard, guard_at = guard_at)
}

cp_wait_short = function(x) {
  started = reactor_now()
  result = gptr_wait(x$s, timeout = 0.04)
  list(value = result, elapsed = reactor_now() - started)
}

# A finite wait may return before the newly scheduled fake generator is called.
# Admit that generator through separate finite waits under the original fixture deadline.
cp_wait_admit = function(x, requests = 1L) {
  elapsed = numeric()
  values = logical()
  pending = x$run$compact_pending
  ids = x$run$request_ids
  retained = TRUE
  while (length(fake_requests(x$fake)) < requests && !isTRUE(x$run$settled) &&
         reactor_now() < x$guard_at) {
    short = cp_wait_short(x)
    elapsed = c(elapsed, short$elapsed)
    values = c(values, identical(short$value, x$s))
    if (!is.null(pending)) {
      retained = retained && identical(x$run$compact_pending, pending) &&
        identical(x$run$request_ids, ids)
    } else if (!is.null(x$run$compact_pending)) {
      pending = x$run$compact_pending
      ids = x$run$request_ids
    }
  }
  list(started = identical(length(fake_requests(x$fake)), requests), elapsed = elapsed,
       values = values, retained = retained)
}

cp_wait_admitted = function(admission) {
  expect_true(admission$started)
  expect_true(all(admission$elapsed < 0.2))
  expect_true(all(admission$values))
  expect_true(admission$retained)
}

cp_wait_entries = function(s) {
  Filter(function(entry) identical(entry$type, "compaction"), session_data(s)$entries)
}

cp_wait_prefix = function(x) {
  expect_identical(session_data(x$s)$entries[seq_along(x$before)], x$before)
}

cp_wait_finished = function(x) {
  expect_null(x$run$compact_pending)
  expect_null(x$run$compact_finish)
  expect_null(x$run$compact_defer)
  expect_null(session_live(x$s)$run)
  expect_false(isTRUE(session_live(x$s)$compacting))
  expect_true(x$run$settled)
  expect_null(x$run$home)
  expect_identical(anyDuplicated(x$s$usage$request_id), 0L)
}

test_that("a finite public wait yields a deferred checkpoint and a second wait completes it", {
  x = cp_wait_fixture(list(fake_text("Remember the fit.", delay = 0.3,
                                    usage = usage_new(input = 100, output = 5)), "Done."))
  bytes = serialize(list(dat = x$home$dat, beta = x$home$beta), NULL)
  address = rlang::obj_address(x$home$dat)
  tick = new.env(parent = emptyenv())
  tick$fired = FALSE
  id = reactor_timer(reactor_now() + 0.01, function() tick$fired = TRUE)
  withr::defer(reactor_cancel(id))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  pending = x$run$compact_pending
  ids = x$run$request_ids
  again = cp_wait_short(x)
  guard_released = FALSE
  # The abort guards the two finite waits, not subsequent expectation formatting.
  # Release it only after both waits positively yield the same uncharged checkpoint.
  if (identical(short$value, x$s) && short$elapsed < 0.2 && admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      identical(again$value, x$s) && again$elapsed < 0.2 &&
      identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      is.list(pending) && identical(x$run$compact_pending, pending) &&
      identical(x$run$request_ids, ids) && length(fake_requests(x$fake)) == 1L &&
      nrow(x$s$usage) == 0L && length(cp_wait_entries(x$s)) == 0L && tick$fired) {
    reactor_cancel(x$guard)
    guard_released = TRUE
  }
  expect_identical(short$value, x$s)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_false(x$run$settled)
  expect_true(is.list(x$run$compact_pending))
  expect_true(is.function(x$run$compact_finish))
  expect_true(isTRUE(session_live(x$s)$compacting))
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(nrow(x$s$usage), 0L)
  expect_length(fake_requests(x$fake), 1L)
  expect_true(tick$fired)
  expect_true(guard_released)
  expect_lt(again$elapsed, 0.2)
  expect_identical(x$s$status, "running")
  expect_identical(x$run$request_ids, ids)
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(x$s$usage), 0L)
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(sum(x$events$types == "session_before_compact"), 1L)
  expect_identical(sum(x$events$types == "before_request"), 1L)
  expect_null(prompt_ctx(x$s)$input)
  cp_wait_prefix(x)
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "idle")
  expect_length(fake_requests(x$fake), 2L)
  expect_length(cp_wait_entries(x$s), 1L)
  expect_identical(nrow(x$s$usage), 2L)
  expect_equal(x$s$usage$input[[1L]], 100)
  expect_equal(x$s$usage$output[[1L]], 5)
  expect_false(x$s$usage$estimated[[1L]])
  expect_identical(sum(x$events$types == "session_compact"), 1L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  expect_identical(serialize(list(dat = x$home$dat, beta = x$home$beta), NULL), bytes)
  expect_identical(rlang::obj_address(x$home$dat), address)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("cancelling a yielded checkpoint charges unknown once and never appends a summary", {
  x = cp_wait_fixture(list(list(hang = TRUE)))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  pending = x$run$compact_pending
  gptr_cancel(x$s)
  expect_identical(x$s$status, "aborted")
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_identical(x$s$usage$stop_reason, "aborted")
  expect_true(all(is.na(unlist(x$s$usage[setdiff(usage_token_columns, "cost")],
                              use.names = FALSE))))
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(sum(x$events$types == "usage"), 1L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  expect_identical(sum(x$events$types == "session_compact"), 0L)
  gptr_cancel(x$s)
  if (is.list(pending)) pending$poll()
  expect_identical(nrow(x$s$usage), 1L)
  expect_length(cp_wait_entries(x$s), 0L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("a delayed checkpoint error falls back once without retrying the request", {
  x = cp_wait_fixture(list(fake_text("", delay = 0.3, stop = "error",
                                    usage = usage_new(input = 100, output = 5)), "Done."))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  pending = x$run$compact_pending
  ids = x$run$request_ids
  again = cp_wait_short(x)
  guard_released = FALSE
  # Guard the finite waits, then release before expectation formatting and completion.
  if (identical(short$value, x$s) && short$elapsed < 0.2 && admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      identical(again$value, x$s) && again$elapsed < 0.2 &&
      identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      is.list(pending) && identical(x$run$compact_pending, pending) &&
      identical(x$run$request_ids, ids) && length(fake_requests(x$fake)) == 1L &&
      nrow(x$s$usage) == 0L && length(cp_wait_entries(x$s)) == 0L) {
    reactor_cancel(x$guard)
    guard_released = TRUE
  }
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_lt(again$elapsed, 0.2)
  expect_true(guard_released)
  expect_identical(x$run$compact_pending, pending)
  expect_identical(x$run$request_ids, ids)
  expect_identical(x$s$status, "running")
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "idle")
  expect_length(fake_requests(x$fake), 2L)
  entries = cp_wait_entries(x$s)
  expect_length(entries, 1L)
  expect_identical(entries[[1L]]$summary, prompt_text("checkpoint_no_summary"))
  expect_identical(nrow(x$s$usage), 2L)
  expect_identical(x$s$usage$stop_reason[[1L]], "error")
  expect_equal(x$s$usage$input[[1L]], 100)
  expect_identical(sum(x$events$types == "session_compact"), 1L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("a yielded empty checkpoint retries once and preserves both known charges", {
  x = cp_wait_fixture(list(fake_text("", delay = 0.3,
                                    usage = usage_new(input = 100, output = 5)),
                          fake_text("Useful summary.", delay = 0.1,
                                    usage = usage_new(input = 120, output = 7)), "Done."))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_length(fake_requests(x$fake), 1L)
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "idle")
  expect_length(fake_requests(x$fake), 3L)
  expect_identical(nrow(x$s$usage), 3L)
  expect_equal(x$s$usage$input[1:2], c(100, 120))
  expect_equal(x$s$usage$output[1:2], c(5, 7))
  expect_length(cp_wait_entries(x$s), 1L)
  expect_identical(cp_wait_entries(x$s)[[1L]]$summary, "Useful summary.")
  expect_equal(cp_wait_entries(x$s)[[1L]]$usage$input, 220)
  expect_identical(sum(x$events$types == "before_request"), 3L)
  expect_identical(sum(x$events$types == "session_compact"), 1L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("a yielded checkpoint consumes its request budget before a retry can start", {
  x = cp_wait_fixture(list(fake_text("", delay = 0.3,
                                    usage = usage_new(input = 100, output = 5)),
                          "Must not start."), budget = list(turns = 1L))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_error(gptr_wait(x$s, timeout = 1), class = "gptr_error_budget")
  expect_identical(x$s$status, "budget")
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_length(cp_wait_entries(x$s), 1L)
  expect_identical(sum(x$events$types == "before_request"), 1L)
  expect_identical(x$run$request_ids, x$s$usage$request_id)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("an overflow checkpoint yields and resumes the same ordinary request once", {
  x = cp_wait_fixture(list(list(overflow = TRUE),
                          fake_text("Useful summary.", delay = 0.3), "Done."), should = FALSE)
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x, requests = 2L)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_true(x$run$overflow_used)
  expect_length(fake_requests(x$fake), 2L)
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(nrow(x$s$usage), 1L)
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "idle")
  expect_length(fake_requests(x$fake), 3L)
  expect_length(cp_wait_entries(x$s), 1L)
  expect_identical(cp_wait_entries(x$s)[[1L]]$details$reason, "overflow")
  expect_identical(nrow(x$s$usage), 3L)
  expect_identical(sum(x$events$types == "session_compact"), 1L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("a yielded checkpoint without metering stays unknown after durable reconstruction", {
  x = cp_wait_fixture(list(fake_text("Useful summary.", delay = 0.3), "Done."))
  original = provider_stream
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    callback = if (is.null(run)) function(msg) {
      msg$usage = NULL
      msg$route = "plan-cli"
      done(msg)
    } else done
    original(model, context, opts, emit, callback, run)
  })
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  pending = x$run$compact_pending
  ids = x$run$request_ids
  guard_released = FALSE
  # The abort guards finite yielding, then releases only an unchanged uncharged owner.
  if (identical(short$value, x$s) && short$elapsed < 0.2 && admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      is.list(pending) && identical(x$run$compact_pending, pending) &&
      identical(x$run$request_ids, ids) && is.function(x$run$compact_finish) &&
      identical(session_live(x$s)$run, x$run) && isTRUE(session_live(x$s)$compacting) &&
      length(fake_requests(x$fake)) == 1L && nrow(x$s$usage) == 0L &&
      length(cp_wait_entries(x$s)) == 0L) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  second_started = reactor_now()
  gptr_wait(x$s, timeout = 1)
  second_completed = reactor_now()
  reason = if (identical(x$run$signal$reason, "fixture-guard")) "fixture-guard" else
    if (is.null(x$run$signal$reason)) "none" else "other"
  diagnostic = paste0("guard_remaining=", x$guard_at - second_started,
                      "; second_wait_elapsed=", second_completed - second_started,
                      "; abort_reason=", reason)
  expect_true(guard_released, info = diagnostic)
  expect_identical(x$s$status, "idle", info = diagnostic)
  expect_identical(nrow(x$s$usage), 2L)
  expect_true(all(is.na(unlist(x$s$usage[1L, usage_token_columns], use.names = FALSE))))
  expect_false(x$s$usage$estimated[[1L]])
  restored = rebuild_usage(store_read(x$s$file)$entries, session_data(x$s))
  expect_identical(restored$request_id, x$s$usage$request_id)
  expect_true(all(is.na(unlist(restored[1L, usage_token_columns], use.names = FALSE))))
  expect_identical(sum(x$events$types == "usage"), 2L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("a yielded checkpoint leaves all caller state intact across both waits", {
  x = cp_wait_fixture(list(fake_text("Useful summary.", delay = 0.3), "Done."))
  snapshot = function() {
    list(env = Sys.getenv(), options = options(), cwd = getwd(),
      libraries = .libPaths(), search = search(), kind = RNGkind(),
      seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
      names = ls(envir = globalenv(), all.names = TRUE))
  }
  before = snapshot()
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  after_short = snapshot()
  pending = x$run$compact_pending
  ids = x$run$request_ids
  guard_released = FALSE
  # Guard the finite yield; release only after its caller state and owner are proved.
  if (identical(short$value, x$s) && short$elapsed < 0.2 && admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      is.list(pending) && identical(x$run$compact_pending, pending) &&
      identical(x$run$request_ids, ids) && is.function(x$run$compact_finish) &&
      identical(session_live(x$s)$run, x$run) && isTRUE(session_live(x$s)$compacting) &&
      length(fake_requests(x$fake)) == 1L && nrow(x$s$usage) == 0L &&
      length(cp_wait_entries(x$s)) == 0L &&
      all(vapply(names(before), function(name) {
        identical(before[[name]], after_short[[name]])
      }, logical(1L)))) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  second_started = reactor_now()
  gptr_wait(x$s, timeout = 1)
  second_completed = reactor_now()
  after = snapshot()
  reason = if (identical(x$run$signal$reason, "fixture-guard")) "fixture-guard" else
    if (is.null(x$run$signal$reason)) "none" else "other"
  diagnostic = paste0("guard_remaining=", x$guard_at - second_started,
                      "; second_wait_elapsed=", second_completed - second_started,
                      "; abort_reason=", reason)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_true(all(vapply(names(before), function(name) {
    identical(before[[name]], after_short[[name]])
  }, logical(1L))))
  expect_true(all(vapply(names(before), function(name) {
    identical(before[[name]], after[[name]])
  }, logical(1L))))
  expect_true(guard_released, info = diagnostic)
  expect_identical(x$s$status, "idle", info = diagnostic)
  cp_wait_finished(x)
})

test_that("a pending checkpoint keeps served R disabled until its owning run completes", {
  x = cp_wait_fixture(list(fake_text("Useful summary.", delay = 0.3), "Done."))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_identical(reactor_depth(), 0L)
  reply = mcp_dispatch_local(
    mcp_test_msg("tools/call", list(name = "r", arguments = list(code = "changed = 99"))),
    x$s)$result
  expect_true(reply$isError)
  expect_match(reply$content[[1L]]$text, "compaction", fixed = TRUE)
  expect_false(exists("changed", envir = x$home, inherits = FALSE))
  expect_length(fake_requests(x$fake), 1L)
  gptr_wait(x$s, timeout = 1)
  after = mcp_dispatch_local(
    mcp_test_msg("tools/call", list(name = "r", arguments = list(code = "after = 7"))),
    x$s)$result
  expect_false(after$isError)
  expect_identical(x$home$after, 7)
  expect_length(cp_wait_entries(x$s), 1L)
  cp_wait_finished(x)
})

test_that("malformed hook and custom results fall back once across deferred waits", {
  x = cp_wait_fixture(list(fake_text("Useful summary.", delay = 0.3), "Done."))
  seen = new.env(parent = emptyenv())
  seen$calls = 0L
  off = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
    list(result = list(summary = "Missing blocks."))
  }))
  withr::defer(off())
  off_comp = gptr_register(gptr_spec("compactor", "wait-invalid",
    should = function(session, ctx) TRUE,
    compact = function(session, ctx) {
      seen$calls = seen$calls + 1L
      seen$input = ctx$input
      list(summary = "Missing blocks.")
    }))
  withr::defer(off_comp())
  local_gptr_options(compactor = "wait-invalid")
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_identical(seen$calls, 1L)
  expect_identical(seen$input$reason, "threshold")
  expect_identical(seen$input$target$ref, "fake/fake-1")
  expect_null(prompt_ctx(x$s)$input)
  again = cp_wait_short(x)
  expect_lt(again$elapsed, 0.2)
  expect_identical(seen$calls, 1L)
  expect_identical(sum(x$events$types == "session_before_compact"), 1L)
  expect_length(fake_requests(x$fake), 1L)
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "idle")
  expect_identical(seen$calls, 1L)
  expect_length(cp_wait_entries(x$s), 1L)
  expect_identical(cp_wait_entries(x$s)[[1L]]$details$strategy, "checkpoint")
  expect_identical(cp_wait_entries(x$s)[[1L]]$summary, "Useful summary.")
  expect_length(fake_requests(x$fake), 2L)
  expect_identical(nrow(x$s$usage), 2L)
  expect_null(prompt_ctx(x$s)$input)
  cp_wait_finished(x)
})

test_that("a compaction hook cancellation remains a completed no-op at the boundary", {
  x = cp_wait_fixture(list("Done."))
  off = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
    list(cancel = TRUE)
  }))
  withr::defer(off())
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "idle")
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(sum(x$events$types == "session_before_compact"), 1L)
  expect_identical(sum(x$events$types == "before_request"), 1L)
  cp_wait_finished(x)
})

test_that("aborting before a checkpoint starts preserves the zero-charge boundary", {
  x = cp_wait_fixture(list("Must not start."))
  off = gptr_register(gptr_hook("before_request", function(event, ctx) {
    ctx$abort("fixture-before-request")
    NULL
  }))
  withr::defer(off())
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "aborted")
  expect_length(fake_requests(x$fake), 0L)
  expect_identical(nrow(x$s$usage), 0L)
  expect_length(x$run$request_ids, 0L)
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(sum(x$events$types == "before_request"), 1L)
  expect_identical(sum(x$events$types == "usage"), 0L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  cp_wait_finished(x)
})

test_that("a deferred checkpoint accounting failure cannot start an ordinary request", {
  x = cp_wait_fixture(list(fake_text("Useful summary.", delay = 0.3), "Must not start."))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  original = gptr_condition("Synthetic deferred accounting failure.", "internal", "error")
  seen = new.env(parent = emptyenv())
  seen$calls = 0L
  local_mocked_bindings(compact_charge = function(...) {
    seen$calls = seen$calls + 1L
    stop(original)
  })
  expect_error(gptr_wait(x$s, timeout = 1), class = "gptr_error_internal")
  expect_identical(x$s$status, "error")
  expect_identical(x$run$condition, original)
  expect_identical(x$run$accounting_error, original)
  expect_identical(session_data(x$s)$condition, original)
  expect_identical(seen$calls, 1L)
  expect_length(fake_requests(x$fake), 1L)
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(nrow(x$s$usage), 0L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  expect_identical(sum(x$events$types == "session_compact"), 0L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("manual compaction on an active session completes without an orphan continuation", {
  x = cp_wait_fixture(list(fake_text("Ordinary answer.", delay = 0.5,
                                    usage = usage_new(input = 30, output = 3)),
                          fake_text("Manual summary.", delay = 0.1,
                                    usage = usage_new(input = 100, output = 5))), should = FALSE)
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  ordinary = list(status = x$s$status, busy = x$run$busy,
                  request_closed = x$run$request_closed,
                  requests = length(fake_requests(x$fake)), usage = nrow(x$s$usage))
  ordinary_id = x$run$request_id
  manual_started = reactor_now()
  # Keep the abort active through admission and manual work, before expectation formatting.
  text = cmd_compact("", session_live(x$s)$ctx)
  manual_completed = reactor_now()
  entries = cp_wait_entries(x$s)
  guard_released = FALSE
  if (identical(short$value, x$s) && short$elapsed < 0.2 && admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      identical(ordinary$status, "running") && isTRUE(ordinary$busy) &&
      identical(ordinary$request_closed, FALSE) && ordinary$requests == 1L &&
      ordinary$usage == 0L && identical(text, "Conversation compacted.") &&
      manual_completed < x$guard_at && length(entries) == 1L &&
      identical(entries[[1L]]$details$reason, "manual") &&
      identical(entries[[1L]]$summary, "Manual summary.") &&
      length(fake_requests(x$fake)) == 2L && nrow(x$s$usage) == 1L &&
      identical(x$s$usage$input[[1L]], 100) && identical(x$s$usage$output[[1L]], 5) &&
      !identical(x$s$usage$request_id[[1L]], ordinary_id) && isTRUE(x$run$busy) &&
      !isTRUE(x$run$settled) && identical(x$run$request_id, ordinary_id) &&
      identical(x$s$status, "running") && identical(x$run$request_closed, FALSE) &&
      !isTRUE(x$run$signal$aborted) &&
      is.null(x$run$compact_pending) && is.null(x$run$compact_finish) &&
      is.null(x$run$compact_defer) && !isTRUE(session_live(x$s)$compacting)) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  reason = if (identical(x$run$signal$reason, "fixture-guard")) "fixture-guard" else
    if (is.null(x$run$signal$reason)) "none" else "other"
  diagnostic = paste0("guard_remaining=", x$guard_at - manual_started,
                      "; manual_elapsed=", manual_completed - manual_started,
                      "; abort_reason=", reason)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(ordinary$status, "running")
  expect_true(ordinary$busy)
  expect_false(ordinary$request_closed)
  expect_identical(ordinary$requests, 1L)
  expect_identical(ordinary$usage, 0L)
  expect_identical(text, "Conversation compacted.", info = diagnostic)
  expect_true(guard_released, info = diagnostic)
  expect_length(cp_wait_entries(x$s), 1L)
  expect_identical(cp_wait_entries(x$s)[[1L]]$details$reason, "manual")
  expect_identical(cp_wait_entries(x$s)[[1L]]$summary, "Manual summary.")
  expect_length(fake_requests(x$fake), 2L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_equal(x$s$usage$input[[1L]], 100)
  expect_equal(x$s$usage$output[[1L]], 5)
  expect_false(identical(x$s$usage$request_id[[1L]], ordinary_id))
  expect_true(x$run$busy)
  expect_false(x$run$settled)
  expect_null(x$run$compact_pending)
  expect_null(x$run$compact_finish)
  expect_null(x$run$compact_defer)
  expect_false(isTRUE(session_live(x$s)$compacting))
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "idle")
  expect_identical(x$s$text, "Ordinary answer.")
  expect_length(cp_wait_entries(x$s), 1L)
  expect_length(fake_requests(x$fake), 2L)
  expect_identical(nrow(x$s$usage), 2L)
  expect_equal(x$s$usage$input, c(100, 30))
  expect_equal(x$s$usage$output, c(5, 3))
  expect_identical(x$s$usage$request_id[[2L]], ordinary_id)
  expect_identical(sum(x$events$types == "session_compact"), 1L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("a manual command cannot replace a yielded automatic checkpoint", {
  x = cp_wait_fixture(list(fake_text("Useful summary.", delay = 0.3,
                                    usage = usage_new(input = 100, output = 5)), "Done."))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_true(isTRUE(session_live(x$s)$compacting))
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  expect_true(is.list(pending))
  expect_true(is.function(finish))
  expect_length(ids, 1L)
  text = cmd_compact("", session_live(x$s)$ctx)
  expect_identical(text, "Compaction is already in progress.")
  direct = compact_run(x$s, "manual")
  expect_identical(direct, x$s)
  expect_identical(x$run$compact_pending, pending)
  expect_identical(x$run$compact_finish, finish)
  expect_identical(x$run$request_ids, ids)
  expect_true(isTRUE(session_live(x$s)$compacting))
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(x$s$usage), 0L)
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(sum(x$events$types == "session_before_compact"), 1L)
  expect_identical(sum(x$events$types == "before_request"), 1L)
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "idle")
  expect_length(fake_requests(x$fake), 2L)
  expect_length(cp_wait_entries(x$s), 1L)
  expect_identical(cp_wait_entries(x$s)[[1L]]$details$reason, "threshold")
  expect_identical(nrow(x$s$usage), 2L)
  expect_identical(x$s$usage$request_id[[1L]], ids[[1L]])
  expect_equal(x$s$usage$input[[1L]], 100)
  expect_equal(x$s$usage$output[[1L]], 5)
  expect_identical(sum(x$events$types == "session_compact"), 1L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

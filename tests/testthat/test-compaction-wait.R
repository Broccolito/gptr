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

# Offline scheduling uses a controlled clock; timer and task callbacks remain real.
# Every timed finite wait runs under it, so a stalled synchronous step cannot fail its bound.
cp_wait_clock = function(.env = parent.frame()) {
  r = reactor_get()
  # a task an earlier test left is named by the start of its body
  left = vapply(ls(r$tasks), function(id) {
    strtrim(paste(trimws(deparse(body(r$tasks[[id]]$fn))), collapse = " "), 70L)
  }, "")
  if (length(left)) stop("an earlier test left reactor tasks: ", paste(left, collapse = "; "))
  stopifnot(!length(ls(r$transfers)), !length(ls(r$procs)), !length(ls(r$stdin)),
            !length(ls(r$runs)), !length(ls(r$timers)), !length(r$queue), !length(r$fifo),
            identical(r$depth, 0L))
  clock = new.env(parent = emptyenv())
  clock$now = reactor_now()
  original_io = reactor_io
  local_mocked_bindings(reactor_now = function() clock$now,
    reactor_io = function(r, allow_runs, slice_ms, t_end) {
      clock$now = clock$now + reactor_wait_ms(r, allow_runs, slice_ms, t_end) / 1000
      original_io(r, allow_runs, slice_ms = 0, t_end = clock$now)
    }, .env = .env)
  clock
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
  cp_wait_clock()
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
  cp_wait_clock()
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
  clock = cp_wait_clock()
  injected = new.env(parent = emptyenv())
  injected$n = 0L
  x = cp_wait_fixture(function(request) {
    if (identical(request$n, 1L)) {
      injected$n = injected$n + 1L
      clock$now = clock$now + 0.55
      return(fake_text("", delay = 0.3, stop = "error",
                       usage = usage_new(input = 100, output = 5)))
    }
    "Done."
  })
  # Admit cooperative request preparation before timing the in-flight waits.
  startup_started = reactor_now()
  reactor_pump(until = function() {
    length(fake_requests(x$fake)) >= 1L || isTRUE(x$run$settled)
  }, timeout = 0.8)
  startup_completed = reactor_now()
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  admission_ready = startup_completed < x$guard_at &&
    identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
    !isTRUE(x$run$signal$aborted) && identical(session_live(x$s)$run, x$run) &&
    isTRUE(session_live(x$s)$compacting) && is.list(pending) && is.function(finish) &&
    length(ids) == 1L && length(fake_requests(x$fake)) == 1L && nrow(x$s$usage) == 0L &&
    length(cp_wait_entries(x$s)) == 0L && identical(injected$n, 1L)
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  again = cp_wait_short(x)
  waits_completed = reactor_now()
  guard_released = FALSE
  # Guard the finite waits, then release before expectation formatting and completion.
  if (admission_ready && identical(short$value, x$s) && short$elapsed < 0.2 && admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      identical(again$value, x$s) && again$elapsed < 0.2 &&
      identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted) && isTRUE(session_live(x$s)$compacting) &&
      is.list(pending) && identical(x$run$compact_pending, pending) &&
      identical(x$run$compact_finish, finish) &&
      identical(x$run$request_ids, ids) && length(fake_requests(x$fake)) == 1L &&
      nrow(x$s$usage) == 0L && length(cp_wait_entries(x$s)) == 0L &&
      waits_completed < x$guard_at) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  expect_identical(injected$n, 1L)
  expect_true(admission_ready)
  expect_lt(startup_completed - startup_started, 0.8)
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
  expect_identical(injected$n, 1L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("a yielded empty checkpoint retries once and preserves both known charges", {
  cp_wait_clock()
  x = cp_wait_fixture(list(fake_text("", delay = 0.3,
                                    usage = usage_new(input = 100, output = 5)),
                          fake_text("Useful summary.", delay = 0.1,
                                    usage = usage_new(input = 120, output = 7)), "Done."))
  # Cold request preparation is cooperative R work, not part of the in-flight wait oracle.
  startup_started = reactor_now()
  reactor_pump(until = function() {
    length(fake_requests(x$fake)) >= 1L || isTRUE(x$run$settled)
  }, timeout = 0.8)
  startup_completed = reactor_now()
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  admission_ready = startup_completed < x$guard_at &&
    identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
    !isTRUE(x$run$signal$aborted) && identical(session_live(x$s)$run, x$run) &&
    isTRUE(session_live(x$s)$compacting) && is.list(pending) && is.function(finish) &&
    length(ids) == 1L && length(fake_requests(x$fake)) == 1L && nrow(x$s$usage) == 0L &&
    length(cp_wait_entries(x$s)) == 0L
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  waits_completed = reactor_now()
  guard_released = FALSE
  # Bound admission, then release its abort before assertion formatting.
  if (admission_ready && identical(short$value, x$s) && short$elapsed < 0.2 &&
      admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted) && isTRUE(session_live(x$s)$compacting) &&
      is.list(pending) && is.function(finish) && length(ids) == 1L &&
      identical(x$run$compact_pending, pending) && identical(x$run$compact_finish, finish) &&
      identical(x$run$request_ids, ids) && length(fake_requests(x$fake)) == 1L &&
      nrow(x$s$usage) == 0L && length(cp_wait_entries(x$s)) == 0L &&
      waits_completed < x$guard_at) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  admission_reason = if (identical(x$run$signal$reason, "fixture-guard")) "fixture-guard" else
    if (is.null(x$run$signal$reason)) "none" else "other"
  admission_diagnostic = paste0("startup_elapsed=", startup_completed - startup_started,
                                "; finite_elapsed=", short$elapsed,
                                "; guard_remaining=", x$guard_at - waits_completed,
                                "; abort_reason=", admission_reason)
  expect_true(admission_ready, info = admission_diagnostic)
  expect_lt(startup_completed - startup_started, 0.8)
  expect_true(guard_released, info = admission_diagnostic)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_length(fake_requests(x$fake), 1L)
  # Completion keeps its own unchanged 0.8 s abort, excluding assertion formatting.
  completion_started = reactor_now()
  completion_guard_at = completion_started + 0.8
  completion_guard = reactor_timer(completion_guard_at,
                                   function() run_abort(x$run, "fixture-completion-guard"))
  withr::defer(reactor_cancel(completion_guard))
  gptr_wait(x$s, timeout = 1)
  completion_completed = reactor_now()
  completion_guard_released = FALSE
  if (guard_released && identical(x$s$status, "idle") && isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted)) {
    completion_guard_released = identical(reactor_cancel(completion_guard), 1L)
  }
  completion_reason = if (identical(x$run$signal$reason, "fixture-completion-guard"))
    "fixture-completion-guard" else if (identical(x$run$signal$reason, "fixture-guard"))
    "fixture-guard" else if (is.null(x$run$signal$reason)) "none" else "other"
  completion_diagnostic = paste0("completion_elapsed=", completion_completed - completion_started,
                                 "; guard_remaining=", completion_guard_at - completion_completed,
                                 "; abort_reason=", completion_reason)
  cat(completion_diagnostic, "\n")
  expect_identical(x$s$status, "idle")
  expect_true(completion_guard_released, info = completion_diagnostic)
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
  cp_wait_clock()
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
  cp_wait_clock()
  x = cp_wait_fixture(list(list(overflow = TRUE),
                          fake_text("Useful summary.", delay = 0.3), "Done."), should = FALSE)
  # Admit the overflow and its checkpoint before measuring the truly in-flight finite wait.
  startup_started = reactor_now()
  reactor_pump(until = function() {
    length(fake_requests(x$fake)) >= 2L || isTRUE(x$run$settled)
  }, timeout = 0.8)
  startup_completed = reactor_now()
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  admission_ready = startup_completed < x$guard_at &&
    identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
    !isTRUE(x$run$signal$aborted) && identical(session_live(x$s)$run, x$run) &&
    isTRUE(session_live(x$s)$compacting) && isTRUE(x$run$overflow_used) &&
    is.list(pending) && is.function(finish) && length(ids) == 2L &&
    length(fake_requests(x$fake)) == 2L && nrow(x$s$usage) == 1L &&
    length(cp_wait_entries(x$s)) == 0L
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x, requests = 2L)
  waits_completed = reactor_now()
  guard_released = FALSE
  if (admission_ready && identical(short$value, x$s) && short$elapsed < 0.2 &&
      admitted$started && all(admitted$elapsed < 0.2) && all(admitted$values) &&
      admitted$retained && identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted) && isTRUE(session_live(x$s)$compacting) &&
      identical(x$run$compact_pending, pending) && identical(x$run$compact_finish, finish) &&
      identical(x$run$request_ids, ids) && length(fake_requests(x$fake)) == 2L &&
      nrow(x$s$usage) == 1L && length(cp_wait_entries(x$s)) == 0L &&
      waits_completed < x$guard_at) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  reason = x$run$signal$reason %||% "none"
  diagnostic = paste0("startup_elapsed=", startup_completed - startup_started,
                      "; finite_elapsed=", short$elapsed,
                      "; guard_remaining=", x$guard_at - waits_completed,
                      "; abort_reason=", reason)
  expect_true(admission_ready, info = diagnostic)
  expect_lt(startup_completed - startup_started, 0.8)
  expect_true(guard_released, info = diagnostic)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_true(x$run$overflow_used)
  expect_length(fake_requests(x$fake), 2L)
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(nrow(x$s$usage), 1L)
  # Completion has its own original-sized guard; expectations consume neither phase's budget.
  completion_started = reactor_now()
  completion_guard_at = completion_started + 0.8
  completion_guard = reactor_timer(completion_guard_at,
                                   function() run_abort(x$run, "fixture-completion-guard"))
  withr::defer(reactor_cancel(completion_guard))
  gptr_wait(x$s, timeout = 1)
  completion_completed = reactor_now()
  completion_guard_released = FALSE
  if (guard_released && identical(x$s$status, "idle") && isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted)) {
    completion_guard_released = identical(reactor_cancel(completion_guard), 1L)
  }
  completion_diagnostic = paste0("completion_elapsed=", completion_completed - completion_started,
                                 "; guard_remaining=", completion_guard_at - completion_completed,
                                 "; abort_reason=", x$run$signal$reason %||% "none")
  cat(completion_diagnostic, "\n")
  expect_identical(x$s$status, "idle", info = completion_diagnostic)
  expect_true(completion_guard_released, info = completion_diagnostic)
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
  cp_wait_clock()
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
  cp_wait_clock()
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
  cp_wait_clock()
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
  cp_wait_clock()
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
  # Measure fallback setup separately from finite waits on its pending checkpoint.
  startup_started = reactor_now()
  reactor_pump(until = function() {
    length(fake_requests(x$fake)) >= 1L || isTRUE(x$run$settled)
  }, timeout = 0.8)
  startup_completed = reactor_now()
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  retained = function() {
    identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted) && isTRUE(session_live(x$s)$compacting) &&
      is.list(pending) && is.function(finish) && length(ids) == 1L &&
      identical(x$run$compact_pending, pending) && identical(x$run$compact_finish, finish) &&
      identical(x$run$request_ids, ids) && length(fake_requests(x$fake)) == 1L &&
      nrow(x$s$usage) == 0L && length(cp_wait_entries(x$s)) == 0L &&
      identical(seen$calls, 1L) && identical(seen$input$reason, "threshold") &&
      identical(seen$input$target$ref, "fake/fake-1") && is.null(prompt_ctx(x$s)$input) &&
      identical(sum(x$events$types == "session_before_compact"), 1L) &&
      identical(sum(x$events$types == "before_request"), 1L)
  }
  admission_ready = retained() && startup_completed < x$guard_at
  admission_guard_released = FALSE
  if (admission_ready) {
    admission_guard_released = identical(reactor_cancel(x$guard), 1L)
    if (admission_guard_released) {
      x$guard_at = reactor_now() + 0.8
      x$guard = reactor_timer(x$guard_at, function() run_abort(x$run, "fixture-guard"))
      withr::defer(reactor_cancel(x$guard))
    }
  }
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  again = cp_wait_short(x)
  waits_completed = reactor_now()
  guard_released = FALSE
  if (admission_ready && admission_guard_released && identical(short$value, x$s) &&
      short$elapsed < 0.2 && admitted$started && all(admitted$elapsed < 0.2) &&
      all(admitted$values) && admitted$retained && identical(again$value, x$s) &&
      again$elapsed < 0.2 && retained() && waits_completed < x$guard_at) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  reason = if (identical(x$run$signal$reason, "fixture-guard")) "fixture-guard" else
    if (is.null(x$run$signal$reason)) "none" else "other"
  diagnostic = paste0("startup_elapsed=", startup_completed - startup_started,
                      "; finite_elapsed=", short$elapsed, ",", again$elapsed,
                      "; guard_remaining=", x$guard_at - waits_completed,
                      "; abort_reason=", reason)
  expect_true(admission_ready, info = diagnostic)
  expect_lt(startup_completed - startup_started, 0.8)
  expect_true(admission_guard_released, info = diagnostic)
  expect_true(guard_released, info = diagnostic)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_identical(seen$calls, 1L)
  expect_identical(seen$input$reason, "threshold")
  expect_identical(seen$input$target$ref, "fake/fake-1")
  expect_null(prompt_ctx(x$s)$input)
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
  cp_wait_clock()
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
  cp_wait_clock()
  x = cp_wait_fixture(list(fake_text("Ordinary answer.", delay = 0.5,
                                    usage = usage_new(input = 30, output = 3)),
                          fake_text("Manual summary.", delay = 0.1,
                                    usage = usage_new(input = 100, output = 5))), should = FALSE)
  # This title starts with an active request; measure its in-flight finite wait separately.
  startup_started = reactor_now()
  reactor_pump(until = function() {
    length(fake_requests(x$fake)) >= 1L || isTRUE(x$run$settled)
  }, timeout = 0.8)
  startup_completed = reactor_now()
  admission_ready = length(fake_requests(x$fake)) == 1L && isTRUE(x$run$busy) &&
    !isTRUE(x$run$settled) && identical(x$s$status, "running") &&
    identical(x$run$request_closed, FALSE) && !isTRUE(x$run$signal$aborted) &&
    nrow(x$s$usage) == 0L && length(cp_wait_entries(x$s)) == 0L &&
    is.null(x$run$compact_pending) && startup_completed < x$guard_at
  admission_guard_released = FALSE
  if (admission_ready) {
    admission_guard_released = identical(reactor_cancel(x$guard), 1L)
    if (admission_guard_released) {
      # Admission retains its 0.8-second guard; the timed wait and manual work get 2 seconds
      # (the manual compaction alone took 0.8 s on a slow hosted Windows runner).
      x$guard_at = reactor_now() + 2
      x$guard = reactor_timer(x$guard_at, function() run_abort(x$run, "fixture-guard"))
      withr::defer(reactor_cancel(x$guard))
    }
  }
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
  compacted = "^Conversation compacted: \\S+ to \\S+ tokens\\.$"
  entries = cp_wait_entries(x$s)
  guard_released = FALSE
  if (admission_ready && admission_guard_released &&
      identical(short$value, x$s) && short$elapsed < 0.2 && admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      identical(ordinary$status, "running") && isTRUE(ordinary$busy) &&
      identical(ordinary$request_closed, FALSE) && ordinary$requests == 1L &&
      ordinary$usage == 0L && isTRUE(grepl(compacted, text)) &&
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
  diagnostic = paste0("startup_elapsed=", startup_completed - startup_started,
                      "; admission_ready=", admission_ready,
                      "; guard_remaining=", x$guard_at - manual_started,
                      "; manual_elapsed=", manual_completed - manual_started,
                      "; abort_reason=", reason)
  expect_true(admission_ready, info = diagnostic)
  expect_lt(startup_completed - startup_started, 0.8)
  expect_true(admission_guard_released, info = diagnostic)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(ordinary$status, "running")
  expect_true(ordinary$busy)
  expect_false(ordinary$request_closed)
  expect_identical(ordinary$requests, 1L)
  expect_identical(ordinary$usage, 0L)
  expect_match(text, compacted, info = diagnostic)
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
  cp_wait_clock()
  x = cp_wait_fixture(list(fake_text("Useful summary.", delay = 0.3,
                                    usage = usage_new(input = 100, output = 5)), "Done."))
  short = cp_wait_short(x)
  admitted = cp_wait_admit(x)
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  retained = function() {
    identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted) && isTRUE(session_live(x$s)$compacting) &&
      is.list(pending) && is.function(finish) && length(ids) == 1L &&
      identical(x$run$compact_pending, pending) && identical(x$run$compact_finish, finish) &&
      identical(x$run$request_ids, ids) && length(fake_requests(x$fake)) == 1L &&
      nrow(x$s$usage) == 0L && length(cp_wait_entries(x$s)) == 0L &&
      identical(sum(x$events$types == "session_before_compact"), 1L) &&
      identical(sum(x$events$types == "before_request"), 1L)
  }
  initial_retained = retained()
  manual_started = reactor_now()
  text = cmd_compact("", session_live(x$s)$ctx)
  command_retained = retained()
  direct = compact_run(x$s, "manual")
  direct_retained = retained()
  manual_completed = reactor_now()
  guard_released = FALSE
  # Guard the finite waits and both manual calls, not later expectation formatting.
  # Release only after each call preserves the same uncharged automatic checkpoint.
  if (identical(short$value, x$s) && short$elapsed < 0.2 && admitted$started &&
      all(admitted$elapsed < 0.2) && all(admitted$values) && admitted$retained &&
      initial_retained && command_retained && direct_retained &&
      identical(text, "Compaction is already in progress.") && identical(direct, x$s) &&
      manual_completed < x$guard_at) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  reason = if (identical(x$run$signal$reason, "fixture-guard")) "fixture-guard" else
    if (is.null(x$run$signal$reason)) "none" else "other"
  diagnostic = paste0("guard_remaining=", x$guard_at - manual_started,
                      "; manual_elapsed=", manual_completed - manual_started,
                      "; abort_reason=", reason)
  expect_identical(short$value, x$s)
  expect_lt(short$elapsed, 0.2)
  cp_wait_admitted(admitted)
  expect_identical(x$s$status, "running")
  expect_true(isTRUE(session_live(x$s)$compacting))
  expect_true(is.list(pending))
  expect_true(is.function(finish))
  expect_length(ids, 1L)
  expect_true(initial_retained, info = diagnostic)
  expect_true(command_retained, info = diagnostic)
  expect_true(direct_retained, info = diagnostic)
  expect_identical(text, "Compaction is already in progress.", info = diagnostic)
  expect_identical(direct, x$s)
  expect_true(guard_released, info = diagnostic)
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
  reason = if (identical(x$run$signal$reason, "fixture-guard")) "fixture-guard" else
    if (is.null(x$run$signal$reason)) "none" else "other"
  expect_identical(x$s$status, "idle", info = paste0("abort_reason=", reason))
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

test_that("an admitted stuck checkpoint still aborts under its independent completion guard", {
  cp_wait_clock()
  x = cp_wait_fixture(list(fake_text("Must not finish.", hang = TRUE)))
  startup_started = reactor_now()
  reactor_pump(until = function() {
    length(fake_requests(x$fake)) >= 1L || isTRUE(x$run$settled)
  }, timeout = 0.8)
  startup_completed = reactor_now()
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  admission_ready = startup_completed < x$guard_at &&
    identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
    !isTRUE(x$run$signal$aborted) && identical(session_live(x$s)$run, x$run) &&
    isTRUE(session_live(x$s)$compacting) && is.list(pending) && is.function(finish) &&
    length(ids) == 1L && length(fake_requests(x$fake)) == 1L && nrow(x$s$usage) == 0L &&
    length(cp_wait_entries(x$s)) == 0L
  short = cp_wait_short(x)
  guard_released = FALSE
  if (admission_ready && identical(short$value, x$s) && short$elapsed < 0.2 &&
      identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted) && identical(x$run$compact_pending, pending) &&
      identical(x$run$compact_finish, finish) && identical(x$run$request_ids, ids) &&
      length(fake_requests(x$fake)) == 1L && nrow(x$s$usage) == 0L &&
      length(cp_wait_entries(x$s)) == 0L && reactor_now() < x$guard_at) {
    guard_released = identical(reactor_cancel(x$guard), 1L)
  }
  expect_true(admission_ready)
  expect_lt(startup_completed - startup_started, 0.8)
  expect_true(guard_released)
  expect_identical(short$value, x$s)
  expect_lt(short$elapsed, 0.2)
  completion_guard = reactor_timer(reactor_now() + 0.8,
                                   function() run_abort(x$run, "fixture-completion-guard"))
  withr::defer(reactor_cancel(completion_guard))
  gptr_wait(x$s, timeout = 1)
  expect_identical(x$s$status, "aborted")
  expect_identical(x$run$signal$reason, "fixture-completion-guard")
  expect_length(fake_requests(x$fake), 1L)
  expect_length(cp_wait_entries(x$s), 0L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_true(all(is.na(unlist(x$s$usage[1L, setdiff(usage_token_columns, "cost")],
                              use.names = FALSE))))
  expect_identical(x$s$usage$cost, 0)
  expect_identical(x$s$usage$stop_reason, "aborted")
  expect_identical(x$run$request_ids, x$s$usage$request_id)
  expect_identical(sum(x$events$types == "usage"), 1L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  restored = rebuild_usage(store_read(x$s$file)$entries, session_data(x$s))
  expect_identical(restored$request_id, x$s$usage$request_id)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("the offline overflow completion guard aborts at its unchanged deadline", {
  clock = cp_wait_clock()
  x = cp_wait_fixture(list(list(overflow = TRUE), list(hang = TRUE)), should = FALSE)
  reactor_pump(until = function() length(fake_requests(x$fake)) >= 2L || x$run$settled,
               timeout = 0.8)
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  retained = function() {
    identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted) && identical(session_live(x$s)$run, x$run) &&
      isTRUE(session_live(x$s)$compacting) && isTRUE(x$run$overflow_used) &&
      is.list(pending) && is.function(finish) && length(ids) == 2L &&
      identical(x$run$compact_pending, pending) && identical(x$run$compact_finish, finish) &&
      identical(x$run$request_ids, ids) && length(fake_requests(x$fake)) == 2L &&
      nrow(x$s$usage) == 1L && length(cp_wait_entries(x$s)) == 0L
  }
  expect_true(retained())
  guard_released = retained() && identical(reactor_cancel(x$guard), 1L)
  expect_true(guard_released)
  started = reactor_now()
  guard = reactor_timer(started + 0.8,
                        function() run_abort(x$run, "fixture-completion-guard"))
  withr::defer(reactor_cancel(guard))
  gptr_wait(x$s, timeout = 0.79)
  expect_true(retained())
  expect_identical(x$run$compact_pending, pending)
  expect_identical(x$run$compact_finish, finish)
  expect_identical(x$run$request_ids, ids)
  gptr_wait(x$s, timeout = 0.02)
  expect_identical(x$s$status, "aborted")
  expect_identical(x$run$signal$reason, "fixture-completion-guard")
  expect_equal(clock$now - started, 0.8, tolerance = 1e-9)
  expect_length(fake_requests(x$fake), 2L)
  expect_identical(nrow(x$s$usage), 2L)
  expect_identical(x$s$usage$stop_reason[[2L]], "aborted")
  expect_length(cp_wait_entries(x$s), 0L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

test_that("the offline empty checkpoint completion guard aborts at its unchanged deadline", {
  clock = cp_wait_clock()
  x = cp_wait_fixture(list(list(hang = TRUE)))
  reactor_pump(until = function() length(fake_requests(x$fake)) >= 1L || x$run$settled,
               timeout = 0.8)
  pending = x$run$compact_pending
  finish = x$run$compact_finish
  ids = x$run$request_ids
  retained = function() {
    identical(x$s$status, "running") && !isTRUE(x$run$settled) &&
      !isTRUE(x$run$signal$aborted) && identical(session_live(x$s)$run, x$run) &&
      isTRUE(session_live(x$s)$compacting) && is.list(pending) && is.function(finish) &&
      length(ids) == 1L && identical(x$run$compact_pending, pending) &&
      identical(x$run$compact_finish, finish) && identical(x$run$request_ids, ids) &&
      length(fake_requests(x$fake)) == 1L && nrow(x$s$usage) == 0L &&
      length(cp_wait_entries(x$s)) == 0L
  }
  expect_true(retained())
  guard_released = retained() && identical(reactor_cancel(x$guard), 1L)
  expect_true(guard_released)
  started = reactor_now()
  guard = reactor_timer(started + 0.8,
                        function() run_abort(x$run, "fixture-completion-guard"))
  withr::defer(reactor_cancel(guard))
  gptr_wait(x$s, timeout = 0.79)
  expect_true(retained())
  expect_identical(x$run$compact_pending, pending)
  expect_identical(x$run$compact_finish, finish)
  expect_identical(x$run$request_ids, ids)
  gptr_wait(x$s, timeout = 0.02)
  expect_identical(x$s$status, "aborted")
  expect_identical(x$run$signal$reason, "fixture-completion-guard")
  expect_equal(clock$now - started, 0.8, tolerance = 1e-9)
  expect_identical(reactor_cancel(guard), 0L)
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_identical(x$s$usage$stop_reason, "aborted")
  expect_identical(x$run$request_ids, x$s$usage$request_id)
  expect_identical(sum(x$events$types == "usage"), 1L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  expect_length(cp_wait_entries(x$s), 0L)
  gptr_cancel(x$s)
  expect_identical(nrow(x$s$usage), 1L)
  expect_identical(sum(x$events$types == "agent_end"), 1L)
  cp_wait_prefix(x)
  cp_wait_finished(x)
})

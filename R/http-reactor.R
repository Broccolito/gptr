# The process reactor (P04; contract 8.2, IC-57, IC-60; architecture 6.1 and 2.3).
#
# One reactor per R process: a curl multi pool, the child-pipe watchers, timers, tasks, the
# tool FIFO, admission (global `gptr.max_active` plus the per-provider limiter of
# http-retry.R) and strong references to active runs only (INFRA-15). reactor_pump() is the
# only blocking wait in gptr. The wait primitive is report 15's (sections 2.2-2.4, 4.2, 5.9,
# `p10_mixed.R`): one processx::poll() over processx::curl_fds(curl::multi_fdset(pool)) and
# the live pipes, then curl::multi_run(timeout = 0). The curl multi interface also survives a
# resumed interrupt in every phase of a request (report 02 section 4.3).
#
# Re-entrancy (IC-57): the reactor counts its pump depth and records which run's FIFO tool is
# executing. A nested pump (a sub-agent, System 1 or MCP call made inside an `r` evaluation)
# runs FIFO tools only of the runs named in its `allow_runs` (default: none whenever another
# pump is on the stack), and later::run_now(0) runs only at depth 1 or when `allow_runs` holds
# a run marked with reactor_served() (a CLI child served by gptr's MCP server).

#' The process reactor, created on first use
#' @return the `gptr_reactor` environment
#' @noRd
reactor_get = function() {
  r = get0("reactor", envir = the, inherits = FALSE)
  if (!is.null(r)) return(r)
  r = new.env(parent = emptyenv())
  r$pool = curl::new_pool(total_con = 100L, host_con = 100L, multiplex = TRUE)
  r$seq = 0L
  r$transfers = new.env(parent = emptyenv())
  r$queue = character()
  r$procs = new.env(parent = emptyenv())
  r$stdin = new.env(parent = emptyenv())
  r$timers = new.env(parent = emptyenv())
  r$tasks = new.env(parent = emptyenv())
  r$fifo = list()
  r$runs = new.env(parent = emptyenv())
  r$tool_stack = character()
  r$depth = 0L
  r$allow_stack = list()
  r$served = character()
  r$limits = new.env(parent = emptyenv())
  class(r) = "gptr_reactor"
  assign("reactor", r, envir = the)
  r
}

#' Monotonic seconds (contract 1.2)
#' @noRd
reactor_now = function() as.numeric(proc.time()[["elapsed"]])

#' The pump depth: 0 when no reactor_pump() is on the stack
#' @noRd
reactor_depth = function() {
  r = get0("reactor", envir = the, inherits = FALSE)
  if (is.null(r)) 0L else r$depth
}

#' The run whose FIFO tool is executing innermost on this call stack, or NULL
#'
#' P06 may build run_current() on it (IC-57).
#' @noRd
reactor_tool_run = function() {
  r = get0("reactor", envir = the, inherits = FALSE)
  if (is.null(r) || !length(r$tool_stack)) return(NULL)
  r$tool_stack[length(r$tool_stack)]
}

#' The runs a server answering inside the current pump may serve (IC-57)
#'
#' NULL (every run) outside any pump and in the outermost pump; inside a nested pump, that
#' pump's `allow_runs`. P18's MCP handler, which runs from later::run_now(0) in a nested pump
#' only when that pump waits for a served CLI child, answers a request whose token is bound to
#' a run outside this set with the retryable JSON-RPC error -32002.
#' @return NULL or chr
#' @noRd
reactor_allow_runs = function() {
  r = get0("reactor", envir = the, inherits = FALSE)
  if (is.null(r) || r$depth <= 1L || !length(r$allow_stack)) return(NULL)
  r$allow_stack[[length(r$allow_stack)]]
}

#' The next id, `t<integer>` (IC-20)
#' @noRd
reactor_id = function(r) {
  r$seq = r$seq + 1L
  paste0("t", r$seq)
}

#' Ids of a reactor table in creation order
#' @noRd
reactor_ids = function(e) {
  ids = ls(e, sorted = FALSE)
  ids[order(as.integer(substring(ids, 2L)))]
}

#' The id of a run given as a `gptr_run` environment, a list with `id`, or a string
#' @noRd
reactor_run_id = function(run) {
  if (is.null(run)) return(NA_character_)
  if (is.character(run)) return(run[1L])
  id = if (is.environment(run)) get0("id", envir = run, inherits = FALSE) else run[["id"]]
  if (is.null(id)) NA_character_ else as.character(id)[1L]
}

#' The session id of a run (`gptr_run` field `session`), or NULL
#' @noRd
reactor_run_session = function(run) {
  if (is.environment(run)) return(get0("session", envir = run, inherits = FALSE))
  if (is.list(run)) return(run[["session"]])
  NULL
}

#' Call a callback; an error becomes a registry diagnostic and is returned, never signalled
#'
#' Interrupts are not caught: they propagate out of the pump to the caller's policy.
#' @noRd
reactor_call = function(what, fn, ...) {
  if (is.null(fn)) return(invisible(NULL))
  tryCatch(fn(...), error = function(e) {
    registry_diagnostic("reactor", what, "error", conditionMessage(e))
    e
  })
}

#' Mark a run as waiting for a CLI child served by gptr's MCP server (IC-57)
#'
#' A nested pump whose `allow_runs` holds such a run still calls later::run_now(0), so the
#' in-session MCP server keeps answering that child. P18/P20 set and clear the mark;
#' reactor_run_remove() clears it at settlement.
#' @return invisible(chr) the marked run ids
#' @noRd
reactor_served = function(run, served = TRUE) {
  r = reactor_get()
  id = reactor_run_id(run)
  r$served = if (isTRUE(served)) union(r$served, id) else setdiff(r$served, id)
  invisible(r$served)
}

#' Register a timer: `fn()` runs once when `reactor_now() >= at`
#' @return the timer id
#' @noRd
reactor_timer = function(at, fn, run = NULL) {
  check_number(at, "at")
  check_function(fn, "fn")
  r = reactor_get()
  id = reactor_id(r)
  assign(id, list(at = at, fn = fn, run = reactor_run_id(run)), envir = r$timers)
  id
}

#' Register a task: `fn()` runs once per pump iteration until it returns FALSE
#'
#' `TRUE` or `NULL` means "call me again in the next iteration" (iterations then last at most
#' 5 ms, never zero: see reactor_next_due()); a number means "call me again after that many
#' seconds" (the `wait` of an `inprocess` generator, contract 8.1). A task that fails is
#' removed (the error becomes a diagnostic).
#' @return the task id
#' @noRd
reactor_task = function(fn, run = NULL) {
  check_function(fn, "fn")
  r = reactor_get()
  id = reactor_id(r)
  t = new.env(parent = emptyenv())
  t$fn = fn
  t$run = reactor_run_id(run)
  t$next_at = -Inf
  t$busy = FALSE
  assign(id, t, envir = r$tasks)
  id
}

#' Queue one R-evaluating tool of a run in the FIFO
#' @param run the `gptr_run` (or its id) the tool belongs to.
#' @param fn zero-argument function executing the tool.
#' @return invisible(the FIFO item id)
#' @noRd
reactor_enqueue_tool = function(run, fn) {
  check_function(fn, "fn")
  r = reactor_get()
  id = reactor_id(r)
  r$fifo[[length(r$fifo) + 1L]] = list(id = id, run = reactor_run_id(run), fn = fn)
  invisible(id)
}

#' Hold a strong reference to an active run until it settles (INFRA-15)
#' @noRd
reactor_run_add = function(run) {
  r = reactor_get()
  id = reactor_run_id(run)
  if (!is.na(id)) assign(id, run, envir = r$runs)
  invisible(id)
}

#' Drop the reference to a settled run (and its served mark)
#' @noRd
reactor_run_remove = function(run) {
  r = reactor_get()
  id = reactor_run_id(run)
  if (!is.na(id) && exists(id, envir = r$runs, inherits = FALSE)) rm(list = id, envir = r$runs)
  r$served = setdiff(r$served, id)
  invisible(id)
}

#' Service later's event loop (httpuv servers, background timers) when later is loaded
#'
#' later::run_now() rethrows the first error of a callback; like every other callback error in
#' the pump it becomes a registry diagnostic, so a failing httpuv handler or background tick
#' cannot abort the caller's gptr() call. Interrupts still propagate.
#' @noRd
later_run_now = function() {
  if (!isNamespaceLoaded("later")) return(invisible(FALSE))
  tryCatch(later::run_now(0), error = function(e) {
    registry_diagnostic("reactor", "later", "error", conditionMessage(e))
  })
  invisible(TRUE)
}

#' Pump the reactor: the only blocking wait in gptr
#'
#' @param until zero-argument function; the pump returns `TRUE` as soon as it returns TRUE.
#' @param slice_ms upper bound of one wait, in milliseconds.
#' @param allow_runs run ids whose FIFO tools may run in this pump; `NULL` means all. When not
#'   given it is `NULL` only when no pump is on the stack, else `character()`: every tool runs
#'   inside a pump, so a nested pump started while any tool executes (`run_current()` of 04)
#'   or from any other reactor callback runs no FIFO tool unless it names the runs (IC-57).
#' @param timeout seconds; the pump returns `FALSE` when they have passed.
#' @return invisible(lgl(1))
#' @noRd
reactor_pump = function(until = function() FALSE, slice_ms = 100L, allow_runs = NULL,
                        timeout = Inf) {
  check_function(until, "until")
  check_number(slice_ms, "slice_ms", min = 0)
  check_number(timeout, "timeout", min = 0)
  r = reactor_get()
  if (missing(allow_runs)) {
    allow_runs = if (r$depth == 0L) NULL else character()
  } else {
    check_strings(allow_runs, "allow_runs", null = TRUE)
  }
  r$depth = r$depth + 1L
  r$allow_stack = c(r$allow_stack, list(allow_runs))
  on.exit({
    r$depth = r$depth - 1L
    r$allow_stack = r$allow_stack[-length(r$allow_stack)]
  }, add = TRUE)
  t_end = reactor_now() + timeout
  repeat {
    if (isTRUE(until())) return(invisible(TRUE))
    if (reactor_now() >= t_end) return(invisible(FALSE))
    reactor_step(r, allow_runs, slice_ms, t_end)
  }
}

#' One pump iteration (contract 8.2): I/O, timers, tasks, later, at most one FIFO tool
#' @noRd
reactor_step = function(r, allow_runs, slice_ms, t_end) {
  reactor_io(r, allow_runs, slice_ms, t_end)
  reactor_fire_timers(r)
  reactor_run_tasks(r)
  if (r$depth == 1L || length(intersect(allow_runs, r$served))) later_run_now()
  reactor_run_fifo(r, allow_runs)
  invisible(NULL)
}

#' Wait for the next event: timers, tasks, the FIFO and child pipes
#' @noRd
reactor_io = function(r, allow_runs, slice_ms, t_end) {
  reactor_admit(r)
  wait = reactor_wait_ms(r, allow_runs, slice_ms, t_end)
  active = reactor_active(r)
  pollables = reactor_pollables(r)
  if (length(active)) {
    fds = curl::multi_fdset(pool = r$pool)
    if (is.numeric(fds$timeout) && length(fds$timeout) == 1L && fds$timeout >= 0) {
      wait = min(wait, fds$timeout)
    }
    pollables = c(list(processx::curl_fds(fds)), pollables)
  }
  if (length(pollables)) {
    processx::poll(pollables, as.integer(min(wait, .Machine$integer.max)))
  } else if (wait > 0) {
    Sys.sleep(wait / 1000)
  }
  if (length(active)) {
    reactor_multi_run(r)
    reactor_check_transfers(r)
  }
  reactor_read_procs(r)
  reactor_drain_stdin(r)
  invisible(NULL)
}

#' How long this iteration may wait, in milliseconds (pending stdin: at most 5 ms)
#' @noRd
reactor_wait_ms = function(r, allow_runs, slice_ms, t_end) {
  if (reactor_fifo_ready(r, allow_runs)) return(0)
  now = reactor_now()
  at = min(t_end, reactor_next_due(r))
  if (length(ls(r$stdin, sorted = FALSE))) at = min(at, now + 0.005)
  for (id in ls(r$transfers, sorted = FALSE)) {
    tr = r$transfers[[id]]
    if (identical(tr$state, "active") && !isTRUE(tr$busy)) {
      at = min(at, http_timeout_next(tr$t_start, tr$t_first, tr$t_last, tr$timeouts))
    } else if (identical(tr$state, "queued")) {
      at = min(at, ratelimit_next(tr$provider))
    }
  }
  max(0, min(as.numeric(slice_ms), (at - now) * 1000))
}

#' The earliest due time of the timers and tasks
#'
#' A task that asked to run again in the next iteration (it returned TRUE or NULL) counts as due
#' 5 ms from now, not now: tasks run once per iteration, but they never shorten the wait to
#' zero. P06's `run_drive()` and P05's abort watcher return TRUE for the whole of a request, so
#' a zero wait would make every gptr() call spin a CPU core while it waits for the model. A task
#' whose call is still running (a pump nested inside it) is not due at all.
#' @noRd
reactor_next_due = function(r) {
  at = Inf
  for (id in ls(r$timers, sorted = FALSE)) at = min(at, r$timers[[id]]$at)
  tick = reactor_now() + 0.005
  for (id in ls(r$tasks, sorted = FALSE)) {
    t = r$tasks[[id]]
    if (!isTRUE(t$busy)) at = min(at, max(t$next_at, tick))
  }
  at
}

#' Is a FIFO item runnable in this pump?
#' @noRd
reactor_fifo_ready = function(r, allow_runs) {
  if (!length(r$fifo)) return(FALSE)
  if (is.null(allow_runs)) return(TRUE)
  any(vapply(r$fifo, function(x) x$run %in% allow_runs, NA))
}

#' Run at most one FIFO tool whose run is allowed in this pump
#'
#' The item leaves the FIFO before it runs; its run id is on `tool_stack` while it executes.
#' A tool that fails becomes a diagnostic (dispatchers turn failures into tool results
#' themselves; this is the last line of defence).
#' @noRd
reactor_run_fifo = function(r, allow_runs) {
  if (!length(r$fifo)) return(invisible(FALSE))
  ok = if (is.null(allow_runs)) {
    rep(TRUE, length(r$fifo))
  } else {
    vapply(r$fifo, function(x) x$run %in% allow_runs, NA)
  }
  k = which(ok)
  if (!length(k)) return(invisible(FALSE))
  item = r$fifo[[k[1L]]]
  r$fifo = r$fifo[-k[1L]]
  r$tool_stack = c(r$tool_stack, item$run)
  on.exit({
    r$tool_stack = r$tool_stack[-length(r$tool_stack)]
  }, add = TRUE)
  reactor_call("tool", item$fn)
  invisible(TRUE)
}

#' Fire due timers in time order (each once; removed before it runs)
#' @noRd
reactor_fire_timers = function(r) {
  ids = reactor_ids(r$timers)
  if (!length(ids)) return(invisible(NULL))
  now = reactor_now()
  at = vapply(ids, function(id) r$timers[[id]]$at, 0)
  due = ids[at <= now][order(at[at <= now])]
  for (id in due) {
    tm = r$timers[[id]]
    if (is.null(tm)) next
    rm(list = id, envir = r$timers)
    reactor_call("timer", tm$fn)
  }
  invisible(NULL)
}

#' Run due tasks; a task returning FALSE (or failing) is removed
#'
#' A task whose call is still running is skipped, so a pump nested inside that call (an
#' `inprocess` generator whose events reach a hook that calls System 1, IC-57) never calls the
#' task again before it returned: its events can neither interleave nor arrive out of order.
#' @noRd
reactor_run_tasks = function(r) {
  for (id in reactor_ids(r$tasks)) {
    t = r$tasks[[id]]
    if (is.null(t) || isTRUE(t$busy) || reactor_now() < t$next_at) next
    res = reactor_run_task(t)
    if (inherits(res, "error") || isFALSE(res)) {
      if (exists(id, envir = r$tasks, inherits = FALSE)) rm(list = id, envir = r$tasks)
    } else if (is.numeric(res) && length(res) == 1L && !is.na(res)) {
      t$next_at = reactor_now() + max(0, res)
    } else {
      t$next_at = -Inf
    }
  }
  invisible(NULL)
}

#' Call one task with its busy mark set (cleared on exit, also when an interrupt unwinds it)
#' @noRd
reactor_run_task = function(t) {
  t$busy = TRUE
  on.exit({
    t$busy = FALSE
  }, add = TRUE)
  reactor_call("task", t$fn)
}

#' Cancel reactor work by id: transfers, timers, tasks, FIFO items and process watchers
#' @param ids chr of ids returned by reactor_http(), reactor_proc(), reactor_timer(),
#'   reactor_task() or reactor_enqueue_tool(); unknown ids are ignored.
#' @return invisible(int(1)) the number of items cancelled
#' @noRd
reactor_cancel = function(ids) {
  check_strings(ids, "ids")
  r = reactor_get()
  n = 0L
  for (id in ids) n = n + reactor_cancel_id(r, id)
  invisible(n)
}

#' Cancel one id: timers, tasks, FIFO items and process watchers
#'
#' A process watcher is removed and its child is interrupted, given the grace period and killed
#' with its tree (kill_all()); `on_exit` is not called.
#' @return int(1) 1 when something was cancelled
#' @noRd
reactor_cancel_id = function(r, id) {
  tr = r$transfers[[id]]
  if (!is.null(tr)) return(reactor_cancel_transfer(r, tr))
  if (exists(id, envir = r$timers, inherits = FALSE)) {
    rm(list = id, envir = r$timers)
    return(1L)
  }
  if (exists(id, envir = r$tasks, inherits = FALSE)) {
    rm(list = id, envir = r$tasks)
    return(1L)
  }
  k = which(vapply(r$fifo, function(x) identical(x$id, id), NA))
  if (length(k)) {
    r$fifo = r$fifo[-k]
    return(1L)
  }
  w = r$procs[[id]]
  if (!is.null(w)) {
    rm(list = id, envir = r$procs)
    reactor_stdin_drop(r, w$p, "The child was cancelled before stdin was delivered.")
    kill_all(w$p)
    return(1L)
  }
  0L
}

#' Unload cleanup: kill watched children and forget all reactor state
#' @noRd
reactor_shutdown = function() {
  r = get0("reactor", envir = the, inherits = FALSE)
  if (is.null(r)) return(invisible(NULL))
  for (id in ls(r$transfers, sorted = FALSE)) {
    try(reactor_cancel_transfer(r, r$transfers[[id]]), silent = TRUE)
  }
  children = lapply(ls(r$procs, sorted = FALSE), function(id) r$procs[[id]]$p)
  pending = lapply(ls(r$stdin, sorted = FALSE), function(key) r$stdin[[key]]$p)
  # In-flight callbacks still hold r. Clear its tables before stopping children so
  # they cannot deliver more lines or schedule old work after shutdown.
  for (table in list(r$procs, r$timers, r$tasks)) rm(list = ls(table), envir = table)
  r$fifo = list()
  rm(list = "reactor", envir = the)
  stopped = list()
  for (p in c(children, pending)) {
    reactor_stdin_drop(r, p, "The reactor stopped before stdin was delivered.")
    if (any(vapply(stopped, identical, NA, p))) next
    try(kill_all(p, grace = 0), silent = TRUE)
    stopped[[length(stopped) + 1L]] = p
  }
  invisible(NULL)
}

on_load(on_unload(reactor_shutdown))

# ---- child-process watchers and non-blocking stdin (IC-60) ---------------------------------

#' Watch a child's pipes
#'
#' `on_line(line)` per complete line of `stream` (UTF-8, a trailing carriage return stripped,
#' at most 512 chunks per iteration, lines up to 16 MiB); `on_stderr(line)` per line of the
#' other stream when `stream = "stdout"` (drained and dropped when NULL); `on_exit(status)`
#' once, after the process exited and both pipes reached end of stream. A callback may pump the
#' reactor, but the watcher's own later lines are delivered only after the callback returned:
#' work that needs the child's next answer (a request made from inside `on_line`) is scheduled
#' with `reactor_timer(reactor_now(), fn)` instead of waited for inside the callback.
#' @return the watcher id
#' @noRd
reactor_proc = function(proc, on_line, on_exit, run = NULL, stream = "stdout",
                        on_stderr = NULL) {
  check_function(on_line, "on_line")
  check_function(on_exit, "on_exit")
  check_function(on_stderr, "on_stderr", null = TRUE)
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  r = reactor_get()
  id = reactor_id(r)
  w = new.env(parent = emptyenv())
  w$id = id
  w$p = proc
  w$run = reactor_run_id(run)
  has_out = isTRUE(tryCatch(proc$has_output_connection(), error = function(e) FALSE))
  has_err = isTRUE(tryCatch(proc$has_error_connection(), error = function(e) FALSE))
  other = if (stream == "stdout") "stderr" else "stdout"
  has_main = if (stream == "stdout") has_out else has_err
  has_other = if (stream == "stdout") has_err else has_out
  w$main = if (has_main) line_reader(proc, stream) else NULL
  w$other = if (has_other) line_reader(proc, other) else NULL
  w$on_main = on_line
  w$on_other = if (stream == "stdout") on_stderr else NULL
  w$on_exit = on_exit
  assign(id, w, envir = r$procs)
  id
}

#' The pipe connections still worth polling
#'
#' A watcher whose callback is running (a pump nested inside it) is left out: its unread output
#' would make every poll of the nested pump return at once.
#' @noRd
reactor_pollables = function(r) {
  out = list()
  for (id in ls(r$procs, sorted = FALSE)) {
    w = r$procs[[id]]
    if (is.null(w) || isTRUE(w$busy)) next
    p = w$p
    if (isTRUE(tryCatch(p$is_incomplete_output(), error = function(e) FALSE))) {
      out[[length(out) + 1L]] = p$get_output_connection()
    }
    if (isTRUE(tryCatch(p$is_incomplete_error(), error = function(e) FALSE))) {
      out[[length(out) + 1L]] = p$get_error_connection()
    }
  }
  out
}

#' Deliver the ready lines of every watched child; report each exit once
#'
#' A watcher whose callback is running is skipped, so a pump nested inside `on_line` (a
#' `process_jsonl` normaliser whose events reach a hook that calls System 1, IC-57) neither
#' delivers its later lines re-entrantly or out of order nor reports its exit early or twice.
#' @noRd
reactor_read_procs = function(r) {
  for (id in reactor_ids(r$procs)) {
    w = r$procs[[id]]
    if (!is.null(w) && !isTRUE(w$busy)) reactor_read_proc(r, id, w)
  }
  invisible(NULL)
}

#' Deliver one watcher's lines, then its exit; stop as soon as a callback cancelled the watcher
#' @noRd
reactor_read_proc = function(r, id, w) {
  w$busy = TRUE
  on.exit({
    w$busy = FALSE
  }, add = TRUE)
  live = function() exists(id, envir = r$procs, inherits = FALSE)
  if (!is.null(w$main)) {
    for (ln in w$main$read()) {
      if (!live()) return(invisible(NULL))
      reactor_call("on_line", w$on_main, ln)
    }
  }
  if (!is.null(w$other)) {
    lines = w$other$read()
    if (!is.null(w$on_other)) {
      for (ln in lines) {
        if (!live()) return(invisible(NULL))
        reactor_call("on_stderr", w$on_other, ln)
      }
    }
  }
  done = (is.null(w$main) || w$main$eof()) && (is.null(w$other) || w$other$eof())
  alive = tryCatch(w$p$is_alive(), error = function(e) NA)
  if (done && live() && isFALSE(alive)) {
    rm(list = id, envir = r$procs)
    status = tryCatch(w$p$get_exit_status(), error = function(e) NA_integer_)
    reactor_stdin_drop(r, w$p, "The child exited before stdin was delivered.")
    proc_release(w$p)
    reactor_call("on_exit", w$on_exit, if (is.null(status)) NA_integer_ else status)
  }
  invisible(NULL)
}

#' Write pending stdin bytes without blocking; fail buffers that cannot be delivered
#'
#' processx's write_input() writes at most about 8 KB per call and returns the rest (report 08
#' verification: one call truncated a 50 KB prompt), so each child gets up to 64 slices of
#' 64 KB per iteration and the pump reads the child's output between attempts. A buffer that
#' made no progress for `gptr.stdin_timeout` seconds is dropped, the child's stdin is closed
#' and a typed failure is kept for write_all(). Write errors and premature exit likewise
#' fail instead of claiming delivery; inside a pump failures become registry diagnostics.
#' @noRd
reactor_drain_stdin = function(r) {
  for (key in ls(r$stdin, sorted = FALSE)) {
    b = r$stdin[[key]]
    if (!is.null(b) && !isTRUE(b$busy)) reactor_drain_child(r, key, b)
  }
  invisible(NULL)
}


#' Fail one owned stdin buffer without exposing its bytes or an arbitrary process error
#' @noRd
reactor_stdin_fail = function(r, key, b, message, class = "io") {
  fields = if (class == "timeout") list(what = "stdin", seconds = b$limit) else
    list(operation = "write", path = NULL)
  b$failed = TRUE
  b$error = gptr_condition(message, class, fields = fields)
  if (identical(r$stdin[[key]], b)) rm(list = key, envir = r$stdin)
  try(close(b$p$get_input_connection()), silent = TRUE)
  if (!isTRUE(b$waited)) registry_diagnostic("reactor", "stdin", class, message)
  invisible(NULL)
}

#' Remove a pending buffer only when it belongs to the same original process object
#' @noRd
reactor_stdin_drop = function(r, p, message) {
  key = as.character(p$get_pid())
  b = r$stdin[[key]]
  if (!is.null(b) && identical(b$p, p)) {
    # Reading output after a successful write can observe immediate child exit.
    # Bytes already accepted by the pipe are complete, even before the drain settles.
    if (b$pos >= length(b$bytes)) {
      if (isTRUE(b$close)) try(close(p$get_input_connection()), silent = TRUE)
      rm(list = key, envir = r$stdin)
    } else {
      reactor_stdin_fail(r, key, b, message)
    }
  }
  invisible(NULL)
}

#' Give one child a bounded write slice, reading ready output between successful writes
#' @noRd
reactor_drain_child = function(r, key, b) {
  b$busy = TRUE
  on.exit({
    b$busy = FALSE
  }, add = TRUE)
  p = b$p
  alive = tryCatch(p$is_alive(), error = function(e) NA)
  if (isFALSE(alive)) {
    reactor_stdin_fail(r, key, b, "The child exited before stdin was delivered.")
    return(invisible(NULL))
  }
  if (isTRUE(alive)) {
    k = 0L
    while (b$pos < length(b$bytes) && k < 64L && identical(r$stdin[[key]], b)) {
      end = min(length(b$bytes), b$pos + 65536L)
      slice = b$bytes[(b$pos + 1L):end]
      rest = tryCatch(p$write_input(slice), error = function(e) NULL)
      if (!is.raw(rest) || length(rest) > length(slice)) {
        reactor_stdin_fail(r, key, b, "Could not write the queued bytes to child stdin.")
        return(invisible(NULL))
      }
      written = length(slice) - length(rest)
      if (written <= 0L) break
      b$pos = b$pos + written
      b$last = reactor_now()
      k = k + 1L
      reactor_read_procs(r)
    }
  }
  if (!identical(r$stdin[[key]], b)) return(invisible(NULL))
  if (b$pos >= length(b$bytes)) {
    if (isTRUE(b$close)) try(close(p$get_input_connection()), silent = TRUE)
    rm(list = key, envir = r$stdin)
  } else if (reactor_now() - b$last >= b$limit) {
    reactor_stdin_fail(r, key, b,
      paste0("Timed out writing to child stdin: nothing was consumed for ", b$limit, " s."),
      class = "timeout")
  }
  invisible(NULL)
}

# ---- the opt-in wire log (INFRA-28; IC-59, IC-65) ------------------------------------------

#' Where the wire log of a session goes, or NULL when the log is off
#'
#' `options(gptr.wire_log = TRUE)`: `<workspace root>/cache/tmp/wire-<session id>.jsonl`. A
#' string names a directory (one file per session inside it) or, ending in `.jsonl`, one file;
#' it must lie inside the workspace root or `tempdir()`, otherwise the default location is used
#' (with a one-time notice).
#' @noRd
wire_log_path = function(session) {
  opt = gptr_opt("wire_log")
  if (is.null(opt) || isFALSE(opt)) return(NULL)
  file = paste0("wire-", gsub("[^A-Za-z0-9_-]", "_", session %||% "nosession"), ".jsonl")
  roots = c(workspace_root(create = FALSE), tempdir())
  safe = function(path) {
    part = path
    repeat {
      link = Sys.readlink(part)
      if (!is.na(link) && nzchar(link) && !file.exists(part)) return(FALSE)
      parent = dirname(part)
      if (identical(parent, part)) break
      part = parent
    }
    any(vapply(roots, function(root) path_inside(path, root), NA))
  }
  prepare = function(path) {
    if (!safe(path) || !safe(dirname(path))) return(NULL)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    path
  }
  default = function() prepare(file.path(roots[1L], "cache", "tmp", file))
  if (isTRUE(opt)) return(default())
  if (!is.character(opt) || length(opt) != 1L || is.na(opt) || !nzchar(opt)) return(NULL)
  path = if (grepl("[.]jsonl$", opt)) opt else file.path(opt, file)
  if (!safe(path) || !safe(dirname(path))) {
    gptr_inform("gptr.wire_log must be inside the workspace root or tempdir(); using the default.",
                "notice", .once = "wire_log_path")
    return(default())
  }
  prepare(path)
}

#' Append one line: open, append, close (no connection outlives the call; IC-59)
#' @noRd
wire_log_append = function(path, line) {
  append_line = function() {
    con = file(path, open = "ab")
    on.exit(close(con), add = TRUE)
    writeLines(as_utf8(line), con, useBytes = TRUE)
    flush(con)
  }
  suspendInterrupts(append_line())
  invisible(path)
}

#' One redacted wire-log line for a transfer (request start or terminal event)
#'
#' Fields `ts` (epoch seconds), `request_id`, `provider`, `model`, `url` (origin and path only),
#' `status`, `bytes`, `seconds`, `event`; never headers or bodies (contract 8.2).
#' @param tr the transfer environment (`session`, `request_id`, `provider`, `model`, `spec$url`,
#'   `bytes`, `t_start`).
#' @noRd
wire_log = function(tr, event, status = NULL) {
  path = tryCatch(wire_log_path(tr$session), error = function(e) NULL)
  if (is.null(path)) return(invisible(NULL))
  present = function(x) {
    if (is.null(x) || (length(x) == 1L && is.na(x))) NULL else x
  }
  st = present(status)
  # `ts` is seconds since the epoch, as for every `ts` of contract 1.2
  rec = list(ts = round(as.numeric(Sys.time()), 3),
             request_id = tr$request_id,
             provider = present(tr$provider),
             model = present(tr$model),
             url = url_for_log(tr$spec$url), status = if (is.null(st)) NULL else as.integer(st),
             bytes = tr$bytes, seconds = round(reactor_now() - tr$t_start, 3), event = event)
  rec = rec[!vapply(rec, is.null, NA)]
  tryCatch(wire_log_append(path, json_encode(redact(rec, "persist"))), error = function(e) NULL)
  invisible(NULL)
}

# ---- HTTP transfers (INFRA-01, 05, 06, 21, 28; IC-64) --------------------------------------

#' Queue one HTTP transfer
#'
#' `spec` is an adapter's `build()` result (contract 8.1): `url`, `method`, `headers`, `body`,
#' `stream`. Optional fields read here: `request_id`, `model` and `session_id` (labels for the
#' wire log and for condition fields) and `connect_timeout`, `first_byte_timeout`,
#' `idle_timeout` (seconds; P05 copies them from `opts`). Callbacks: `on_headers(status,
#' headers)` once per attempt that received a 2xx head (normally once; a second call follows a
#' retry and means "start over"); `on_bytes(raw)` per body chunk of a 2xx response;
#' `on_done(status, headers)` at the end; `on_fail(cnd)` with a classed, unsignalled
#' `gptr_error_*` condition. Exactly one of `on_done` and `on_fail` runs, unless the transfer
#' is cancelled. Callbacks run after curl::multi_run() has returned (never inside libcurl), so
#' they may cancel, retry, start transfers or pump the reactor; the transfer's own later events
#' reach it only after the running callback returned. `retry` is
#' `list(max_attempts = gptr.max_attempts, committed = function()
#' lgl(1), on_retry = NULL)`; `on_retry(type, info)` receives `"retry_start"` (`info`:
#' `attempt`, `delay`, `class`) and `"retry_end"` (`info`: `attempt`, `ok`), which P05 forwards
#' to `emit` as the `retry_start`/`retry_end` events. Without `committed`, a transfer counts as
#' committed once a 2xx body byte reached `on_bytes`.
#' @return the transfer id
#' @noRd
reactor_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL,
                        provider = NULL, retry = NULL) {
  check_list(spec, "spec", named = TRUE)
  check_string(spec[["url"]], "spec$url")
  check_function(on_bytes, "on_bytes")
  check_function(on_done, "on_done")
  check_function(on_fail, "on_fail")
  check_function(on_headers, "on_headers", null = TRUE)
  check_string(provider, "provider", null = TRUE)
  check_list(retry, "retry", named = TRUE, null = TRUE)
  for (name in c("model", "request_id", "session_id")) {
    check_string(spec[[name]], paste0("spec$", name), null = TRUE)
  }
  attempts = retry[["max_attempts"]] %||% gptr_opt("max_attempts") %||% 4L
  check_number(attempts, "max_attempts", min = 1, int = TRUE)
  check_function(retry[["committed"]], "retry$committed", null = TRUE)
  check_function(retry[["on_retry"]], "retry$on_retry", null = TRUE)
  check_number(gptr_opt("max_active"), "gptr.max_active", min = 1, int = TRUE)
  r = reactor_get()
  id = reactor_id(r)
  tr = new.env(parent = emptyenv())
  tr$id = id
  tr$spec = spec
  tr$on_bytes = on_bytes
  tr$on_done = on_done
  tr$on_fail = on_fail
  tr$on_headers = on_headers
  tr$run = reactor_run_id(run)
  tr$session = spec[["session_id"]] %||% reactor_run_session(run)
  tr$provider = provider
  tr$model = spec[["model"]] %||% NA_character_
  tr$request_id = spec[["request_id"]] %||% id_new("q", 12L)
  tr$delivered = FALSE
  tr$inbox = list()
  tr$busy = FALSE
  tr$head_pending = FALSE
  committed = retry[["committed"]] %||% function() tr$delivered
  tr$retry = list(max_attempts = as.integer(attempts),
                  committed = committed, on_retry = retry[["on_retry"]])
  tr$timeouts = http_timeouts(spec)
  tr$attempt = 0L
  tr$state = "queued"
  tr$status = NA_integer_
  tr$bytes = 0
  tr$t_start = reactor_now()
  assign(id, tr, envir = r$transfers)
  r$queue = c(r$queue, id)
  id
}

#' Ids of the transfers currently in the curl pool
#' @noRd
reactor_active = function(r) {
  ids = ls(r$transfers, sorted = FALSE)
  ids[vapply(ids, function(id) identical(r$transfers[[id]]$state, "active"), NA)]
}

#' Admit queued transfers while the global and per-provider slots allow (never waits)
#'
#' A transfer that cannot start calls its `on_fail` from here, and that callback may queue new
#' transfers (a fallback request) or pump the reactor. The queue is therefore rebuilt at the end
#' from every transfer that is still queued, so a transfer queued by such a callback is kept.
#' @noRd
reactor_admit = function(r) {
  if (!length(r$queue)) return(invisible(NULL))
  max_active = as.integer(gptr_opt("max_active") %||% 8L)
  n = length(reactor_active(r))
  for (id in r$queue) {
    if (n >= max_active) break
    tr = r$transfers[[id]]
    if (is.null(tr) || !identical(tr$state, "queued")) next
    if (!ratelimit_admit(tr$provider)) next
    reactor_start(r, tr)
    # a start that failed ran on_fail, which may have started transfers of its own
    n = length(reactor_active(r))
  }
  queued = vapply(r$queue, function(id) identical(r$transfers[[id]]$state, "queued"), NA,
                  USE.NAMES = FALSE)
  r$queue = unique(r$queue[queued])
  invisible(NULL)
}

#' Start (or re-send) one attempt of a transfer
#' @noRd
reactor_start = function(r, tr) {
  tr$attempt = tr$attempt + 1L
  tr$state = "active"
  tr$t_start = reactor_now()
  tr$t_first = NA_real_
  tr$t_last = tr$t_start
  tr$status = NA_integer_
  tr$headers = list()
  tr$ok = FALSE
  tr$err_body = list()
  h = tryCatch(http_handle(tr$spec), error = function(e) e)
  if (inherits(h, "error")) {
    tr$state = "failed"
    reactor_forget(r, tr)
    wire_log(tr, "error")
    reactor_call("on_fail", tr$on_fail, h)
    return(invisible(NULL))
  }
  tr$handle = h
  wire_log(tr, "start")
  # the curl callbacks only queue the event: reactor_deliver() hands it to the transfer's
  # callbacks after curl::multi_run() has returned, outside libcurl, so on_bytes, on_headers,
  # on_done and on_fail may cancel, retry, start transfers or pump the reactor (libcurl refuses
  # every multi API call made from inside its own callbacks); events of an abandoned attempt
  # are dropped, so they can never feed or finish the next attempt
  k = tr$attempt
  added = tryCatch({
    curl::multi_add(h, pool = r$pool,
                    data = function(x, final = FALSE) reactor_curl_event(tr, k, "data", x),
                    done = function(res) reactor_curl_event(tr, k, "done", res),
                    fail = function(msg) reactor_curl_event(tr, k, "fail", msg))
    TRUE
  }, error = function(e) e)
  if (inherits(added, "error")) {
    reactor_abandon(r, tr, transport_error(paste0("The transfer could not start: ",
                                                  conditionMessage(added)), "internal",
                                           detail = conditionMessage(added)))
  }
  invisible(NULL)
}

#' Queue one curl callback of an attempt (runs inside curl::multi_run(): no user code here)
#' @noRd
reactor_curl_event = function(tr, k, type, value) {
  if (!identical(tr$attempt, k)) return(invisible(NULL))
  if (identical(type, "data")) tr$t_last = reactor_now()
  tr$inbox[[length(tr$inbox) + 1L]] = list(k = k, type = type, value = value)
  invisible(NULL)
}

#' Deliver the queued curl events of every transfer (after curl::multi_run() returned)
#'
#' Events reach each transfer in arrival order. While one of a transfer's callbacks runs, the
#' transfer is busy: a pump nested inside that callback (a hook calling System 1, say) skips
#' it, so its next chunk is never delivered re-entrantly or ahead of the rest of the current
#' one; the outer delivery picks it up when the callback returns.
#' @noRd
reactor_deliver = function(r) {
  for (id in reactor_ids(r$transfers)) {
    tr = r$transfers[[id]]
    if (!is.null(tr) && !isTRUE(tr$busy) && (length(tr$inbox) || isTRUE(tr$head_pending))) {
      reactor_deliver_one(r, tr)
    }
  }
  invisible(NULL)
}

#' Deliver one transfer's queued events in order
#' @noRd
reactor_deliver_one = function(r, tr) {
  tr$busy = TRUE
  on.exit({
    tr$busy = FALSE
  }, add = TRUE)
  reactor_head_notify(r, tr)
  while (length(tr$inbox)) {
    ev = tr$inbox[[1L]]
    tr$inbox = tr$inbox[-1L]
    if (!identical(tr$attempt, ev$k)) next
    switch(ev$type,
           data = reactor_on_data(r, tr, ev$value),
           done = reactor_on_done(r, tr, ev$value),
           fail = reactor_on_fail(r, tr, ev$value))
  }
  invisible(NULL)
}

#' Record the response head the first time it is visible (no user callback runs here)
#' @noRd
reactor_head = function(r, tr) {
  if (!is.na(tr$t_first)) return(invisible(TRUE))
  d = tryCatch(curl::handle_data(tr$handle), error = function(e) NULL)
  status = if (is.null(d)) 0L else as.integer(d$status_code)
  if (is.na(status) || status < 200L) return(invisible(FALSE))
  tr$t_first = reactor_now()
  tr$t_last = tr$t_first
  tr$status = status
  tr$headers = tryCatch(curl::parse_headers_list(d$headers), error = function(e) list())
  tr$ok = status >= 200L && status < 300L
  tr$head_pending = tr$ok
  ratelimit_update(tr$provider, tr$headers)
  invisible(TRUE)
}

#' Tell the callbacks about a 2xx head once per attempt: `retry_end` after a retry, on_headers
#'
#' Called only while the transfer's events are delivered (the transfer is busy).
#' @noRd
reactor_head_notify = function(r, tr) {
  if (!isTRUE(tr$head_pending)) return(invisible(NULL))
  tr$head_pending = FALSE
  if (tr$attempt > 1L && !is.null(tr$retry$on_retry)) {
    reactor_call("on_retry", tr$retry$on_retry, "retry_end",
                 list(attempt = tr$attempt, ok = TRUE))
  }
  if (!is.null(tr$on_headers)) {
    res = reactor_call("on_headers", tr$on_headers, tr$status, tr$headers)
    if (inherits(res, "error") && identical(tr$state, "active")) {
      cnd = transport_error(paste0("A headers callback failed: ", conditionMessage(res)),
                            "internal", detail = conditionMessage(res))
      reactor_abandon(r, tr, cnd)
    }
  }
  invisible(NULL)
}

#' A delivered data event: 2xx bytes go to on_bytes, other bodies are kept for classification
#' @noRd
reactor_on_data = function(r, tr, x) {
  if (!identical(tr$state, "active")) return(invisible(NULL))
  reactor_head(r, tr)
  reactor_head_notify(r, tr)
  # on_headers may have cancelled or retried the transfer
  if (!identical(tr$state, "active")) return(invisible(NULL))
  tr$t_last = reactor_now()
  if (!length(x)) return(invisible(NULL))
  tr$bytes = tr$bytes + length(x)
  if (isTRUE(tr$ok)) {
    tr$delivered = TRUE
    res = reactor_call("on_bytes", tr$on_bytes, x)
    if (inherits(res, "error") && identical(tr$state, "active")) {
      cnd = transport_error(paste0("A stream callback failed: ", conditionMessage(res)),
                            "internal", detail = conditionMessage(res))
      reactor_abandon(r, tr, cnd)
    }
  } else {
    tr$err_body[[length(tr$err_body) + 1L]] = x
  }
  invisible(NULL)
}

#' A delivered done event: 2xx ends the transfer, anything else is classified
#' @noRd
reactor_on_done = function(r, tr, res) {
  if (!identical(tr$state, "active")) return(invisible(NULL))
  reactor_head(r, tr)
  reactor_head_notify(r, tr)
  if (!identical(tr$state, "active")) return(invisible(NULL))
  status = as.integer(res$status_code)
  headers = tryCatch(curl::parse_headers_list(res$headers), error = function(e) list())
  if (!is.na(status) && status >= 200L && status < 300L) {
    tr$state = "done"
    reactor_forget(r, tr)
    wire_log(tr, "done", status)
    reactor_call("on_done", tr$on_done, status, headers)
    return(invisible(NULL))
  }
  body = if (length(tr$err_body)) do.call(c, tr$err_body) else raw(0)
  cl = retry_classify(status, headers, body)
  reactor_failure(r, tr, cl, status = status, headers = headers)
  invisible(NULL)
}

#' A delivered fail event: connection failures and other libcurl errors
#' @noRd
reactor_on_fail = function(r, tr, msg) {
  if (!identical(tr$state, "active")) return(invisible(NULL))
  cl = retry_classify(NA_integer_, list(), curl_error = msg)
  reactor_failure(r, tr, cl, status = NA_integer_)
  invisible(NULL)
}

#' Enforce the first-byte and idle timers of active transfers (INFRA-05; never retried)
#'
#' A busy transfer (one of its callbacks is running a nested pump) is skipped: its bytes may
#' be waiting in its queue, and its callbacks must not run re-entrantly.
#' @noRd
reactor_check_transfers = function(r) {
  now = reactor_now()
  for (id in reactor_active(r)) {
    tr = r$transfers[[id]]
    if (is.null(tr) || isTRUE(tr$busy)) next
    reactor_head(r, tr)
    if (!identical(tr$state, "active")) next
    hit = http_timeout_check(tr$t_start, tr$t_first, tr$t_last, tr$timeouts, now)
    if (is.null(hit)) next
    msg = paste0("No ", if (hit$what == "first byte") "first response byte" else "stream data",
                 " for ", hit$seconds, " s (", url_for_log(tr$spec$url), ").")
    cnd = transport_error(msg, hit$class, seconds = hit$seconds, what = hit$what,
                          provider = tr$provider)
    reactor_abandon(r, tr, cnd)
  }
  invisible(NULL)
}

#' Stop the active attempt and fail the transfer without retrying
#' @noRd
reactor_abandon = function(r, tr, cnd) {
  tr$state = "failed"
  reactor_curl_cancel(r, tr$handle)
  reactor_forget(r, tr)
  wire_log(tr, "error", tr$status)
  if (tr$attempt > 1L && !is.null(tr$retry$on_retry)) {
    reactor_call("on_retry", tr$retry$on_retry, "retry_end",
                 list(attempt = tr$attempt, ok = FALSE))
  }
  reactor_call("on_fail", tr$on_fail, cnd)
  invisible(NULL)
}

#' Fail a transfer after a classified failure
#' @return lgl(1) TRUE when a re-send was scheduled
#' @noRd
reactor_failure = function(r, tr, cl, status = NA_integer_, headers = list()) {
  reactor_fail_final(r, tr, cl, status, headers)
}

#' The terminal failure: the classed condition with the fields of contract 2.2, to on_fail
#' @return FALSE
#' @noRd
reactor_fail_final = function(r, tr, cl, status = NA_integer_, headers = list()) {
  if (identical(tr$state, "active")) reactor_curl_cancel(r, tr$handle)
  tr$state = "failed"
  reactor_forget(r, tr)
  h = retry_headers(headers)
  rid = retry_header(h, "request-id") %||% retry_header(h, "x-request-id") %||% tr$request_id
  fields = list(provider = tr$provider,
                model = if (is.na(tr$model)) NULL else tr$model, status = status,
                request_id = rid, error_type = cl$class[1L], session = tr$session)
  if (cl$class[1L] %in% c("rate_limit", "retry_after")) fields$retry_after = cl$retry_after
  if (identical(cl$class[1L], "network")) fields$curl_code = NA_integer_
  if (identical(cl$class[1L], "redirect")) {
    loc = retry_header(h, "location")
    fields$location_origin = if (is.null(loc)) NA_character_ else url_origin(loc)
  }
  if (cl$class[1L] %in% c("timeout_idle", "timeout_connect")) {
    idle = identical(cl$class[1L], "timeout_idle")
    fields$seconds = if (idle) tr$timeouts$idle else tr$timeouts$connect
    fields$what = if (idle) "idle stream" else "connect"
  }
  cnd = transport_error(cl$message, cl$class, .data = fields)
  wire_log(tr, "error", status)
  if (tr$attempt > 1L && !is.null(tr$retry$on_retry)) {
    reactor_call("on_retry", tr$retry$on_retry, "retry_end",
                 list(attempt = tr$attempt, ok = FALSE))
  }
  reactor_call("on_fail", tr$on_fail, cnd)
  FALSE
}

#' Remove a finished transfer from the reactor
#' @noRd
reactor_forget = function(r, tr) {
  tr$handle = NULL
  if (exists(tr$id, envir = r$transfers, inherits = FALSE)) rm(list = tr$id, envir = r$transfers)
  r$queue = setdiff(r$queue, tr$id)
  invisible(NULL)
}

#' Cancel one transfer without callbacks
#' @return int(1) 1 when something was cancelled
#' @noRd
reactor_cancel_transfer = function(r, tr) {
  if (tr$state %in% c("done", "failed", "cancelled")) return(0L)
  if (identical(tr$state, "active")) reactor_curl_cancel(r, tr$handle)
  if (identical(tr$state, "waiting") && !is.null(tr$timer)) {
    if (exists(tr$timer, envir = r$timers, inherits = FALSE)) rm(list = tr$timer, envir = r$timers)
  }
  tr$state = "cancelled"
  reactor_forget(r, tr)
  wire_log(tr, "cancelled", tr$status)
  1L
}

#' Let curl do its I/O, then deliver what arrived
#'
#' libcurl refuses every multi API call made from inside its own callbacks
#' (`curl::multi_cancel()`, `curl::multi_add()` and `curl::multi_run()` signal "API function
#' called from within callback"; verified with curl 7.0.0). The callbacks handed to
#' `curl::multi_add()` therefore only queue events, and `reactor_deliver()` runs the
#' transfers' callbacks once `multi_run()` has returned: a stream cancelled or retried from
#' `on_bytes` really stops, and a callback may start transfers or pump the reactor.
#' @noRd
reactor_multi_run = function(r) {
  curl::multi_run(timeout = 0, pool = r$pool)
  for (id in reactor_active(r)) reactor_head(r, r$transfers[[id]])
  reactor_deliver(r)
  invisible(NULL)
}

#' Remove a handle from the pool (never called from inside curl::multi_run())
#' @noRd
reactor_curl_cancel = function(r, h) {
  if (!is.null(h)) try(curl::multi_cancel(h), silent = TRUE)
  invisible(NULL)
}

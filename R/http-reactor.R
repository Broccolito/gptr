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
  wait = reactor_wait_ms(r, allow_runs, slice_ms, t_end)
  pollables = reactor_pollables(r)
  if (length(pollables)) {
    processx::poll(pollables, as.integer(min(wait, .Machine$integer.max)))
  } else if (wait > 0) {
    Sys.sleep(wait / 1000)
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

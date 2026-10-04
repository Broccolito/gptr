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

#' Wait for the next event (this version has only timers, tasks and the FIFO to wait for)
#' @noRd
reactor_io = function(r, allow_runs, slice_ms, t_end) {
  wait = reactor_wait_ms(r, allow_runs, slice_ms, t_end)
  if (wait > 0) Sys.sleep(wait / 1000)
  invisible(NULL)
}

#' How long this iteration may wait, in milliseconds
#' @noRd
reactor_wait_ms = function(r, allow_runs, slice_ms, t_end) {
  if (reactor_fifo_ready(r, allow_runs)) return(0)
  now = reactor_now()
  at = min(t_end, reactor_next_due(r))
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

#' Cancel one id (this version knows timers, tasks and FIFO items)
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
  0L
}

#' Unload cleanup: forget all reactor state
#' @noRd
reactor_shutdown = function() {
  if (exists("reactor", envir = the, inherits = FALSE)) rm(list = "reactor", envir = the)
  invisible(NULL)
}

on_load(on_unload(reactor_shutdown))

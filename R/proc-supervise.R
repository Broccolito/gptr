# Supervision of child processes (P04; contract 7.4, IC-59, IC-60).
#
# - pid_alive(): ps liveness plus a creation-time comparison against pid reuse (IC-59); never
#   the tools package's pskill(), which on Windows always terminates the process.
# - Tree markers: every child started by proc_spawn() carries the environment variable
#   `GPTR_PROC_<16 hex>=YES`, recorded in memory and in
#   `R_user_dir("gptr", "cache")/procs/<marker>.json`. SIGTERM skips finalizers (verified for
#   IC-60) and grandchildren survive a SIGKILL of their parent (report 15 section 2.11), so the
#   next load of gptr runs proc_sweep(), which kills the trees whose gptr parent is gone.
# - kill_all(): report G5's kill recipe and its fact-check items 3-4: kill_tree() alone misses
#   SIP-protected binaries on macOS (their environment is unreadable), `$kill()` signals the
#   whole process group, and on Windows `taskkill /F /T /PID` must run while the parent lives.

#' The process and job tables (`the$jobs`, owned by P04; IC-12)
#' @noRd
jobs_env = function() {
  e = get0("jobs", envir = the, inherits = FALSE)
  if (is.null(e)) {
    e = new.env(parent = emptyenv())
    e$table = new.env(parent = emptyenv())
    e$order = character()
    e$procs = new.env(parent = emptyenv())
    e$handles = new.env(parent = emptyenv())
    e$self = NULL
    assign("jobs", e, envir = the)
  }
  e
}

#' Valid process identity fields and marker names (fail closed before OS operations)
#' @noRd
proc_pid_valid = function(pid) {
  is.numeric(pid) && length(pid) == 1L && is.finite(pid) && pid > 0 &&
    pid <= .Machine$integer.max && pid == floor(pid)
}

#' @noRd
proc_marker_valid = function(marker) {
  is.character(marker) && length(marker) == 1L && !is.na(marker) &&
    grepl("^GPTR_PROC_[0-9a-f]{16}$", marker)
}

#' @noRd
proc_time_valid = function(time) {
  identical(time, "NA") || (is.numeric(time) && length(time) == 1L && !is.nan(time) &&
    (is.na(time) || (is.finite(time) && time > 0)))
}

#' @noRd
proc_record_valid = function(rec, path) {
  is.list(rec) && proc_marker_valid(rec$marker) &&
    identical(basename(path), paste0(rec$marker, ".json")) &&
    proc_pid_valid(rec$pid) && proc_pid_valid(rec$parent_pid) &&
    rec$pid != rec$parent_pid && rec$pid != Sys.getpid() &&
    proc_time_valid(rec$create_time) && proc_time_valid(rec$parent_create)
}

#' Recognize process absence without interpreting an arbitrary OS error as death
#'
#' On Linux, ps_handle() can raise os_error/ENOENT from /proc/<pid>/stat instead of
#' no_such_process. Require a working independent PID inventory before accepting that
#' error: initialization can also fail while reading global procfs information.
#' @noRd
proc_error_absent = function(error, pid) {
  if (inherits(error, "no_such_process")) return(TRUE)
  if (!inherits(error, "ps_error") || !inherits(error, "os_error")) return(FALSE)
  code = error$errno
  codes = ps::errno()
  absent = codes$value[codes$name %in% c("ENOENT", "ESRCH")]
  if (!is.numeric(code) || length(code) != 1L || is.na(code) || !code %in% absent) return(FALSE)
  if (!proc_pid_valid(pid)) return(FALSE)
  pids = tryCatch(ps::ps_pids(), error = function(e) integer())
  is.numeric(pids) && all(vapply(pids, proc_pid_valid, logical(1))) &&
    Sys.getpid() %in% pids && !pid %in% pids
}

#' Read a handle without treating access failures as proof that a process is gone
#' @noRd
proc_handle_alive = function(handle) {
  if (is.null(handle)) return(NA)
  tryCatch(ps::ps_is_running(handle) && !identical(ps::ps_status(handle), "zombie"),
           error = function(e) {
             pid = tryCatch(ps::ps_pid(handle), error = function(e) NA_integer_)
             if (proc_error_absent(e, pid)) FALSE else NA
           })
}

#' Verify a recorded identity once, keeping the same handle for any later signal
#'
#' JSON timestamps can round by microseconds. Compare the saved value with the actual
#' handle's creation time with a 0.01-second tolerance; never create a handle with a rounded
#' timestamp, because ps compares handle identity exactly.
#' @noRd
proc_identity = function(pid, create_time = NULL) {
  handle = tryCatch(ps::ps_handle(as.integer(pid)), error = identity)
  if (inherits(handle, "condition")) {
    alive = if (proc_error_absent(handle, pid)) FALSE else NA
    return(list(handle = NULL, alive = alive))
  }
  want = suppressWarnings(as.numeric(create_time))
  if (length(want) == 1L && is.finite(want)) {
    actual = tryCatch(as.numeric(ps::ps_create_time(handle)), error = function(e) NA_real_)
    if (!is.finite(actual)) return(list(handle = handle, alive = NA))
    if (abs(actual - want) >= 0.01) return(list(handle = NULL, alive = FALSE))
  }
  list(handle = handle, alive = proc_handle_alive(handle))
}

#' Parent liveness for orphan decisions: uncertainty never authorizes cleanup
#' @noRd
proc_parent_alive = function(rec) proc_identity(rec$parent_pid, rec$parent_create)$alive

#' Creation time of a process in seconds since the epoch, or NA
#' @noRd
proc_create_time = function(pid) {
  if (!proc_pid_valid(pid)) return(NA_real_)
  h = tryCatch(ps::ps_handle(as.integer(pid)), error = function(e) NULL)
  if (is.null(h)) return(NA_real_)
  tryCatch(as.numeric(ps::ps_create_time(h)), error = function(e) NA_real_)
}

#' Is a process alive and, when `create_time` is given, the same process (pid reuse)?
#'
#' proc_identity(); zombies count as dead (IC-59). An unknown creation time (NULL, NA or the
#' marker file's "NA") is not compared, and an unknown state reads alive: locks stay held.
#' @param pid int(1)
#' @param create_time num(1) seconds since the epoch (a POSIXct is accepted), or NULL.
#' @return lgl(1)
#' @noRd
pid_alive = function(pid, create_time = NULL) {
  proc_pid_valid(pid) && !isFALSE(proc_identity(pid, create_time)$alive)
}

#' This R process: pid and creation time (cached)
#' @noRd
proc_self = function() {
  je = jobs_env()
  if (is.null(je$self)) {
    je$self = list(pid = Sys.getpid(), create_time = proc_create_time(Sys.getpid()))
  }
  je$self
}

#' The tree-marker directory, `R_user_dir("gptr", "cache")/procs`
#' @noRd
proc_dir = function(create = FALSE) {
  d = file.path(gptr_user_dir("cache", create = create), "procs")
  if (create && !dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

#' A fresh tree-marker variable name (RNG-free id)
#' @noRd
proc_marker_new = function() paste0("GPTR_PROC_", id_new("", 16L))

#' Record a spawned child in memory and as a marker file for the orphan sweep
#' @noRd
proc_mark = function(p, marker, command) {
  self = proc_self()
  pid = p$get_pid()
  rec = list(marker = marker, pid = pid, create_time = proc_create_time(pid),
             parent_pid = self$pid, parent_create = self$create_time,
             command = basename(command),
             started = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"))
  je = jobs_env()
  assign(marker, rec, envir = je$procs)
  assign(marker, p, envir = je$handles)
  path = file.path(proc_dir(create = TRUE), paste0(marker, ".json"))
  # Keep the original child in memory if persistence fails: proc_spawn() rolls it back.
  write_atomic(path, json_encode(rec))
  if (length(ls(je$procs)) > 32L) proc_prune()
  invisible(rec)
}

#' The marker record of a pid started by proc_spawn(), or NULL
#' @noRd
proc_record = function(pid, process = NULL) {
  if (!proc_pid_valid(pid)) return(NULL)
  je = jobs_env()
  for (m in ls(je$procs)) {
    rec = je$procs[[m]]
    same_handle = is.null(process) || identical(je$handles[[m]], process)
    if (identical(as.integer(rec$pid), as.integer(pid)) && same_handle) return(rec)
  }
  NULL
}

#' Forget a marker: drop the record and delete its file
#' @noRd
proc_unmark = function(marker) {
  if (!proc_marker_valid(marker)) return(invisible(FALSE))
  je = jobs_env()
  if (exists(marker, envir = je$procs, inherits = FALSE)) rm(list = marker, envir = je$procs)
  if (exists(marker, envir = je$handles, inherits = FALSE)) rm(list = marker, envir = je$handles)
  unlink(file.path(proc_dir(create = FALSE), paste0(marker, ".json")))
  invisible(TRUE)
}

#' Processes that still carry a marker (ps reads the environments of the user's processes)
#' @noRd
proc_tree = function(marker) {
  if (!proc_marker_valid(marker)) return(list())
  suppressWarnings(tryCatch(ps::ps_find_tree(marker), error = function(e) {
    structure(list(), unavailable = TRUE)
  }))
}

#' Release the marker of a child that exited, once no descendant carries it
#' @noRd
proc_release = function(p) {
  pid = tryCatch(p$get_pid(), error = function(e) NA_integer_)
  rec = proc_record(pid, process = p)
  if (is.null(rec)) return(invisible(FALSE))
  tree = proc_tree(rec$marker)
  if (!length(tree) && !isTRUE(attr(tree, "unavailable"))) proc_unmark(rec$marker)
  invisible(TRUE)
}

#' Drop the records of exited children whose trees are gone
#' @noRd
proc_prune = function() {
  je = jobs_env()
  for (m in ls(je$procs)) {
    tree = proc_tree(m)
    process = je$handles[[m]]
    dead = !is.null(process) && isFALSE(tryCatch(process$is_alive(), error = function(e) NA))
    if (dead && !length(tree) && !isTRUE(attr(tree, "unavailable"))) proc_unmark(m)
  }
  invisible(NULL)
}

#' The orphan sweep: kill the trees of markers whose gptr parent process is gone
#'
#' Runs at every load of gptr (IC-60: SIGTERM skips finalizers, so only the next load can
#' clean up). A marker whose parent is alive belongs to another live R session and is left
#' alone. Besides the processes found by their marker, the recorded child itself is killed
#' when it is provably still the same process (its recorded creation time is known and equal),
#' which also covers binaries whose environment ps cannot read (macOS system binaries; report
#' G5 fact-check 3). A record without a creation time is never killed by pid: after a crash
#' the pid may belong to an unrelated process by the next load.
#' @return invisible(int(1)) the number of processes killed
#' @noRd
proc_sweep = function() {
  d = proc_dir(create = FALSE)
  if (!dir.exists(d)) return(invisible(0L))
  killed = 0L
  files = list.files(d, pattern = "^GPTR_PROC_[0-9a-f]{16}[.]json$", full.names = TRUE)
  for (path in files) {
    rec = tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
    if (!proc_record_valid(rec, path)) {
      unlink(path)
      next
    }
    if (!isFALSE(proc_parent_alive(rec))) next
    result = tryCatch(proc_cleanup_record(rec), error = function(e) list(killed = 0L))
    killed = killed + result$killed
  }
  invisible(killed)
}

#' Wait, at most `seconds`, until none of the signalled processes reads as running
#'
#' On Windows ps_kill() calls TerminateProcess(), which returns before the process has exited
#' (on Unix ps_kill() sends SIGTERM and waits up to its grace period before SIGKILL), so a
#' process killed a moment ago can still read as running and still carry its marker. Only a
#' handle that reads as running is waited for: an unknown state (NA) is never waited on and stays
#' unknown.
#' @return invisible(lgl(1)) TRUE when none reads as running
#' @noRd
proc_wait_exit = function(handles, seconds = 2) {
  t_end = proc.time()[["elapsed"]] + seconds
  repeat {
    running = vapply(handles, function(h) isTRUE(proc_handle_alive(h)), logical(1))
    if (!any(running) || proc.time()[["elapsed"]] >= t_end) return(invisible(!any(running)))
    handles = handles[running]
    Sys.sleep(0.02)
  }
}

#' Kill handles with one ps_kill() call; returns the handles it signalled
#'
#' ps_kill() fails as a whole when one handle fails (access denied, say) and lists the per-handle
#' results in the condition's `results`: a character result means that handle was signalled (or
#' was already dead). A failure without per-handle results counts as no handle signalled.
#' @noRd
proc_kill_signalled = function(handles) {
  if (!length(handles)) return(list())
  ok = tryCatch({
    suppressWarnings(ps::ps_kill(handles))
    rep(TRUE, length(handles))
  }, error = function(e) {
    res = e$results
    if (!is.list(res) || length(res) != length(handles)) return(rep(FALSE, length(handles)))
    vapply(res, function(x) is.character(x) || is.null(x), logical(1))
  })
  handles[ok]
}

#' Clean one validated owned tree, retaining its recovery record until cleanup is confirmed
#' @noRd
proc_cleanup_record = function(rec) {
  tree = proc_tree(rec$marker)
  signalled = proc_kill_signalled(tree)
  killed = 0L
  ct = suppressWarnings(as.numeric(rec$create_time))
  known = length(ct) == 1L && is.finite(ct)
  child = if (known) proc_identity(rec$pid, ct) else list(handle = NULL, alive = NA)
  signal_child = known && isTRUE(child$alive)
  if (signal_child && !inherits(try(ps::ps_kill(child$handle), silent = TRUE), "try-error")) {
    signalled = c(signalled, list(child$handle))
  }
  # wait only for what was signalled: a failed kill (kept record) must not delay every load
  proc_wait_exit(signalled)
  if (signal_child) {
    child$alive = proc_handle_alive(child$handle)
    if (isFALSE(child$alive)) killed = killed + 1L
  }
  tree_killed = vapply(tree, function(h) isFALSE(proc_handle_alive(h)), logical(1))
  tree_pids = vapply(tree, function(h) tryCatch(ps::ps_pid(h), error = function(e) NA_integer_), 1L)
  if (rec$pid %in% tree_pids) killed = 0L
  killed = killed + sum(tree_killed)
  survivors = proc_tree(rec$marker)
  clear = !isTRUE(attr(survivors, "unavailable")) &&
    !any(vapply(survivors, function(h) !isFALSE(proc_handle_alive(h)), logical(1)))
  complete = clear && (!known || isFALSE(child$alive))
  if (complete) proc_unmark(rec$marker)
  list(killed = as.integer(killed), complete = complete)
}

#' Kill a child process and its whole tree
#'
#' Interrupt, wait `grace` seconds, `kill_tree()` (processx's marker) and gptr's marker, on
#' Windows `taskkill /F /T /PID` while the process still lives, then `$kill()` (the process
#' group on Unix); then wait at most 2 s for the process and those the tree kills signalled to
#' stop running, and the marker cleanup for those it signals itself (Windows `TerminateProcess()`
#' is asynchronous, and processx reads the exit code before the process is gone; D-019, D-180).
#' @param p a processx (or callr) process.
#' @param grace num(1) seconds to wait after the interrupt.
#' @return invisible(lgl(1)): TRUE when the process is gone
#' @noRd
kill_all = function(p, grace = 2) {
  if (is.null(p)) return(invisible(TRUE))
  pid = tryCatch(p$get_pid(), error = function(e) NA_integer_)
  if (isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))) {
    try(p$interrupt(), silent = TRUE)
    if (grace > 0) try(p$wait(as.integer(ceiling(grace * 1000))), silent = TRUE)
  }
  killed = tryCatch(p$kill_tree(), error = function(e) NULL)
  rec = proc_record(pid, process = p)
  if (!is.null(rec)) {
    killed = c(killed, suppressWarnings(tryCatch(ps::ps_kill_tree(rec$marker),
                                                 error = function(e) NULL)))
  }
  if (is_windows() && isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))) {
    tk = file.path(Sys.getenv("SystemRoot", "C:/Windows"), "System32", "taskkill.exe")
    try({
      k = processx::process$new(tk, c("/F", "/T", "/PID", as.character(pid)), stdout = NULL,
                                stderr = NULL, windows_hide_window = TRUE)
      k$wait(5000L)
    }, silent = TRUE)
  }
  try(p$kill(), silent = TRUE)
  proc_wait_exit(lapply(unique(c(pid, killed)), function(x) {
    tryCatch(ps::ps_handle(x), error = function(e) NULL)
  }))
  dead = isFALSE(tryCatch(p$is_alive(), error = function(e) NA))
  if (!is.null(rec)) {
    cleanup = proc_cleanup_record(rec)
    dead = isFALSE(tryCatch(p$is_alive(), error = function(e) NA)) && cleanup$complete
  }
  invisible(dead)
}

#' The size of a child-process pool: capped at 2 whenever R CMD check runs (IC-60)
#'
#' Pools of CLI children (P20), MCP stdio servers (P18), bridges (P22) and workers (P19) pass
#' their configured size through this helper.
#' @noRd
proc_pool_cap = function(n) {
  n = as.integer(n)
  if (check_running()) min(n, 2L) else n
}

on_load(proc_sweep())
# ---- the job table and gptr_jobs() (IC-12, IC-36, IC-60) -----------------------------------

#' The job kinds of the `gptr_jobs` listing (contract 5.12)
#' @noRd
job_kinds = c("session", "bg", "artifact", "mcp_serve", "worker", "cli")

#' Add a row to the job table
#'
#' @param kind one of `job_kinds`.
#' @param id,name chr(1) row id (unique; a second add replaces the row) and display name.
#' @param pid int(1) or NA.
#' @param stop zero-argument function. The stored stop also sets `stop_requested`, so a later
#'   non-zero exit reads `stopped` (`bg`, `artifact`, `mcp_serve`) or `aborted` (`session`,
#'   `worker`, `cli`), never `error` (IC-60).
#' @param status zero-argument function returning the current status string.
#' @return invisible(id)
#' @noRd
job_add = function(kind, id, name, pid = NA, stop, status = function() "running") {
  kind = check_choice(kind, job_kinds, "kind")
  check_string(id, "id")
  check_string(name, "name", empty = TRUE)
  check_function(stop, "stop")
  check_function(status, "status")
  missing_pid = (is.numeric(pid) || is.logical(pid)) && length(pid) == 1L && is.na(pid) &&
    !is.nan(pid)
  if (!missing_pid && !proc_pid_valid(pid)) {
    arg_abort(pid, "pid", "one positive integer PID or NA")
  }
  je = jobs_env()
  rec = new.env(parent = emptyenv())
  rec$id = id
  rec$kind = kind
  rec$name = name
  rec$pid = as.integer(pid)
  rec$started = Sys.time()
  rec$stop_requested = FALSE
  rec$status_fun = status
  stop_fun = stop
  rec$stop = function() {
    rec$stop_requested = TRUE
    stop_fun()
  }
  assign(id, rec, envir = je$table)
  je$order = c(setdiff(je$order, id), id)
  invisible(id)
}

#' Remove a row from the job table
#' @return invisible(lgl(1)) TRUE when the row existed
#' @noRd
job_remove = function(id) {
  check_string(id, "id")
  je = jobs_env()
  found = exists(id, envir = je$table, inherits = FALSE)
  if (found) rm(list = id, envir = je$table)
  je$order = setdiff(je$order, id)
  invisible(found)
}

#' The status of one job; a requested stop maps a finished job to `stopped` / `aborted`
#' @noRd
job_status = function(rec) {
  st = tryCatch(rec$status_fun(), error = function(e) "unknown")
  if (!is.character(st) || length(st) != 1L || is.na(st) || !nzchar(st)) st = "unknown"
  if (isTRUE(rec$stop_requested) && !st %in% c("running", "waiting", "unknown")) {
    st = if (rec$kind %in% c("artifact", "bg", "mcp_serve")) "stopped" else "aborted"
  }
  st
}

#' Job records as a data frame (`id`, `kind`, `name`, `pid`, `status`, `started`)
#' @noRd
job_frame = function(recs) {
  if (!length(recs)) {
    return(data.frame(id = character(), kind = character(), name = character(),
                      pid = integer(), status = character(),
                      started = as.POSIXct(character(), tz = "UTC"),
                      stringsAsFactors = FALSE))
  }
  data.frame(id = vapply(recs, function(r) r$id, ""),
             kind = vapply(recs, function(r) r$kind, ""),
             name = vapply(recs, function(r) r$name, ""),
             pid = vapply(recs, function(r) r$pid, 1L),
             status = vapply(recs, job_status, ""),
             started = do.call(c, lapply(recs, function(r) r$started)),
             stringsAsFactors = FALSE)
}

#' The job table as a data frame
#' @param kind NULL or chr of job kinds to keep.
#' @return df `id`, `kind`, `name`, `pid`, `status`, `started`
#' @noRd
job_list = function(kind = NULL) {
  je = jobs_env()
  ids = je$order[vapply(je$order, exists, NA, envir = je$table, inherits = FALSE)]
  recs = lapply(ids, function(id) je$table[[id]])
  if (!is.null(kind)) recs = Filter(function(r) r$kind %in% kind, recs)
  job_frame(recs)
}

#' List or stop gptr's background jobs and child processes
#'
#' Lists the job table of this R process: background sessions, `peter$bg()` jobs, Shiny
#' artifacts, the MCP server started by `gptr_mcp_serve()`, sub-agent workers and
#' subscription-CLI children. A finished job whose stop was requested reads `stopped` or
#' `aborted`, never `error`. Unavailable status information is shown as `unknown`.
#'
#' @param kill `TRUE` stops every job (sessions are canceled, processes are killed together
#'   with their process tree) and returns the table of what was stopped, invisibly.
#' @return A `gptr_jobs` data frame with the columns `id`, `kind` (`session`, `bg`,
#'   `artifact`, `mcp_serve`, `worker`, `cli`), `name`, `pid`, `status` and `started`.
#' @section Options:
#' Options of the transport and process layer (`?gptr_options` collects every option):
#'
#' - `gptr.max_active` (8): concurrent HTTP transfers (global).
#' - `gptr.connect_timeout` (20), `gptr.first_byte_timeout` (120), `gptr.idle_timeout` (90):
#'   seconds; there is no total timeout on streams.
#' - `gptr.max_retry_delay` (60): seconds; a longer `retry-after` fails fast.
#' - `gptr.max_attempts` (4): transport attempts per request.
#' - `gptr.wire_log` (`FALSE`): `TRUE` writes one redacted JSON line per request start and end
#'   to `<workspace root>/cache/tmp/wire-<session id>.jsonl`; a path must lie inside the
#'   workspace root or `tempdir()`.
#' - `gptr.supervise` (`NULL`): processx supervision of children; `NULL` means on, except under
#'   R CMD check.
#' - `gptr.stdin_timeout` (60): seconds a child may take to accept pending stdin bytes.
#' @export
#' @examples
#' gptr_jobs()
gptr_jobs = function(kill = FALSE) {
  check_flag(kill, "kill")
  if (!kill) return(new_listing(job_list(), "gptr_jobs"))
  je = jobs_env()
  recs = lapply(je$order, function(id) je$table[[id]])
  recs = Filter(Negate(is.null), recs)
  # stop functions may remove their own rows (P21), so the records are kept for the result
  for (rec in recs) try(rec$stop(), silent = TRUE)
  invisible(new_listing(job_frame(recs), "gptr_jobs"))
}

#' Unload cleanup: stop every job and kill the trees of every child this process spawned
#' @noRd
proc_unload = function() {
  je = jobs_env()
  for (id in je$order) {
    rec = je$table[[id]]
    if (!is.null(rec)) try(rec$stop(), silent = TRUE)
  }
  for (m in ls(je$procs)) {
    process = je$handles[[m]]
    if (!is.null(process)) {
      try(kill_all(process), silent = TRUE)
    } else {
      try(proc_cleanup_record(je$procs[[m]]), silent = TRUE)
    }
  }
  invisible(NULL)
}

on_load(on_unload(proc_unload))

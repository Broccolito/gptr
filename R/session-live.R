# session-live.R -- the live-session registry, homes, locks, split-brain rules and gptr_last()
# (P06, layer L3).
#
# Live resources (the kept home, the active run, the store handle, ctx, caches) are held in
# `the$live[[id]] = rlang::new_weakref(key = <shell>, value = <live>)`: an unreferenced, settled
# session is collected and its finalizer removes the entry and the file lock (G3 findings 2 and
# 10, verified). `the$last` holds the most recent session strongly (IC-71): a shell holds no frames
# or user objects, so this is copy-safe (rule R10). Locks are `<file>.lock/pid` holding the pid
# and the process creation time, checked with P04's `pid_alive()` (IC-59).

on_load({
  the$live = new.env(parent = emptyenv())
  the$last = NULL
  the$replay_blocks = new.env(parent = emptyenv())
})
on_load(on_unload(live_unload))

#' Create and register the live record of a session (04 section 5.1)
#' @noRd
live_new = function(s, home) {
  d = session_data(s)
  live = new.env(parent = emptyenv())
  live$home = if (!is.null(home) && home_keep(home)) home else NULL
  live$run = NULL
  live$listeners = list()
  live$store = NULL
  # the session's gptr_ctx: P02's ctx_new(s) reads the id through the `$id` accessor of the shell
  # and refuses a session whose id it cannot read, so the ctx is created once that accessor exists
  live$ctx = NULL
  live$memo = new.env(parent = emptyenv())
  live$adapter = new.env(parent = emptyenv())
  live$background = NULL
  live$lock = NULL
  # the session's gptr$out() store (IC-71): NULL until P01's out_store(live) creates it on the
  # first out_put(..., session = live); P01 accepts NULL or a gptr_out_store, never a bare env
  live$out = NULL
  live$mcp_token = NULL
  live$ext = new.env(parent = emptyenv())
  assign(d$id, rlang::new_weakref(key = s, value = live), envir = the$live)
  reg.finalizer(s, session_finalizer, onexit = TRUE)
  # the IC-70 late-registration scan reads live sessions through this callback (P03)
  secret_live_entries_set(live_entries_all)
  live
}

#' Undo the live registration of a fresh shell whose construction failed (store_rebuild() could
#' not open its store): the id is free again and the finalizer will neither release a lock nor
#' notify `session_shutdown` for it
#' @noRd
live_forget = function(s) {
  d = session_data(s)
  d$forgotten = TRUE
  w = get0(d$id, envir = the$live, inherits = FALSE)
  if (!is.null(w) && identical(rlang::wref_key(w), s)) rm(list = d$id, envir = the$live)
  invisible(NULL)
}

#' The live record of a session, or NULL for a detached copy
#' @noRd
session_live = function(s) {
  w = get0(session_data(s)$id, envir = the$live, inherits = FALSE)
  if (is.null(w)) return(NULL)
  k = rlang::wref_key(w)
  if (is.null(k) || !identical(k, s)) return(NULL)
  rlang::wref_value(w)
}

#' The kept home environment of a session, or NULL
#' @noRd
session_home = function(s) {
  live = session_live(s)
  if (is.null(live)) NULL else live$home
}

#' The live session object with this id, or NULL
#' @noRd
session_by_id = function(id) {
  if (is.null(id) || is.null(the$live)) return(NULL)
  w = get0(id, envir = the$live, inherits = FALSE)
  if (is.null(w)) return(NULL)
  rlang::wref_key(w)
}

#' Live sessions of this process, named by id
#' @noRd
live_all = function() {
  out = list()
  for (id in ls(the$live, all.names = TRUE)) {
    s = session_by_id(id)
    if (!is.null(s)) out[[id]] = s
  }
  out
}

#' The in-memory entries of the live sessions, named by id: the callback P03's secret_register()
#' scans for a newly registered value (IC-70, warning `secret_late`). P03's auth-secrets.R is L0
#' and may not read `the$live`, so the session layer installs it (03 section 2.2: callbacks
#' registered by upper layers); live_new() installs it again, so that a test that cleared P03's
#' slot cannot leave the scan inert for later sessions.
#' @noRd
live_entries_all = function() {
  lapply(live_all(), function(s) session_data(s)$entries %||% list())
}

on_load(secret_live_entries_set(live_entries_all))

#' Remember the most recently active session (a strong reference, IC-71)
#' @noRd
last_set = function(s) {
  the$last = s
  invisible(s)
}

#' The most recent session
#'
#' Returns the most recently active session of this R process. It is held strongly (it survives
#' `gc()`), so a session whose call was interrupted before its result was assigned is not lost.
#'
#' @return A `gptr_session`, or `NULL` when no session was created in this process.
#' @examples
#' s = gptr_last()
#' is.null(s) || inherits(s, "gptr_session")
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' identical(gptr_last(), s)
#' @export
gptr_last = function() the$last

#' May a session keep this environment as its home? Not a function frame on the stack (rule R2)
#' @noRd
home_keep = function(env) {
  if (identical(env, globalenv())) return(TRUE)
  k = sys.nframe()
  while (k > 0L) {
    if (identical(sys.frame(k), env)) return(FALSE)
    k = k - 1L
  }
  TRUE
}

#' A description of a home (a string, never the environment itself)
#' @noRd
home_label = function(env) {
  if (is.null(env)) return("<none>")
  if (identical(env, globalenv())) return("globalenv")
  ov = attr(env, "gptr_overlay", exact = TRUE)
  if (!is.null(ov)) return(ov)
  k = sys.nframe()
  while (k > 0L) {
    if (identical(sys.frame(k), env)) {
      fn = sys.call(k)[[1L]]
      return(paste0("frame of ", paste(deparse(fn, nlines = 1L), collapse = ""), "()"))
    }
    k = k - 1L
  }
  "<environment>"
}

#' Finalizer of a shell: drop the registry entry, release the lock, notify `session_shutdown`
#' (nothing for a shell whose registration was undone by live_forget())
#' @noRd
session_finalizer = function(s) {
  d = tryCatch(session_data(s), error = function(e) NULL)
  if (is.null(d) || isTRUE(d$forgotten)) return(invisible(NULL))
  w = get0(d$id, envir = the$live, inherits = FALSE)
  if (!is.null(w)) {
    k = rlang::wref_key(w)
    if (is.null(k) || identical(k, s)) rm(list = d$id, envir = the$live)
  }
  if (!is.null(d$file)) lock_release(lock_path(d$file))
  # dispatched with the session id (the shell is being finalised): P02's ev_dispatch() then drops
  # the session's rank-0 registry records after the handlers ran (IC-69)
  tryCatch(ev_dispatch("session_shutdown",
                       ev_new("session_shutdown", session = d$id, run = NULL, agent = "main",
                              turn = d$turns, reason = "gc"),
                       session = d$id),
           error = function(e) NULL)
  invisible(NULL)
}

#' At unload: release every live session's lock and notify `session_shutdown` (reason unload)
#' @noRd
live_unload = function() {
  for (s in live_all()) {
    d = session_data(s)
    if (!is.null(d$file)) lock_release(lock_path(d$file))
    live = session_live(s)
    tryCatch(ev_dispatch("session_shutdown",
                         ev_new("session_shutdown", session = d$id, run = NULL, agent = "main",
                                turn = d$turns, reason = "unload"),
                         session = s, ctx = live$ctx),
             error = function(e) NULL)
  }
  invisible(NULL)
}

#' Attach a detached copy (saveRDS, a knitr cache, callr) so that it can continue
#'
#' A same-process duplicate of a live original is `gptr_error_split_brain` (`busy` when the
#' original is running), after one `gc()` re-check; a copy whose file is locked by another live
#' process is `split_brain`; otherwise the copy continues from its own leaf and new entries form a
#' sibling branch in the same file (G3 finding 14).
#' @return The live record.
#' @noRd
session_attach = function(s, home = NULL) {
  live = session_live(s)
  if (!is.null(live)) return(live)
  d = session_data(s)
  other = session_by_id(d$id)
  if (!is.null(other)) {
    invisible(gc())
    other = session_by_id(d$id)
  }
  if (!is.null(other) && !identical(other, s)) {
    if (identical(session_data(other)$status, "running")) {
      gptr_abort(paste0("session ", d$id, " is running in this R process"), "busy", session = d$id)
    }
    gptr_abort(paste0("another live object for session ", d$id, " exists in this R process; use ",
                      "gptr_resume(\"", d$id, "\") to get it, or gptr_fork() to branch this copy"),
               "split_brain", id = d$id, holder_pid = Sys.getpid())
  }
  if (!is.null(d$file) && lock_held_elsewhere(d$file)) {
    h = lock_holder(lock_path(d$file))
    gptr_abort(paste0("session ", d$id, " is attached in another R process (pid ", h$pid,
                      "); use gptr_fork() to branch it"), "split_brain", id = d$id,
               holder_pid = h$pid)
  }
  if (identical(d$status, "running")) {
    d$status = "aborted"
    d$reason = "detached"
  }
  live = live_new(s, home)
  if (!is.null(d$file) && isTRUE(file.size(d$file) > 0)) {
    live$store = store_open(s)
    n_file = length(readLines(d$file, encoding = "UTF-8", warn = FALSE)) - 1L
    if (n_file > length(d$entries)) {
      gptr_inform(paste0("session ", d$id, ": continuing from this object's state (turn ",
                         d$turns, "); ", n_file - length(d$entries), " newer entries in the file ",
                         "stay as a sibling branch"), "notice")
    }
  }
  live
}

#' The lock directory of a session file
#' @noRd
lock_path = function(file) paste0(file, ".lock")

#' The creation time of this R process (seconds since the epoch). Not named proc_create_time(),
#' which is P04's `proc_create_time(pid)` in proc-supervise.R.
#' @noRd
lock_self_created = function() as.numeric(ps::ps_create_time(ps::ps_handle()))

#' Take the lock of a session file, or signal split brain when another live process holds it
#' @return The lock directory.
#' @noRd
lock_acquire = function(file) {
  dir = lock_path(file)
  if (!dir.create(dir, showWarnings = FALSE, recursive = TRUE)) {
    h = lock_holder(dir)
    if (!is.null(h) && !lock_is_mine(h) && lock_is_live(h)) {
      gptr_abort(paste0("the session file ", basename(file),
                        " is locked by another R process (pid ",
                        h$pid, ")"), "split_brain",
                 id = sub("^.*_", "", sub("[.]jsonl$", "", basename(file))), holder_pid = h$pid)
    }
  }
  write_atomic(file.path(dir, "pid"),
               c(as.character(Sys.getpid()), format(lock_self_created(), digits = 17)))
  dir
}

#' The holder of a lock: `list(pid, created, heartbeat)` or NULL
#' @noRd
lock_holder = function(dir) {
  f = file.path(dir, "pid")
  if (!file.exists(f)) return(NULL)
  x = tryCatch(readLines(f, encoding = "UTF-8", warn = FALSE), error = function(e) character())
  if (length(x) < 2L) return(NULL)
  list(pid = suppressWarnings(as.integer(x[[1L]])), created = suppressWarnings(as.numeric(x[[2L]])),
       heartbeat = as.numeric(file.mtime(f)))
}

#' Is a lock held by this process?
#' @noRd
lock_is_mine = function(h) {
  identical(h$pid, Sys.getpid()) && isTRUE(abs(h$created - lock_self_created()) < 0.01)
}

#' Is a lock's holder alive (pid and creation time) with a heartbeat younger than 24 h?
#' @noRd
lock_is_live = function(h) {
  if (is.na(h$pid)) return(FALSE)
  if (isTRUE(as.numeric(Sys.time()) - h$heartbeat > 24 * 3600)) return(FALSE)
  isTRUE(pid_alive(h$pid, .POSIXct(h$created, tz = "UTC")))
}

#' Is a session file locked by another live process?
#' @noRd
lock_held_elsewhere = function(file) {
  h = lock_holder(lock_path(file))
  !is.null(h) && !lock_is_mine(h) && lock_is_live(h)
}

#' Release a lock this process holds
#' @noRd
lock_release = function(dir) {
  h = lock_holder(dir)
  if (!is.null(h) && lock_is_mine(h)) unlink(dir, recursive = TRUE)
  invisible(TRUE)
}

# agent-background.R -- experimental background sessions (P21; contract 04 section 7.21, IC-57).
#
# peter(..., background = TRUE) returns a running session at once. A `later` timer pumps the
# process reactor while the console is idle: one non-blocking reactor iteration per tick, and
# nothing while a reactor pump is on the call stack (IC-57: reactor_depth() > 0).

#' The background pump state `the$bg` (owned by P21, 04 section 7.0), created on first use
#' @noRd
bg_state = function() {
  st = the$bg
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$sessions = new.env(parent = emptyenv())
    st$ticking = FALSE
    st$ticks = 0L
    the$bg = st
  }
  st
}

#' The background session with id `id`, or NULL
#' @noRd
bg_get = function(id) {
  if (!rlang::is_string(id) || !nzchar(id)) return(NULL)
  get0(id, envir = bg_state()$sessions, inherits = FALSE)
}

#' Is `id` a registered background session?
#' @noRd
bg_has = function(id) {
  !is.null(bg_get(id))
}

#' Ids of the registered background sessions, sorted
#' @noRd
bg_ids = function() {
  ls(bg_state()$sessions, sorted = TRUE)
}

#' Is an idle tick pumping the reactor right now?
#' @noRd
bg_ticking = function() {
  isTRUE(bg_state()$ticking)
}

#' An `until` function for reactor_pump() that allows exactly one non-blocking iteration
#' (the pump checks `until()` before each iteration)
#' @noRd
bg_once = function() {
  first = TRUE
  function() {
    if (!first) return(TRUE)
    first <<- FALSE
    FALSE
  }
}

#' The `gptr.background_tools` mode: "wait" or "idle" (anything else reads as "idle")
#' @noRd
bg_tools_mode = function() {
  if (identical(gptr_opt("background_tools"), "wait")) "wait" else "idle"
}

#' Replace C0/C1 controls, bidi and zero-width characters by spaces and invalid bytes by <xx>
#' (code points, so the result does not depend on the locale)
#' @noRd
bg_clean = function(x) {
  x = iconv(as_utf8(as.character(x)), "UTF-8", "UTF-8", sub = "byte")
  vapply(x, function(s) {
    if (is.na(s)) return("")
    cp = utf8ToInt(s)
    bad = cp < 32L | (cp >= 127L & cp <= 159L) | (cp >= 0x200bL & cp <= 0x200fL) |
      (cp >= 0x202aL & cp <= 0x202eL) | (cp >= 0x2066L & cp <= 0x2069L) | cp == 0xfeffL
    cp[bad] = 32L
    intToUtf8(cp)
  }, "", USE.NAMES = FALSE)
}

#' One line of at most `n` characters, whitespace collapsed, cut with an ASCII ellipsis
#' @noRd
bg_cut = function(x, n) {
  x = gsub("[[:space:]]+", " ", trimws(paste(bg_clean(x), collapse = " ")))
  if (nchar(x) > n) x = paste0(substr(x, 1L, n - 3L), "...")
  x
}

#' Object names for a notice: at most `max` names, then "and N more"
#' @noRd
bg_names_text = function(nm, max = 6L) {
  nm = unique(bg_clean(nm))
  nm = nm[nzchar(trimws(nm))]
  shown = paste(utils::head(nm, max), collapse = ", ")
  if (length(nm) > max) shown = paste0(shown, " and ", length(nm) - max, " more")
  shown
}

#' One line describing a permission request for the waiting notice
#' @noRd
bg_request_summary = function(request) {
  lines = bg_clean(c(request$summary, request$reason, "an action"))
  first = lines[nzchar(trimws(lines))][[1L]]
  bg_cut(paste0(request$tool %||% "tool", ": ", first), 100L)
}

#' The text the model reads when an ask could not be shown at an idle tick (IC-57): nothing ran,
#' nobody declined, and repeating the call later reaches the user
#' @noRd
bg_pending_text = function(what) {
  paste0("the user could not be asked for ", what, " because this session runs in the ",
         "background; the session now waits for the user, and when it continues, call the tool ",
         "again with the same input and the user will be asked")
}

#' Record that the background session `id` needs a human (the first ask wins). It runs inside the
#' dispatcher, so it never stops the run: the sweep after the tick does
#' @noRd
bg_park = function(id, what, summary) {
  s = bg_get(id)
  live = if (!is.null(s)) session_live(s)
  if (is.null(live$background)) return(invisible(FALSE))
  if (is.null(live$background$ask)) {
    live$background$ask = list(what = what, summary = bg_cut(summary, 100L))
  }
  invisible(TRUE)
}

#' The process-level `ui` record `name` that a session wrapper delegates to
#' @noRd
bg_ui_target = function(name) {
  registry_get("ui", name) %||%
    gptr_abort(paste0("The UI backend '", name, "' is no longer registered."), "not_available",
               member = name, provided_by = "P11")
}

#' A session-scoped wrapper of the `ui` record `name`: it delegates, but during an idle tick it
#' records the ask and answers without prompting. `permission()` answers a denial with the pending
#' text, never "abort" (P06 would tell the model that the user aborted the run)
#' @noRd
bg_ui_spec = function(name, id) {
  force(id)
  gptr_spec("ui", name,
    has_ui = function() isTRUE(bg_ui_target(name)$has_ui()),
    select = function(title, ...) {
      if (!bg_ticking()) return(bg_ui_target(name)$select(title, ...))
      bg_park(id, "select", title)
      NA_integer_
    },
    input = function(prompt, ...) {
      if (!bg_ticking()) return(bg_ui_target(name)$input(prompt, ...))
      bg_park(id, "input", prompt)
      NA_character_
    },
    questions = function(qs) {
      if (!bg_ticking()) return(bg_ui_target(name)$questions(qs))
      bg_park(id, "questions", "a question from the agent")
      list(answers = json_obj(), cancelled = TRUE)
    },
    notify = function(...) bg_ui_target(name)$notify(...),
    permission = function(request) {
      if (!bg_ticking()) return(bg_ui_target(name)$permission(request))
      bg_park(id, "permission", bg_request_summary(request))
      list(decision = "deny", remember = NULL, feedback = bg_pending_text("approval"))
    }
  )
}

#' Shadow every registered `ui` record with a wrapper for session `id`; returns the record ids
#' @noRd
bg_install_ui = function(id) {
  vapply(registry_names("ui"), function(nm) {
    registry_add(bg_ui_spec(nm, id), source = "session", rank = 0L, session = id)
  }, "", USE.NAMES = FALSE)
}

on_load(ext_declare_builtin("background", builtin_background))
on_load(ext_service_set("bg.register", bg_register, provided_by = "P21", builtin = "background"))
on_load(on_unload(bg_shutdown))

#' The `builtin:background` factory. Its hook is also the record that keeps the bootstrap service
#' `bg.register` visible (service_builtin_active(), IC-34)
#' @noRd
builtin_background = function(gptr) {
  gptr$on("tool_call", bg_on_tool_call, matcher = "ask")
}

#' `tool_call` hook (matcher "ask"): during an idle tick a background session's `ask` call is
#' blocked with the pending text and recorded, because a cancelled answer would tell the model
#' that the user dismissed the questions
#' @noRd
bg_on_tool_call = function(event, ctx) {
  if (!bg_ticking() || !bg_park(event$session, "questions", "a question from the agent")) {
    return(NULL)
  }
  list(decision = "block", reason = bg_pending_text("answers"))
}

#' Is the later package available?
#' @noRd
bg_has_later = function() {
  requireNamespace("later", quietly = TRUE)
}

#' Run a session in the background (service `bg.register`, 04 section 7.21) [experimental]
#'
#' A live run is marked background, an idle session with queued input is started in the
#' background, and anything else is refused.
#' @noRd
bg_register = function(s) {
  check_class(s, "gptr_session", "s")
  run = session_live(s)$run
  if (!bg_has_later()) {
    # a run that P08 started for the background would otherwise never be pumped
    if (isTRUE(run$opts$background)) run_abort(run, reason = "missing_package")
    gptr_abort(c("Background sessions need the 'later' package.",
                 "Install it with install.packages(\"later\")."),
               "missing_package", package = "later", feature = "background sessions")
  }
  if (is.null(run)) {
    q = session_data(s)$queue
    if (!length(c(q$steer, q$follow_up))) {
      gptr_abort("The session is not running and has no queued input to run in the background.",
                 "invalid_argument", arg = "s",
                 expected = "a running session or a session with queued input (.run = FALSE)")
    }
    run = run_start(s, NULL, opts = list(background = TRUE))
  }
  run$opts$background = TRUE
  bg_track(s, run)
  bg_ensure_pump()
  invisible(s)
}

#' The run options (04 section 7.6) a resumed background run keeps; never `call` (the caller's
#' frame, rule R2) or `safety` (snapshotted again at resume, IC-53)
#' @noRd
bg_run_opts = function(run) {
  o = run$opts[intersect(names(run$opts), c("max_turns", "budget", "returns", "context",
                                             "timeout", "preset", "tools", "root", "agent",
                                             "depth"))]
  o$background = TRUE
  o
}

#' Hold the session and record its live handle `list(ui, run, opts)` (ids and options only); the
#' first registration also adds the job row, installs the UI wrappers and prints the notice
#' @noRd
bg_track = function(s, run) {
  d = session_data(s)
  live = session_live(s)
  bg = live$background
  if (!bg_has(d$id)) {
    assign(d$id, s, envir = bg_state()$sessions)
    bg = list(ui = bg_install_ui(d$id))
    first = Filter(function(m) identical(m$role, "user"), path_messages(entries_path(d)))
    bg_job_add(d$id, bg_cut(if (length(first)) msg_text(first[[1L]]), 40L))
    gptr_inform(c("Background sessions are experimental.",
                  "See help(\"gptr-background\") for the consoles where they are supported."),
                "notice", .once = "background_experimental")
  }
  bg$run = run$id
  bg$ask = NULL
  bg$opts = bg_run_opts(run)
  live$background = bg
}

#' Add the `session` job row; its closures hold the id only, never the session (rule R1)
#' @noRd
bg_job_add = function(id, name) {
  job_add("session", id, name, stop = function() bg_stop(id), status = function() {
    s = bg_get(id)
    if (is.null(s)) "done" else session_data(s)$status
  })
}

#' Stop a background session (the job row's `stop`, gptr_jobs(kill = TRUE))
#' @noRd
bg_stop = function(id) {
  s = bg_get(id)
  run = if (!is.null(s)) session_live(s)$run
  if (!is.null(run)) run_abort(run)
  bg_release(id)
}

#' Forget a background session: UI wrappers, live handle, job row, strong reference; with
#' `notice`, tell the idle console how it settled
#' @noRd
bg_release = function(id, notice = FALSE) {
  s = bg_get(id)
  if (is.null(s)) return(invisible(FALSE))
  live = session_live(s)
  if (!is.null(live)) {
    for (rid in live$background$ui) registry_remove(rid)
    live$background = NULL
  }
  job_remove(id)
  rm(list = id, envir = bg_state()$sessions)
  if (notice) {
    d = session_data(s)
    why = if (length(d$reason) && nzchar(d$reason)) paste0(": ", bg_cut(d$reason, 120L))
    gptr_inform(paste0("Background session ", id, " finished with status ", d$status, why, "."),
                "notice")
  }
  invisible(TRUE)
}

#' Unload cleanup (registered with on_unload()): cancel the timer, stop every background session
#' @noRd
bg_shutdown = function() {
  st = the$bg
  if (is.null(st)) return(invisible(NULL))
  if (!is.null(st$cancel)) st$cancel()
  for (id in bg_ids()) try(bg_stop(id), silent = TRUE)
  the$bg = NULL
  invisible(NULL)
}

#' Arm the 50 ms later timer when background sessions exist and none is armed. Never creates
#' `the$bg`: a callback that fires after bg_shutdown() must not revive the state
#' @noRd
bg_ensure_pump = function() {
  st = the$bg
  if (is.null(st) || !is.null(st$cancel) || !length(ls(st$sessions))) return(invisible(FALSE))
  st$cancel = later::later(bg_callback, 0.05)
  invisible(TRUE)
}

#' Evaluate `expr`; an error becomes a `builtin:background` diagnostic (later::run_now() would
#' re-raise it at the console)
#' @noRd
bg_guard = function(event, expr) {
  tryCatch(expr, error = function(e) {
    registry_diagnostic("builtin:background", event, class(e)[1L], conditionMessage(e))
    invisible(NULL)
  })
}

#' The later callback: an idle tick, or bookkeeping only while a reactor pump is on the stack
#' (IC-57). It re-arms on exit, even after an interrupt, and guards tick and sweep separately, so
#' a failing tick never skips the sweep that stops a run with a recorded ask
#' @noRd
bg_callback = function() {
  st = bg_state()
  pending = st$cancel
  st$cancel = NULL
  # a manual call must not leave two timer chains
  if (!is.null(pending)) pending()
  on.exit(bg_ensure_pump(), add = TRUE)
  idle = reactor_depth() == 0L
  if (idle) bg_guard("tick", bg_tick())
  bg_guard("sweep", bg_sweep(idle))
  invisible(NULL)
}

#' Live runs of the background sessions (a session with a recorded ask is not ticked again)
#' @noRd
bg_runs = function() {
  out = list()
  for (id in bg_ids()) {
    live = session_live(bg_get(id))
    if (!is.null(live$run) && is.null(live$background$ask)) out[[length(out) + 1L]] = live$run
  }
  out
}

#' One idle tick: one non-blocking reactor iteration under the console interrupt policy (P14) in
#' "repl" mode, else abort-only. Explicit `allow_runs` keep the tools of other (suspended
#' foreground) runs queued
#' @noRd
bg_tick = function() {
  runs = bg_runs()
  if (!length(runs)) return(invisible(FALSE))
  st = bg_state()
  allow = character()
  if (identical(bg_tools_mode(), "idle")) allow = vapply(runs, function(r) r$id, "")
  st$ticking = TRUE
  on.exit({
    st$ticking = FALSE
  }, add = TRUE)
  st$ticks = st$ticks + 1L
  pump = function() reactor_pump(until = bg_once(), slice_ms = 0L, allow_runs = allow)
  if (ext_service_has("console.interrupt_policy")) {
    ext_service_get("console.interrupt_policy")(pump, runs, mode = "repl")
  } else {
    tryCatch(pump(), interrupt = function(cnd) for (run in runs) run_abort(run, reason = "user"))
  }
  invisible(TRUE)
}

#' Bookkeeping after a tick or inside a blocking pump: stop the runs of sessions with a recorded
#' ask (never retried at the next tick), release settled sessions
#' @noRd
bg_sweep = function(idle) {
  for (id in bg_ids()) {
    live = session_live(bg_get(id))
    if (!is.null(live$run) && !is.null(live$background$ask)) {
      run_abort(live$run, reason = "waiting")
    }
    if (is.null(live$run)) bg_release(id, notice = idle)
  }
  invisible(NULL)
}

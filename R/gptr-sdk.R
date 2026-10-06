# gptr-sdk.R -- the session SDK verbs gptr_step(), gptr_wait(), gptr_steer(), gptr_cancel(),
# gptr_on() and the agent-side gptr_return() (contract 6.5, 6.6; G1 section 4.6; IC-48, IC-53,
# IC-55). Every verb takes the session first so it composes with |>. Plan P08, layer L6.

#' The unsettled run of a session, or NULL
#' @noRd
sdk_run_of = function(s) {
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  if (is.null(run) || run_settled(run)) NULL else run
}

#' TRUE when a session has queued input (a steer or a follow-up)
#' @noRd
sdk_queued = function(s) {
  q = session_data(s)$queue
  length(q$steer) > 0L || length(q$follow_up) > 0L
}

#' Checks before starting a session's queued input: list(run) when running, NULL when nothing is
#' queued, else list(cur, safety). A root run's safety record is taken once, here (07 section 5),
#' and the guards run under it; a refusal leaves the pending call in place and starts nothing.
#' @noRd
sdk_check = function(s) {
  run = sdk_run_of(s)
  if (!is.null(run)) return(list(run = run))
  if (!sdk_queued(s)) return(NULL)
  cur = run_current()
  safety = gateway_run_safety(cur)
  pending = get0(session_data(s)$id, envir = gateway_state()$pending, inherits = FALSE)
  gateway_guards(pending$call, s, safety %||% egress_safety())
  list(cur = cur, safety = safety)
}

#' Starts the queued input sdk_check() cleared (`chk`) and returns the run, or the unsettled run
#' of a running session; NULL when nothing is queued. Without pending run options, a session
#' without a kept home evaluates in `envir`, held until the run settles (rule R2).
#' @noRd
sdk_launch = function(s, chk, envir = NULL) {
  if (is.null(chk)) return(NULL)
  run = chk$run %||% sdk_run_of(s)
  if (!is.null(run)) return(run)
  if (!sdk_queued(s)) return(NULL)
  opts = gateway_pending_take(session_data(s)$id)
  if (is.null(opts)) {
    opts = list()
    if (is.null(session_home(s)) && is.environment(envir)) {
      call = call_new(envir = unmask_env(envir), args = list(run = TRUE))
      call_hold(call, s)
      opts$call = call
    }
  }
  gateway_run_start(s, NULL, opts, chk$cur, chk$safety)
}

#' Starts the queued input of an idle session and returns the run (sdk_check(), sdk_launch())
#' @noRd
sdk_start = function(s, envir = NULL) sdk_launch(s, sdk_check(s), envir)

#' A session listener counting `turn_end` events; returns list(n = function, off = function)
#' @noRd
sdk_turn_counter = function(s) {
  box = new.env(parent = emptyenv())
  box$n = 0L
  id = hook_add("turn_end", function(event, ctx) {
    box$n = box$n + 1L
    NULL
  }, rank = 0L, source = "session", session = session_data(s)$id)
  list(n = function() box$n, off = function() invisible(hook_remove(id)))
}

#' The stop condition of gptr_step(): `turns` turn_end events, or the run settled
#' @noRd
sdk_until_turns = function(run, counter, turns) {
  force(run)
  force(counter)
  force(turns)
  function() counter$n() >= turns || run_settled(run)
}

#' The stop condition of gptr_wait(): no session is running or waiting (P21 resumes `waiting`)
#' @noRd
sdk_until_settled = function(ss) {
  force(ss)
  function() {
    all(vapply(ss, function(s) !session_data(s)$status %in% c("running", "waiting"), NA))
  }
}

#' Checks a session or a list of sessions; returns the list
#' @noRd
sdk_sessions = function(x, arg = "x") {
  ss = if (inherits(x, "gptr_session")) list(x) else x
  ok = is.list(ss) && !inherits(ss, "gptr_session") && length(ss) > 0L &&
    all(vapply(ss, inherits, NA, what = "gptr_session"))
  if (!ok) {
    gptr_abort(paste0("`", arg, "` must be a gptr session or a list of sessions."),
               "invalid_argument", arg = arg, expected = "a gptr_session or a list of them")
  }
  ss
}

#' The IC-53 control check of a verb acting on sessions: one check (one token) per call, made when
#' any of them is not the running session
#' @noRd
sdk_control_other = function(ss, what) {
  cur = run_current()
  if (is.null(cur)) return(invisible(TRUE))
  for (s in ss) {
    if (!identical(cur$session, session_data(s)$id)) return(gateway_control_other(s, what))
  }
  invisible(TRUE)
}

#' Advance a session
#'
#' Starts the queued input of an idle session (built with `.run = FALSE`, or given a follow-up
#' with [gptr_steer()]) and pumps it until `turns` model turns have ended or the run settles. A
#' running session is advanced the same way.
#'
#' @param s A session.
#' @param turns The number of turns to advance (`Inf` for all).
#' @return `s`, invisibly. A run that settles in status `error`, `blocked`, `budget` or
#'   `max_turns` signals the condition documented in [peter()].
#' @examples
#' s = peter("Plan the analysis", model = gptr_fake_provider(list("Plan: ...")), .run = FALSE,
#'          envir = new.env())
#' gptr_step(s)
#' s$turns
#' @export
gptr_step = function(s, turns = 1L) {
  check_class(s, "gptr_session", "s")
  check_number(turns, "turns", min = 1)
  if (is.finite(turns) && turns != round(turns)) {
    gptr_abort("`turns` must be a whole number of turns or Inf.", "invalid_argument",
               arg = "turns", expected = "an integer >= 1 or Inf")
  }
  run = sdk_start(s, parent.frame())
  if (is.null(run)) return(invisible(s))
  counter = sdk_turn_counter(s)
  on.exit(counter$off(), add = TRUE)
  sdk_pump(list(run), until = sdk_until_turns(run, counter, turns))
  if (run_settled(run)) gateway_signal(s, run)
  invisible(s)
}

#' Wait for sessions to settle
#'
#' Starts idle sessions that have queued input, then pumps until no session is running or
#' waiting, or `timeout` seconds have passed. Every session's egress and replay checks pass before
#' any is started, so a refusal starts none. On timeout the sessions keep their `running` status
#' and no condition is raised.
#'
#' @param x A session or a list of sessions (a team or fan-out session counts as one).
#' @param timeout Seconds to wait.
#' @return `x`, invisibly. For a single session, a terminal status signals its condition.
#' @examples
#' fake = gptr_fake_provider(list("a"))
#' runs = list(a = peter("one", model = fake, .run = FALSE, envir = new.env()),
#'             b = peter("two", model = fake, .run = FALSE, envir = new.env()))
#' gptr_wait(runs, timeout = 10)
#' vapply(runs, function(x) x$status, "")
#' @export
gptr_wait = function(x, timeout = Inf) {
  ss = sdk_sessions(x)
  check_number(timeout, "timeout", min = 0)
  caller = parent.frame()
  # every session is checked before any is started, so a refusal (egress, replay) starts none
  chks = vector("list", length(ss))
  i = 0L
  while (i < length(ss)) {
    i = i + 1L
    chk = sdk_check(ss[[i]])
    if (!is.null(chk)) chks[[i]] = chk
  }
  runs = list()
  i = 0L
  while (i < length(ss)) {
    i = i + 1L
    r = sdk_launch(ss[[i]], chks[[i]], caller)
    if (!is.null(r)) runs = c(runs, list(r))
  }
  until = sdk_until_settled(ss)
  if (!until()) sdk_pump(runs, until = until, timeout = timeout)
  if (inherits(x, "gptr_session") && length(runs) && run_settled(runs[[1L]])) {
    gateway_signal(x, runs[[1L]])
  }
  invisible(x)
}

#' Steer a session
#'
#' The one enqueue function behind the pipe into a running session, the pause menu and
#' `ctx$send()`. A steer reaches the model after the current tool results, as "The user sent this
#' message while you were working: ..."; a follow-up when the agent would otherwise stop. On an
#' idle session the item is taken when the next run starts.
#'
#' @param s A session.
#' @param text The message (secrets are redacted before it is queued).
#' @param as `"steer"` or `"follow_up"`.
#' @return `s`, invisibly, at once.
#' @examples
#' s = peter("Summarise mtcars", model = gptr_fake_provider(list("ok")), .run = FALSE,
#'          envir = new.env())
#' gptr_steer(s, "Use only the mpg column", as = "follow_up")
#' @export
gptr_steer = function(s, text, as = c("steer", "follow_up")) {
  check_class(s, "gptr_session", "s")
  check_string(text, "text")
  kind = check_choice(as, c("steer", "follow_up"), "as")
  gateway_control_other(s, "gptr_steer")
  session_enqueue(s, redact(as_utf8(text), "context"), as = kind, source = "api_user")
  invisible(s)
}

#' Cancel running sessions
#'
#' Aborts the run of a session (or of each session in a list): transfers are cancelled, child
#' processes stopped, the partial turn recorded as aborted, queued items moved to `dropped`, and
#' the status set to `aborted`. Idle sessions are left alone.
#'
#' @param x A session or a list of sessions.
#' @return `x`, invisibly.
#' @examples
#' s = peter("long task", model = gptr_fake_provider(list(list(hang = TRUE))), .run = FALSE,
#'          envir = new.env())
#' gptr_cancel(s)
#' @export
gptr_cancel = function(x) {
  ss = sdk_sessions(x)
  sdk_control_other(ss, "gptr_cancel")
  for (s in ss) {
    r = sdk_run_of(s)
    if (!is.null(r)) run_abort(r, reason = "user")
  }
  invisible(x)
}

#' Listen to a session's events
#'
#' Registers a session-scoped hook (rank 0) for one catalogued event (such as `message_end`,
#' `tool_call`, `turn_end`) or a plugin channel containing `:`. The handler is
#' `function(event, ctx)` and returns what the event allows. Forks never copy listeners.
#'
#' @param s A session.
#' @param event An event name; Claude and Codex hook names are refused with the gptr name.
#' @param handler `function(event, ctx)`.
#' @param matcher `NULL`, a tool-name glob for tool events, or `function(event)` returning a flag.
#' @return A function of no arguments that removes the hook, invisibly.
#' @examples
#' s = peter("hi", model = gptr_fake_provider(list("hello")), .run = FALSE, envir = new.env())
#' log = new.env()
#' log$roles = character()
#' off = gptr_on(s, "message_end", function(event, ctx) {
#'   log$roles = c(log$roles, event$message$role)
#'   NULL
#' })
#' gptr_step(s)
#' off()
#' log$roles
#' @export
gptr_on = function(s, event, handler, matcher = NULL) {
  check_class(s, "gptr_session", "s")
  check_string(event, "event")
  check_function(handler, "handler")
  if (!is.null(matcher) && !is.function(matcher)) check_string(matcher, "matcher")
  control_check("gptr_on")
  id = hook_add(event, handler, matcher = matcher, rank = 0L, source = "session",
                session = session_data(s)$id)
  invisible(sdk_off(id))
}

#' The remover returned by gptr_on()
#' @noRd
sdk_off = function(id) {
  force(id)
  function() invisible(hook_remove(id))
}

#' Designate the result of an agent run
#'
#' Called by R code the agent runs (or by you inside a tool) to designate the run's result, which
#' the session then returns as `$value`. Objects bound in the session's workspace are kept by name
#' when large (no copy), copied when small; other values are boxed. Outside a run it returns its
#' argument invisibly and does nothing else, so recorded code that still contains the call runs
#' cleanly.
#'
#' @param x The value; a bare name is recorded by name.
#' @return `NULL` invisibly during a run; `x` invisibly outside a run.
#' @examples
#' y = gptr_return(1:3)
#' y
#' @export
gptr_return = function(x) {
  run = run_current()
  if (is.null(run)) {
    if (!identical(replay_mode(), "replay")) {
      gptr_inform(paste("gptr_return() only designates a value while an agent runs;",
                        "here it returns its argument."),
                  "notice", .once = "gptr_return_outside_run")
    }
    return(invisible(x))
  }
  expr = substitute(x)
  s = gateway_session_by_id(run$session)
  if (is.null(s)) {
    gptr_abort("The running session is not registered in this process.", "internal",
               detail = "gptr_return() without a live session")
  }
  name = if (is.symbol(expr)) as.character(expr) else NULL
  session_value_set(s, ident_label(expr), x, name = name)
  invisible(NULL)
}

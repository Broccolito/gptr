# console-interrupt.R -- the interrupt policy of every blocking gptr call (P14, layer L5, area
# console; INFRA-03, architecture 6.2, contract 7.14), the `console.interrupt_policy` service.
# Report 18 sections 2.2.2 and 4.6 with G3's menu fixes: Ctrl-C opens a pause menu on stderr (it
# may run inside a tool's stdout capture) that resumes through R's `resume` restart; only the
# outermost policy has handlers, so none sits between the menu and the interrupted code.

#' Run `expr_fun()` under the console interrupt policy
#'
#' @param expr_fun Zero-argument function doing the blocking work (a reactor pump).
#' @param runs List of the `gptr_run` objects this call waits for.
#' @param mode `"call"` re-signals the interrupt after an abort; `"repl"` returns `NULL`.
#' @return The value of `expr_fun()`, or `NULL` after an abort in mode `"repl"`.
#' @noRd
with_interrupt_policy = function(expr_fun, runs, mode = c("call", "repl")) {
  check_function(expr_fun, "expr_fun")
  check_list(runs, "runs")
  mode = check_choice(mode, c("call", "repl"), "mode")
  outer = policy_find()
  if (!is.null(outer)) {
    n0 = length(outer$runs)
    outer$runs = c(outer$runs, runs)
    on.exit({
      outer$runs = outer$runs[seq_len(n0)]
    }, add = TRUE)
    return(expr_fun())
  }
  pol = new.env(parent = emptyenv())
  pol$runs = runs
  pol$mode = mode
  .gptr_interrupt_policy = pol
  force(.gptr_interrupt_policy)
  tryCatch(
    withCallingHandlers(expr_fun(), interrupt = function(cnd) policy_menu(cnd, pol)),
    interrupt = function(cnd) policy_abort(cnd, pol)
  )
}

on_load(ext_service_set("console.interrupt_policy", with_interrupt_policy,
                        provided_by = "P14", builtin = "console"))

#' The outermost policy on the call stack below the innermost console barrier, or NULL
#'
#' The REPL binds `.gptr_interrupt_barrier` around each prompt, so the policy of a prompt's run
#' is the outermost one there. Frames are walked with sys.frame(k), never sys.frames() (G3 rule 6).
#' @noRd
policy_find = function() {
  k = sys.nframe() - 1L
  found = NULL
  while (k >= 1L) {
    env = sys.frame(k)
    found = get0(".gptr_interrupt_policy", envir = env, inherits = FALSE) %||% found
    if (isTRUE(get0(".gptr_interrupt_barrier", envir = env, inherits = FALSE))) break
    k = k - 1L
  }
  found
}

#' Is a run still active? (04 section 7.6 statuses before settlement)
#' @noRd
policy_active = function(run) {
  isTRUE(run$status %in% c("queued", "requesting", "streaming", "tools", "boundary"))
}

#' The active runs among `runs` with their sessions (NULL when the console state has no record)
#' @noRd
policy_targets = function(runs) {
  active = console_state()$active
  lapply(Filter(policy_active, runs), function(r) {
    list(run = r, session = get0(r$id, envir = active, inherits = FALSE)$session)
  })
}

#' Whether the pause menu can be offered here (else the policy is abort-only)
#'
#' Needs someone to answer (IC-43) and a console where resuming an interrupt is verified:
#' terminal R, also inside VS Code (03 section 6.2, report 18 section 2.1.6).
#' @noRd
console_menu_available = function() {
  isTRUE(gptr_can_prompt()) && front_end() %in% c("terminal", "vscode", "unknown")
}

#' The innermost console REPL state on the call stack (a frame binding `.gptr_repl`), or NULL
#'
#' The REPL and the `jsonl` frontend bind their state under this name, so the pause menu, the
#' slash commands and the context-block providers find it without package state.
#' @noRd
console_repl_find = function() {
  k = sys.nframe() - 1L
  while (k >= 1L) {
    rs = get0(".gptr_repl", envir = sys.frame(k), inherits = FALSE)
    if (is.environment(rs)) return(rs)
    k = k - 1L
  }
  NULL
}

#' Read one menu answer: from a `.stdin` REPL's connection, else gptr_readline(); a Ctrl-C while
#' waiting (no resume restart there) gives NA
#' @noRd
console_ask = function(prompt) {
  rs = console_repl_find()
  tryCatch({
    x = if (isTRUE(rs$stdin) && !is.null(rs$reader)) {
      rs$reader$read(prompt, stream = "stderr")
    } else {
      gptr_readline(prompt)
    }
    if (length(x) != 1L || is.na(x)) NA_character_ else as_utf8(x)
  }, interrupt = function(e) NA_character_)
}

#' The pause menu (calling handler for `interrupt`): resumes the interrupted computation, or
#' returns to let the policy's exiting handler abort
#' @noRd
policy_menu = function(cnd, pol) {
  # nested policies drop their runs while the stack unwinds to the exiting handler
  pol$abort_runs = pol$runs
  if (is.null(findRestart("resume", cnd)) || !console_menu_available()) return(invisible(NULL))
  console_render_pause()
  target = Find(function(t) !is.null(t$session), policy_targets(pol$runs))
  s = target$session
  bg = !is.null(s) && identical(pol$mode, "call") && ext_service_has("bg.register") &&
    !isTRUE(target$run$opts$background)
  choices = if (is.null(s)) {
    "[c]ontinue, [a]bort"
  } else {
    paste0("[s]teer, [f]ollow-up, [c]ontinue, [a]bort", if (bg) ", [b]ackground")
  }
  who = if (is.null(s)) "" else paste0(" ", session_data(s)$id)
  repeat {
    console_notice("[gptr] paused", who, ": ", choices)
    ans = console_ask("? ")
    key = if (is.na(ans)) "a" else tolower(substr(trimws(ans), 1L, 1L))
    if (key %in% c("", "c")) {
      console_notice("[gptr] continuing")
      console_render_resume(pol$runs)
      invokeRestart("resume")
    }
    if (identical(key, "a")) return(invisible(NULL))
    if (!is.null(s) && key %in% c("s", "f")) {
      text = console_ask(if (identical(key, "s")) "steer> " else "follow-up> ")
      if (is.na(text)) return(invisible(NULL))
      policy_enqueue(s, text, if (identical(key, "s")) "steer" else "follow_up")
      console_render_resume(pol$runs)
      invokeRestart("resume")
    }
    if (bg && identical(key, "b")) {
      tryCatch({
        ext_service_get("bg.register")(s)
        console_notice("[gptr] running in the background; gptr_wait() brings it back")
        invokeRestart("resume")
      }, error = function(e) {
        console_notice("[gptr] cannot run in the background: ",
                       console_escape(conditionMessage(e), FALSE))
      })
      next
    }
    console_notice("[gptr] please answer with one of the letters shown")
  }
}

#' Queue pause-menu text on the session (IC-49, IC-55: source "pause_menu") after the `input`
#' event (source "steer")
#'
#' P06 refuses an enqueue from the session's own tool frames, which are on the stack when the
#' interrupt hit a tool; the item then waits in the console state for policy_flush().
#' @noRd
policy_enqueue = function(s, text, as) {
  text = as_utf8(text)
  if (!nzchar(trimws(text))) {
    console_notice("[gptr] nothing queued; continuing")
    return(invisible(FALSE))
  }
  ev = ev_dispatch("input", ev_new("input", text = text, source = "steer"), session = s)
  if (identical(ev$action, "handled")) return(invisible(FALSE))
  console_notice(if (identical(as, "steer")) {
    "[gptr] steering message queued; it is delivered after the current tool results"
  } else {
    "[gptr] follow-up queued; it is sent when the agent would stop"
  })
  st = console_state()
  st$pending = c(st$pending, list(list(s = s, text = ev$text, as = as, run = session_live(s)$run)))
  policy_flush()
  if (length(st$pending)) reactor_timer(at = reactor_now(), fn = policy_flush)
  invisible(TRUE)
}

#' Queue the pending pause-menu items once no tool executes on the stack: at the next reactor
#' step or when the tool ends (the tool_execution_end hook), so before the next request
#' (INFRA-12); an item whose run settled first is listed as dropped (03 section 6.2)
#' @noRd
policy_flush = function() {
  st = console_state()
  if (!length(st$pending) || !is.null(run_current())) return(invisible(NULL))
  items = st$pending
  st$pending = NULL
  for (it in items) {
    if (!is.null(it$run) && !policy_active(it$run)) {
      console_notice("[gptr] dropped queued messages: ",
                     console_escape(paste0("'", it$text, "'"), FALSE))
    } else {
      tryCatch(session_enqueue(it$s, it$text, as = it$as, source = "pause_menu"),
               error = function(e) {
                 console_notice("[gptr] the queued message could not be delivered: ",
                                console_escape(conditionMessage(e), FALSE))
               })
    }
  }
  invisible(NULL)
}

#' Abort (exiting handler for `interrupt`): abort the runs present at the interrupt, list the
#' queue items they dropped and, in mode "call", re-signal the interrupt
#' @noRd
policy_abort = function(cnd, pol) {
  targets = policy_targets(pol$abort_runs %||% pol$runs)
  sessions = Filter(Negate(is.null), lapply(targets, function(t) t$session))
  n0 = vapply(sessions, function(s) length(session_data(s)$dropped), 0L)
  suspendInterrupts({
    for (t in rev(targets)) if (policy_active(t$run)) run_abort(t$run, reason = "user")
  })
  console_render_pause()
  console_notice("[gptr] aborted; the session is kept.")
  for (i in seq_along(sessions)) {
    dropped = session_data(sessions[[i]])$dropped
    texts = vapply(dropped[seq_along(dropped) > n0[[i]]], function(item) item$text, "")
    if (length(texts)) {
      console_notice("[gptr] dropped queued messages: ",
                     paste(console_escape(paste0("'", texts, "'"), FALSE), collapse = ", "))
    }
  }
  if (identical(pol$mode, "call")) policy_resignal(cnd)
  invisible(NULL)
}

#' Re-signal an interrupt so programmatic loops stop (03 section 6.2): enclosing handlers see it;
#' without one the evaluation returns to the top level
#' @noRd
policy_resignal = function(cnd) {
  signalCondition(cnd)
  invokeRestart("abort")
}

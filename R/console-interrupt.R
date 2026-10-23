# console-interrupt.R -- the interrupt policy of every blocking gptr call (P14, layer L5, area
# console; INFRA-03, architecture 6.2, contract 7.14), the `console.interrupt_policy` service.
# Report 18 sections 2.2.2 and 4.6 with G3's menu fixes: Ctrl-C opens an ordinary pause menu
# (excluded from a tool's stdout capture) that resumes through R's `resume` restart; only the
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
    withCallingHandlers(expr_fun(),
      gptr_message = function(cnd) console_before_message(pol$runs),
      gptr_process_spawn = function(cnd) console_before_message(pol$runs, kind = NULL),
      interrupt = function(cnd) policy_menu(cnd, pol)),
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
#' terminal R, also inside VS Code, the consoles of Positron and RStudio, and R.app, but not
#' Windows' Rgui (03 section 6.2, report 18 section 2.1.6; the visual review and the steering
#' review resumed it there).
#' @noRd
console_menu_available = function() {
  isTRUE(gptr_can_prompt()) &&
    (front_end() %in% c("terminal", "vscode", "positron", "rstudio", "unknown") ||
       identical(platform_gui(), "AQUA"))
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

#' Read one menu answer at the person's chevron at column 0, as a console question reads (D-243):
#' from a `.stdin` REPL's connection, else readline_answer(); a Ctrl-C while waiting (no resume
#' restart there) gives NA, and in a terminal ends the person's row, as ui_console_read() does.
#' With `accept` (readline_answer()) a line typed before the chevron showed answers when it is one
#' of them, and another such line is kept in the history (console_keep()), never sent to the agent
#' @noRd
console_ask = function(accept = NULL) {
  prompt = paste0(console_style()$person, " ")
  rs = console_repl_find()
  x = tryCatch({
    x = if (isTRUE(rs$stdin) && !is.null(rs$reader)) {
      rs$reader$read(prompt, stream = "stdout")
    } else {
      readline_answer(prompt, if (is.null(accept)) console_typed_ahead else console_keep, accept)
    }
    if (length(x) != 1L || is.na(x)) NA_character_ else as_utf8(x)
  }, interrupt = function(e) NA_character_)
  if (is.na(x) && console_class() %in% c("T", "D")) console_cat("\n")
  x
}

#' The pause menu (calling handler for `interrupt`), a console question wherever it is offered
#' (D-243): after a blank row, `? Paused` (the session's id added when more than one is paused)
#' and under its text the keys as an approval's (ui_keys()): `s steer`, `f follow-up`, `c continue`,
#' `a abort` and, for a foreground call, `b background`, read at the person's chevron
#' (console_ask()), in the saved modes from before its rows (tty_question()). A key or its word
#' answers, also one typed before the chevron showed, an empty answer continues, anything else gets
#' a dim hint naming the keys. [s] and [f] read their text at the chevron of their own question, `?
#' Steer` or `? Follow-up`, and queue it as Enter and Tab do (policy_enqueue()), their queue line,
#' without the text it shows under, right under it, as under any question. [b] says
#' in dim rows that the run went to the background (with the service's notices), or in red why not.
#' It resumes the interrupted computation, the next block a blank row below the menu and the live
#' row with a T console's draft drawn again (console_asked()), or returns to let the policy's
#' exiting handler abort. It clears the live row only: an answer's held row stays in its stream and
#' continues after the menu, which goes between whole rows (D-245)
#' @noRd
policy_menu = function(cnd, pol) {
  # nested policies drop their runs while the stack unwinds to the exiting handler
  pol$abort_runs = pol$runs
  if (is.null(findRestart("resume", cnd)) || !console_menu_available()) return(invisible(NULL))
  if (!is.null(the$live_row)) the$live_row$clear()
  recs = as.list(console_state()$active)
  for (rec in recs) {
    rec$paused = TRUE
    rec$last = "prompt"
  }
  targets = Filter(function(t) !is.null(t$session), policy_targets(pol$runs))
  s = if (length(targets)) targets[[1L]]$session
  bg = !is.null(s) && identical(pol$mode, "call") && ext_service_has("bg.register") &&
    !isTRUE(targets[[1L]]$run$opts$background)
  keys = c(if (!is.null(s)) c(s = "steer", f = "follow-up"), c = "continue", a = "abort",
           if (bg) c(b = "background"))
  k = names(keys)
  ids = unique(vapply(targets, function(t) session_data(t$session)$id, ""))
  rlang::local_options(cli.num_colors = console_colors())
  title = paste(c("Paused", if (length(ids) > 1L) ids[[1L]]), collapse = " ")
  tty_question(TRUE)
  console_write(c("", paste0("  ", ui_question(title, ui_width() - 2L)),
                  ui_keys(k, keys, ui_width())))
  go = function() {
    for (rec in recs) rec$last = "notice"
    console_render_resume(pol$runs)
    console_asked()
    invokeRestart("resume")
  }
  repeat {
    ans = tolower(trimws(console_ask(c("", k, keys))))
    key = if (is.na(ans)) "a" else c("c", k, k)[match(ans, c("", k, keys))]
    if (identical(key, "c")) go()
    if (identical(key, "a")) return(invisible(NULL))
    if (key %in% c("s", "f")) {
      # the text's own question, so its chevron hangs under a title as every other does
      console_write(paste0("  ", ui_question(c(s = "Steer", f = "Follow-up")[[key]],
                                             ui_width() - 2L)))
      text = console_ask(TRUE)
      if (is.na(text)) return(invisible(NULL))
      enqueue = function() {
        the$echoed = ""
        on.exit({
          the$echoed = NULL
        }, add = TRUE)
        policy_enqueue(s, text, if (identical(key, "s")) "steer" else "follow_up")
      }
      enqueue()
      go()
    }
    if (identical(key, "b")) {
      sym = console_style()
      say = function(text, style = sym$dim) {
        console_write(style(console_wrap(paste0("  ", text), ui_width())))
      }
      tryCatch({
        # the service's notices are the menu's dim rows
        withCallingHandlers(ext_service_get("bg.register")(s), gptr_message = function(m) {
          say(console_escape(text_lines(conditionMessage(m)), FALSE))
          invokeRestart("muffleMessage")
        })
        tty_question(FALSE)
        console_render_pause()
        say(paste0("running in the background", sym$sep, "gptr_wait() brings it back"))
        console_write("")
        invokeRestart("resume")
      }, error = function(e) {
        say(paste0("cannot run in the background", sym$sep,
                   console_escape(conditionMessage(e), FALSE)), sym$red)
      })
      next
    }
    console_write(ui_hint(paste0("Paused. Type ", paste(k[-length(k)], collapse = ", "), " or ",
                                 k[[length(k)]], ".")))
  }
}

#' The REPL whose prompt runs, unless it is piped (`.stdin`, `jsonl`), or NULL: its reader's
#' `typed` lines are the next prompts (D-242)
#' @noRd
console_repl_prompt = function() {
  rs = console_repl_find()
  if (!is.null(rs$sending) && !isTRUE(rs$stdin)) rs
}

#' Queue pause-menu or typed text on the session (IC-49, IC-55: source "pause_menu" or "repl",
#' IC-76) after the `input` event (source "steer"), with its queue line (console_queue_line());
#' blank text queues nothing. While a REPL prompt runs (console_repl_prompt()), a follow-up, and
#' text starting with / or !, is the next prompt instead (D-242): it waits in the reader's `typed`
#' lines, and its `input` event comes when it is sent; the reader's `sent` is the kind queued last
#' (console_newest()).
#'
#' P06 refuses an enqueue from the session's own tool frames, which are on the stack when the
#' interrupt hit a tool; the item then waits in the console state for policy_flush().
#' @noRd
policy_enqueue = function(s, text, as, source = "pause_menu") {
  text = as_utf8(text)
  if (!nzchar(trimws(text))) return(invisible(FALSE))
  rs = console_repl_prompt()
  later = identical(as, "follow_up") || grepl("^\\s*[/!]", text)
  if (!is.null(rs)) rs$reader$sent = if (later) "follow_up" else "steer"
  if (!is.null(rs) && later) {
    console_queue_line(s, text, "follow_up")
    rs$reader$typed = c(rs$reader$typed, text)
    return(invisible(TRUE))
  }
  ev = ev_dispatch("input", ev_new("input", text = text, source = "steer"), session = s)
  if (identical(ev$action, "handled")) return(invisible(FALSE))
  console_queue_line(s, ev$text, as)
  st = console_state()
  st$pending = c(st$pending, list(list(s = s, text = ev$text, as = as, source = source)))
  policy_flush()
  if (length(st$pending)) reactor_timer(at = reactor_now(), fn = policy_flush)
  invisible(TRUE)
}

#' The dim line at column 0 that shows a message queued for session `s` (D-242): the queued
#' glyph, `steer` or `follow-up`, the separator and the text (ASCII `-> steer - <text>`), cut to
#' three rows; a steer on a CLI route adds `after the CLI's answer`. A line whose text is on screen
#' already, right above it, says `the$echoed` in its place: `not an answer` for a line a question
#' read past (console_typed_ahead()), nothing for the pause menu's [s] and [f] text, which their
#' question's title names (policy_menu()). Inside an evaluation it has the console's
#' colours. It is a block of the person's lines (console_gap()), except right under a question
#' whose read routed it; while an answer of the session's foreground run streams, it waits in the
#' run's record (`rec$queued`) for the answer's block to end, so it never splits a sentence (D-245).
#' Where a T console's composer reads keys, the live row shows the queue while it is up (D-243), so
#' only a CLI route's steer prints its line then.
#' @noRd
console_queue_line = function(s, text, as) {
  steer = identical(as, "steer")
  on_cli = steer && identical(session_live(s)$run$model[["type"]], "cli")
  # the live row shows the queue, but not that a CLI route's steer waits for the CLI's answer
  if (!on_cli && isTRUE(the$tty$keys) && isTRUE(the$live_row$shown)) return(invisible(NULL))
  rlang::local_options(cli.num_colors = console_colors())
  sym = console_style()
  text = the$echoed %||% text
  rows = sym$dim(console_person_rows(sym$queued, paste0(
    if (steer) "steer" else "follow-up", if (nzchar(text)) paste0(sym$sep, text),
    if (on_cli) paste0(sym$sep, "after the CLI's answer")
  ), n = 3L))
  rec = Find(function(rec) identical(rec$session, s) && console_foreground(rec, tools = TRUE),
             as.list(console_state()$active))
  if (!is.null(rec$md) && identical(rec$last, "text")) {
    rec$queued = c(rec$queued, rows)
    return(invisible(NULL))
  }
  if (!is.null(rec) && !identical(rec$last, "prompt")) console_gap(rec, "person")
  console_write(rows)
}

#' A line typed before a console question (readline_answer()): routed as a line typed during the
#' run of this call (console_typed_route(): /command and !code wait for the next prompt, the
#' others are queued as `type_ahead` says), else added to the console history; never an answer
#' (IC-75, D-243). Without a REPL reader it is queued. The console echoed it after the question's
#' chevron, so its queue line does not repeat it (`the$echoed`).
#' @noRd
console_typed_ahead = function(text) {
  target = Find(function(t) !is.null(t$session), policy_targets(policy_find()$runs))
  if (is.null(target)) return(console_history_add(text))
  the$echoed = "not an answer"
  on.exit({
    the$echoed = NULL
  }, add = TRUE)
  rd = console_repl_find()$reader
  if (is.null(rd)) {
    policy_enqueue(target$session, text, setting_get("type_ahead", target$session),
                   source = "repl")
  } else {
    console_typed_route(rd, target$session, text)
  }
}

#' Queue the pending console items once no tool executes on the stack: at the next reactor
#' step or when the tool ends (the tool_execution_end hook), so before the next request
#' (INFRA-12). The end of a foreground run settles its session's items first
#' (console_queue_left()); any other item reaches its session's queue, for its next run (D-242)
#' @noRd
policy_flush = function() {
  st = console_state()
  if (!length(st$pending) || !is.null(run_current())) return(invisible(NULL))
  items = st$pending
  st$pending = NULL
  for (it in items) {
    tryCatch(session_enqueue(it$s, it$text, as = it$as, source = it$source),
             error = function(e) {
               console_notice("[gptr] the queued message could not be delivered: ",
                              console_escape(conditionMessage(e), FALSE), .error = TRUE)
             })
  }
  invisible(NULL)
}

#' Abort (exiting handler for `interrupt`): abort the runs present at the interrupt and, in mode
#' "call", re-signal the interrupt; what the person queued goes to the history at each run's end
#' (console_queue_left()); a notice says so unless a run's status line (a foreground run at
#' verbosity 1+) already did
#' @noRd
policy_abort = function(cnd, pol) {
  targets = policy_targets(pol$abort_runs %||% pol$runs)
  said = verbosity() >= 1L && any(vapply(targets, function(t) {
    rec = console_record(list(run = t$run$id))
    !is.null(rec) && console_foreground(rec)
  }, NA))
  suspendInterrupts({
    for (t in rev(targets)) if (policy_active(t$run)) run_abort(t$run, reason = "user")
  })
  console_render_pause()
  if (!said) console_notice("[gptr] aborted; the session is kept.")
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

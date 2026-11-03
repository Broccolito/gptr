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

#' Read one menu answer at `prompt`, the answer's under the menu's question (ui_answer_prompt()) or
#' the receipt's word of the menu's `[s]` and `[f]` text, as a console question reads (D-243,
#' D-301): from a `.stdin` REPL's connection, else readline_answer(); a Ctrl-C while waiting (no
#' resume restart there) gives NA, and in a terminal ends the person's row, as ui_console_read()
#' does. With `accept` (readline_answer()) a line typed before the prompt showed answers when
#' `accept(line)` takes it, and another such line is kept in the history (console_keep()), never
#' sent to the agent; the keys a T console read with its Ctrl-C are such lines, read first
#' (console_ahead()), and a line they begin without ending begins the answer: shown after the
#' prompt, the read's text after it
#' @noRd
console_ask = function(accept = NULL, prompt = ui_answer_prompt()) {
  rs = console_repl_find()
  x = console_ahead(rs$reader, accept, prompt)
  if (!is.null(x)) return(x)
  part = rs$reader$after_interrupt %||% ""
  if (nzchar(part)) rs$reader$after_interrupt = ""
  prompt = paste0(prompt, part)
  x = tryCatch({
    x = if (isTRUE(rs$stdin) && !is.null(rs$reader)) {
      rs$reader$read(prompt, stream = "stdout")
    } else {
      readline_answer(prompt, if (is.null(accept)) console_typed_ahead else console_keep, accept,
                      read = function(p) band_read(p, gptr_readline))
    }
    if (length(x) != 1L || is.na(x)) NA_character_ else as_utf8(x)
  }, interrupt = function(e) NA_character_)
  if (is.na(x) && console_class() %in% c("T", "D")) console_cat("\n")
  if (is.na(x)) x else paste0(part, x)
}

#' The answer among the keys a T console's composer read with its Ctrl-C (`rd$after_interrupt`,
#' console_keys()), or NULL: the first whole line, its edit keys applied (console_compose()), that
#' `accept(line)` takes, echoed after `prompt` on the band as readline() leaves a line. The lines
#' before it, or with no answer the whole lines, go to the console history (console_keep()), never
#' to the agent; the text after it waits for the next question, and with no answer a line not
#' ended begins this question's (console_ask())
#' @noRd
console_ahead = function(rd, accept, prompt = ui_answer_prompt()) {
  x = rd$after_interrupt %||% ""
  if (!nzchar(x)) return(NULL)
  edit = console_line_text
  keep = function(texts) console_keep(texts[nzchar(trimws(texts))])
  lines = console_typed_split(x)
  part = if (isTRUE(attr(lines, "partial"))) lines[[length(lines)]]
  whole = lines[seq_len(length(lines) - !is.null(part))]
  typed = vapply(whole, function(line) edit(paste0(line, "\n")), "", USE.NAMES = FALSE)
  hit = which(vapply(typed, function(x) isTRUE(accept(x)), NA))
  if (!length(hit)) {
    rd$after_interrupt = if (!is.null(part)) edit(part) else ""
    keep(typed)
    return(NULL)
  }
  n = hit[[1L]]
  rd$after_interrupt = paste0(paste(c(whole[-seq_len(n)], ""), collapse = "\n"), part)
  keep(typed[seq_len(n - 1L)])
  console_write(console_band(paste0(prompt, console_escape(typed[[n]], FALSE))))
  typed[[n]]
}

#' The pause menu (calling handler for `interrupt`), a console question wherever it is offered
#' (D-243): after a blank row, `? Paused` and under its text the keys as an approval's (ui_keys()):
#' `s steer`, `f follow-up`, `c continue`, `a abort` and, for a foreground call, `b background`,
#' read at the answer's prompt under them
#' (console_ask()), in the saved modes from before its rows (tty_question()), after a drain as at
#' any question (ui_drain(): a D console's line SIGINT left is kept), a T console's draft said to
#' be kept above the chevron (ui_draft_kept()). A key or its word
#' answers, also one typed before the chevron showed or with the Ctrl-C (console_ahead()), an empty
#' answer continues, anything else is kept in the history, never sent, under a dim row that says
#' so and names the keys (ui_reask()); so is a pasted block, whatever its first line (the lines a
#' macOS terminal leaves waiting after it). `[s]` and `[f]` read their text at their receipt's
#' word, `steer> ` or `next> `, at column 0 on the band, so the line read is the receipt (D-301; a
#' pasted block's later lines, which a macOS terminal leaves waiting, are part of it and get the
#' receipt written whole), and queue it as Enter and Tab do (policy_enqueue()). `[b]` closes
#' the answer's cut row, then says in dim terms (console_terms()) that the run went to the
#' background, the service's notice one of them, then lists what the REPL held for after the run as
#' kept (console_background_settle()), or in red why not.
#' It resumes the interrupted computation, the next block a blank row below the menu (where a tool
#' runs, its call's block continues: its code's further output and its result line) and the live
#' row with a T console's draft drawn again (console_asked()), or returns to let the policy's
#' exiting handler abort, in the call's modes again, so a key typed while the run stops is not
#' echoed. It clears the live row only: an answer's held row stays in its stream and continues
#' after the menu, which goes between whole rows (D-245)
#' @noRd
policy_menu = function(cnd, pol) {
  # nested policies drop their runs while the stack unwinds to the exiting handler
  pol$abort_runs = pol$runs
  # one Esc in RStudio sets R's interrupt flag twice (its own and its SIGINT's): a second interrupt
  # in this handler would reach only the policy's abort, so one right behind the first is taken here
  tryCatch(Sys.sleep(0.05), interrupt = function(e) NULL)
  if (is.null(findRestart("resume", cnd)) || !console_menu_available()) return(invisible(NULL))
  if (!is.null(the$live_row)) the$live_row$clear()
  recs = as.list(console_state()$active)
  # a tool on the stack, such as the r code the menu interrupted: its further output and its result
  tool = !is.null(run_current())
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
  rlang::local_options(cli.num_colors = console_colors())
  tty_question(TRUE)
  on.exit(tty_question(FALSE), add = TRUE)
  # one title: [s] and [f] act on the console's own session, which the rows above name
  console_write(c("", paste0("  ", ui_question("Paused", ui_width() - 2L)),
                  ui_keys(k, keys, ui_width())))
  # a key or its word answers, also one typed before the chevron showed
  answers = function(x) tolower(trimws(x)) %in% c("", k, keys)
  # what was typed as the pause key came, drained as at any question: a D console's line SIGINT
  # left (tty_call()) is kept, and a key among it answers
  ahead = ui_drain(ui_answer_prompt(), answers)
  ui_draft_kept()
  go = function() {
    # resumed code's output (the evaluator's tee writes no block gap) and its result line are its
    # call's block again, one blank row below the menu; any other block opens after a notice
    for (rec in recs) rec$last = if (tool) "tool" else "notice"
    if (tool && nzchar(console_pad())) console_cat("\n")
    console_render_resume(pol$runs)
    console_asked()
    invokeRestart("resume")
  }
  # the lines a macOS terminal left of a block pasted at a question (ui_console_read())
  rd = console_repl_find()$reader
  repeat {
    asked = !rlang::is_string(ahead)
    typed = if (asked) console_ask(answers) else ahead
    ahead = NULL
    more = if (asked && !is.na(typed) && !is.null(rd)) rd$waiting()
    if (length(more)) {
      kept = gptr_is_interactive() && console_history_add(paste(c(typed, more), collapse = "\n"))
      console_write(ui_reask("a pasted block is not an answer", k, kept))
      next
    }
    ans = tolower(trimws(typed))
    key = if (is.na(ans)) "a" else c("c", k, k)[match(ans, c("", k, keys))]
    if (identical(key, "c")) go()
    if (identical(key, "a")) return(invisible(NULL))
    if (key %in% c("s", "f")) {
      kind = if (identical(key, "s")) "steer" else "follow_up"
      text = console_ask(function(x) TRUE, c(s = "steer> ", f = "next> ")[[key]])
      if (is.na(text)) return(invisible(NULL))
      # a block pasted here is one message, as at the prompt, its receipt written whole
      more = if (!is.null(rd)) rd$waiting()
      policy_enqueue(s, paste(c(text, more), collapse = "\n"), kind,
                     shown = if (!length(more)) kind)
      go()
    }
    if (identical(key, "b")) {
      sym = console_style()
      # the service's notice, P21's that background sessions are experimental (once a process),
      # is a term of the menu's status row, after the answer's cut row
      said = FALSE
      tryCatch({
        withCallingHandlers(ext_service_get("bg.register")(s), gptr_message = function(m) {
          said <<- TRUE
          invokeRestart("muffleMessage")
        })
        tty_question(FALSE)
        console_render_pause()
        console_write("")
        # nothing runs it while the chat prompt waits (later runs only at R's own prompt)
        where = "in the background"
        if (said) where = paste0(where, " (experimental, ?\"gptr-background\")")
        # `!!` is the chat prompt's R code; at R's own prompt it would negate the session
        bang = if (!is.null(console_repl_find())) "!!"
        terms = c(where, paste0(bang, "gptr::gptr_wait(gptr::gptr_last()) continues it here"))
        console_write(sym$dim(paste0("  ", console_terms(terms, ui_width() - 2L))))
        console_background_settle()
        console_write("")
        invokeRestart("resume")
      }, error = function(e) {
        console_write(sym$red(console_wrap(paste0(
          "  cannot run in the background", sym$sep, console_escape(conditionMessage(e), FALSE)
        ), ui_width())))
      })
      next
    }
    # text that is no key is kept, never sent, as an approval keeps it
    kept = gptr_is_interactive() && console_history_add(typed)
    console_write(ui_reask("not a key", k, kept))
  }
}

#' After `[b]` (policy_menu()) no run ends in the foreground, so the follow-ups, `/cmd` and `!code`
#' lines the REPL held for after it (the reader's `typed` lines) and a T console's draft would be
#' the next prompts while the run goes on, a prompt a steer of it (route_continue()). As after an
#' abort (console_queue_left()) they go to the console history, listed once (console_keep();
#' nothing when nothing is held), and the composer starts empty
#' @noRd
console_background_settle = function() {
  rd = console_repl_prompt()$reader
  if (is.null(rd)) return(invisible(NULL))
  draft = rd$compose$draft
  texts = c(rd$typed, draft[nzchar(draft)])
  rd$typed = character()
  rd$compose = NULL
  console_keep(texts)
}

#' The REPL whose prompt runs, or whose `!!gptr_wait()` waits (console_wait()), unless it is piped
#' (`.stdin`, `jsonl`), or NULL: its reader's `typed` lines are the next prompts (D-242)
#' @noRd
console_repl_prompt = function() {
  rs = console_repl_find()
  if (!is.null(rs$sending) && !isTRUE(rs$stdin)) rs
}

#' Queue pause-menu or typed text on the session (IC-49, IC-55: source "pause_menu" or "repl",
#' IC-76) after the `input` event (source "steer"), with its receipt (console_receipt(), which the
#' read that took the text began where it showed the word of kind `shown`); blank text queues
#' nothing.
#' While a REPL prompt runs (console_repl_prompt()), a follow-up, and text starting with / or !, is
#' the next prompt instead (D-242): it waits in the reader's `typed` lines, and its `input` event
#' comes when it is sent; the reader's `sent` is the kind queued last (console_newest()).
#'
#' P06 refuses an enqueue from the session's own tool frames, which are on the stack when the
#' interrupt hit a tool; the item then waits in the console state for policy_flush().
#' @noRd
policy_enqueue = function(s, text, as, source = "pause_menu", shown = NULL) {
  text = as_utf8(text)
  if (!nzchar(trimws(text))) return(invisible(FALSE))
  rs = console_repl_prompt()
  later = identical(as, "follow_up") || grepl("^\\s*[/!]", text)
  if (!is.null(rs)) rs$reader$sent = if (later) "follow_up" else "steer"
  if (!is.null(rs) && later) {
    console_receipt(s, text, "follow_up", shown)
    rs$reader$typed = c(rs$reader$typed, text)
    return(invisible(TRUE))
  }
  ev = ev_dispatch("input", ev_new("input", text = text, source = "steer"), session = s)
  if (identical(ev$action, "handled")) return(invisible(FALSE))
  console_receipt(s, ev$text, as, shown)
  st = console_state()
  st$pending = c(st$pending, list(list(s = s, text = ev$text, as = as, source = source)))
  policy_flush()
  if (length(st$pending)) reactor_timer(at = reactor_now(), fn = policy_flush)
  invisible(TRUE)
}

#' The receipt of a message the person sent to session `s` while it runs (D-301), written at once:
#' the person's rows at column 0 on the input band (console_band()), `steer> <text>` (the agent
#' reads it at its next step boundary) or `next> <text>` (after this answer), its word as the
#' prompt `peter> ` reads, the text wrapped under itself (console_person_rows()); a steer on a CLI
#' route ends with a dim `(after the CLI's answer)`, on a row of its own where the last is full.
#' Where the read that took the text showed the word of kind `shown` (the pause menu's `steer> `
#' and `next> `), that row is the receipt, and only a note follows it, on a row of its own: the
#' CLI's, or `(runs after this answer)` where the text went as the other kind (`/` and `!` text
#' read at `steer> `). A block of the person's lines (console_person_write()). Inside an
#' evaluation it has the console's colours.
#' @noRd
console_receipt = function(s, text, as, shown = NULL) {
  rlang::local_options(cli.num_colors = console_colors())
  sym = console_style()
  steer = identical(as, "steer")
  word = if (identical(shown %||% as, "steer")) "steer>" else "next>"
  rows = if (is.null(shown)) console_person_rows(word, text)
  note = if (!is.null(shown) && !identical(shown, as)) "(runs after this answer)" else
    if (steer && identical(session_live(s)$run$model[["type"]], "cli")) "(after the CLI's answer)"
  if (!is.null(note)) {
    grey = if (nzchar(sym$band)) sym$band_dim else sym$dim
    n = length(rows)
    if (n && live_fit(rows[[n]]) + 1L + nchar(note) < cli::console_width()) {
      rows[[n]] = paste(rows[[n]], grey(note))
    } else {
      rows = c(rows, paste0(strrep(" ", nchar(word) + 1L), grey(note)))
    }
  }
  if (length(rows)) console_person_write(s, console_band(rows))
}

#' The dim row that says a message `it` (console_newest()) went back into the draft (Up, D-301):
#' `<queued glyph> steer taken back<sep><text>` (`follow-up`), cut to one row, a block of the
#' person's lines (console_person_write()), in the console's colours
#' @noRd
console_taken_back = function(s, it) {
  rlang::local_options(cli.num_colors = console_colors())
  sym = console_style()
  kind = if (identical(it$kind, "steer")) "steer" else "follow-up"
  said = paste0(sym$queued, " ", kind, " taken back", sym$sep, live_text(it$text))
  console_person_write(s, sym$dim(live_fit(said, cli::console_width() - 1L, sym$ellipsis)))
}

#' Write the person's `rows` for session `s` as a block of their own (console_gap()), except right
#' under a question whose read routed them, between whole rows: the live row is cleared and drawn
#' again under them (gptr_message_write()), and a streamed answer's held row continues after them
#' (D-245)
#' @noRd
console_person_write = function(s, rows) {
  rec = Find(function(rec) identical(rec$session, s) && console_foreground(rec, tools = TRUE),
             as.list(console_state()$active))
  if (!is.null(rec) && !identical(rec$last, "prompt")) console_gap(rec, "person")
  console_write(rows)
}

#' A line typed before a console question (readline_answer()): routed as a line typed during the
#' run of this call (console_typed_route(): /command and !code wait for the next prompt, the
#' others are queued as `type_ahead` says), else added to the console history; never an answer
#' (IC-75, D-243). Without a REPL reader it is queued; either way its receipt says where it went.
#' @noRd
console_typed_ahead = function(text) {
  target = Find(function(t) !is.null(t$session), policy_targets(policy_find()$runs))
  if (is.null(target)) return(console_history_add(text))
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
               console_notice(console_style()$red(paste0(
                 "the queued message could not be delivered: ",
                 console_escape(conditionMessage(e), FALSE))), .error = TRUE)
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
  if (!said) {
    sym = console_style()
    console_notice(sym$dim(paste0("aborted", sym$sep, "the session is kept")))
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

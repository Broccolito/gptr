# console-ui.R -- the UI backends console, none, scripted and rstudio (builtin:ui, P11) and the
# ui.get service. Adapted from report 18 Appendix A.3 (c1_ui.R) and A.4 (permission_prompt()):
# the one-line prompt of architecture 6.8.3 / NS-1 with IC-53's display rules (the flagged calls,
# "+N more lines", controls, bidi and zero-width characters as <U+XXXX>). Never askYesNo(), menu()
# or select.list(). A front-end file (L5): it calls no perm-* function, so a remembered answer
# reaches builtin:permissions as the channel event `permissions:remember`.

#' The safety snapshot (IC-53 item 2) of the run executing on this call stack when it belongs to
#' `session`, else of the session's current run; NULL outside a run
#' @noRd
ui_snapshot = function(session) {
  sid = ext_session_id(session)
  run = run_current()
  if (is.null(run) || !(is.null(sid) || identical(run$session, sid))) {
    run = if (inherits(session, "gptr_session")) session_live(session)$run
  }
  run$opts$safety
}

#' The ui.get service (IC-43, IC-53): the run's snapshot of `gptr.ui` (a UI name or spec), else
#' `console` when someone can be prompted (the snapshot's `can_prompt`), else `none`
#' @noRd
ui_get = function(session = NULL) {
  snap = ui_snapshot(session)
  ui = if ("ui" %in% names(snap)) snap[["ui"]] else getOption("gptr.ui")
  if (rlang::is_string(ui) && nzchar(ui)) ui = registry_get("ui", ui, session = session)
  if (!inherits(ui, "gptr_ui")) {
    can = if ("can_prompt" %in% names(snap)) snap[["can_prompt"]] else gptr_can_prompt()
    ui = registry_get("ui", if (isTRUE(can)) "console" else "none", session = session) %||%
      ui_none_spec()
  }
  ui_wrap(ui)
}

#' Wrap a UI so that its permission answers are normalised and a remembered one is sent to
#' builtin:permissions
#' @noRd
ui_wrap = function(ui) {
  ask = ui$permission
  ui$permission = function(request) {
    ans = ui_answer_norm(tryCatch(ask(request), error = function(e) NULL), request)
    if (!is.null(ans$remember)) {
      ev_dispatch("permissions:remember",
                  list(scope = ans$remember, tool = request$tool, input = request$input,
                       rule = request$suggested_rule))
    }
    ans
  }
  ui
}

#' A permission answer (contract section 10.2 row 22): `feedback` only what the person typed,
#' `reason` a denial the UI writes itself; `how`, what the model should do instead of the call,
#' only when given (D-252)
#' @noRd
ui_answer = function(decision, remember = NULL, feedback = NULL, reason = NULL, how = NULL) {
  out = list(decision = decision, remember = remember, feedback = feedback, reason = reason)
  if (!is.null(how)) out$how = how
  out
}

#' Normalise a permission answer: anything unusable is a denial (a failing dialog is not an
#' approval); `remember` only for an approval that may become a rule, `how` only for a denial
#' @noRd
ui_answer_norm = function(ans, request) {
  if (!is.list(ans) || !isTRUE(ans[["decision"]] %in% c("allow", "deny", "abort"))) {
    return(ui_answer("deny", reason = "The approval dialog failed; nothing was done."))
  }
  rem = ans[["remember"]]
  keep = identical(ans[["decision"]], "allow") && isTRUE(rem %in% c("session", "project")) &&
    is.null(ui_no_rule(request))
  text = function(x) if (rlang::is_string(x) && nzchar(x)) x
  how = if (identical(ans[["decision"]], "deny")) text(ans[["how"]])
  ui_answer(ans[["decision"]], if (keep) rem, text(ans[["feedback"]]), text(ans[["reason"]]),
            how)
}

#' Why an approval of this request cannot become a rule (IC-77 item 3), else NULL: never for
#' level 4, control or the ask tool, nor without a suggested rule, where a policy that asks it
#' without one says why (`no_rule`, an ask rule's reason, escaped as the `?` view's reason is)
#' @noRd
ui_no_rule = function(request) {
  risk = request$risk
  if (identical(request$tool, "ask") || !isTRUE(risk$level < 4L) ||
        "control" %in% c(risk$categories, risk$flagged$category)) {
    return("level-4 and control actions are approved one call at a time")
  }
  if (rlang::is_string(request$suggested_rule)) return(NULL)
  if (rlang::is_string(request$no_rule)) {
    return(paste0(ui_escape(request$no_rule), "; an always rule would not stop it"))
  }
  "no rule covers these calls"
}

#' The escaped lines a request shows: its code, else its path (an absolute one normalised, relative
#' inside the project), else P06's summary
#' @noRd
ui_request_lines = function(request) {
  input = request$input
  path = input[["path"]]
  if (rlang::is_string(path) && is_abs_path(path)) path = path_rel(path)
  ui_escape(text_lines(input[["code"]] %||% path %||% request$summary))
}

#' The change a request with a path and no code makes, as escaped diff rows from its input alone
#' (the file is never read): each edit's oldText as `-` rows and newText as `+` rows (also given at
#' the input's top level), `@@` between edits; a patch envelope (`patch`, or carried in `edits`) as
#' its own lines; a write's content as `+` rows; another tool's other fields as redacted JSON (a
#' script's `env` may hand a child a secret); character() for any other shape
#' @noRd
ui_request_change = function(request) {
  input = request$input
  if (!is.list(input) || !rlang::is_string(input[["path"]]) || !is.null(input[["code"]])) {
    return(character())
  }
  signed = function(s, x) {
    x = if (rlang::is_string(x)) console_lines(x)
    if (length(x)) paste0(s, x)
  }
  patch = function(x) rlang::is_string(x) && grepl("^\\s*\\*\\*\\* Begin Patch", x, perl = TRUE)
  edit_rows = function(e) {
    if (patch(e)) return(console_lines(e))
    if (!is.list(e)) return(NULL)
    old = e[["oldText"]] %||% e[["old_text"]]
    new = e[["newText"]] %||% e[["new_text"]]
    if (patch(new) || patch(old)) return(console_lines(if (patch(new)) new else old))
    c(signed("-", old), signed("+", new))
  }
  switch(request$tool %||% "",
         edit = {
           # Pi's top-level oldText and newText too, as the edit tool takes them
           edits = if (patch(input[["patch"]])) list(input[["patch"]]) else
             input[["edits"]] %||% list(input)
           one = Filter(length, lapply(if (is.list(edits)) edits else list(edits), edit_rows))
           as.character(unlist(lapply(seq_along(one), function(i) c(if (i > 1L) "@@", one[[i]]))))
         },
         write = as.character(signed("+", input[["content"]])),
         {
           rest = input[setdiff(names(input), "path")]
           if (!length(rest)) return(character())
           console_lines(redact(tryCatch(json_encode(rest), error = function(e) ""), "context"))
         })
}

#' The flagged calls (level >= 1) of a risk record, highest level first, or NULL
#' @noRd
ui_flagged = function(risk) {
  fl = risk$flagged
  if (!is.data.frame(fl)) return(NULL)
  fl = fl[fl$level >= 1L, , drop = FALSE]
  fl[order(-fl$level), , drop = FALSE]
}

#' Flagged calls as the console writes them, the ask's and the ? view's alike (D-222, IC-82):
#' `[<level> <category>] <call>`, escaped, its backticked names inline code as in an answer and an
#' object's `<class, size>` the mention line's `(class, size)`
#' @noRd
ui_flags = function(fl) {
  blue = console_style()$blue
  call = sub(" <([^<>]*)>$", " (\\1)", ui_escape(fl$call))
  call = vapply(strsplit(call, "`", fixed = TRUE), function(p) {
    code = seq_along(p) %% 2L == 0L
    p[code] = blue(p[code])
    paste(p, collapse = "")
  }, "")
  paste0("[", fl$level, " ", fl$category, "] ", call)
}

#' Who asks (D-188): "sub-agent <label>" for a sub-agent's request, else ""
#' @noRd
ui_who = function(request) {
  a = request$agent
  if (!rlang::is_string(a) || identical(a, "main")) "" else paste0("sub-agent ", ui_escape(a))
}

#' The width of a console question's rows: the console's, less the margin (D-186)
#' @noRd
ui_width = function() max(20L, cli::console_width() - nchar(console_pad()))

#' The rows that open a console question (D-243): `?` (blue) and the title in bold, its lines
#' word-wrapped to `width` columns with the later rows under its text; escaped
#' @noRd
ui_question = function(title, width) {
  rows = console_wrap(console_lines(title), width - 2L)
  lead = c(paste0(console_style()$blue("?"), " "), rep("  ", length(rows)))
  paste0(lead[seq_along(rows)], cli::style_bold(rows))
}

#' A question's keys (D-243): rows at column 4, under the question's text, of each key in bold and
#' what it does dim, joined by the separator; a row of `width` ends at a whole key (console_terms())
#' @noRd
ui_keys = function(keys, what, width) {
  sym = console_style()
  terms = paste0(cli::style_bold(keys), sym$dim(paste0(" ", what)))
  paste0("    ", console_terms(terms, width - 4L, sym$dim(sym$sep)))
}

#' A question's hint when it reads again (D-243): dim rows at column 4, under the question's text as
#' its keys row, word-wrapped at `width`
#' @noRd
ui_hint = function(text, width = ui_width()) {
  console_style()$dim(console_wrap(paste0("    ", text), width))
}

#' A question's row when an answer is no answer (D-243): dim at column 4, as its keys row, the
#' console's lower-case `terms`, `kept in history <Up glyph>` where the console history `kept` the
#' answer (as the kept list says, console_keep()), then the `keys` it takes, each bold, its words
#' after a blank dim (`n <instead>`), `a, b or c`, in rows of whole terms (console_terms())
#' @noRd
ui_reask = function(terms, keys = character(), kept = FALSE, width = ui_width()) {
  sym = console_style()
  terms = sym$dim(c(terms, if (kept) paste("kept in history", sym$up)))
  if (length(keys)) {
    word = sub("^\\S+", "", keys)
    k = paste0(cli::style_bold(sub(" .*$", "", keys)), ifelse(nzchar(word), sym$dim(word), ""))
    n = length(k)
    last = if (n > 1L) paste0(sym$dim(" or "), k[[n]])
    terms = c(terms, paste0(paste(k[seq_len(n - (n > 1L))], collapse = sym$dim(", ")), last))
  }
  paste0("    ", console_terms(terms, width - 4L, sym$dim(sym$sep)))
}

#' The question of an approval (D-243): `Allow <tool>?`, or `<who>: allow <tool>?` for a sub-agent
#' @noRd
ui_permission_question = function(request) {
  tool = console_tool_name(request$tool %||% "tool")
  who = ui_who(request)
  if (nzchar(who)) paste0(who, ": allow ", tool, "?") else paste0("Allow ", tool, "?")
}

#' Is the console's last printed call line this request's (its session and call ids, D-243)?
#' @noRd
ui_call_shown = function(request) {
  rlang::is_string(request$tool_call_id) &&
    identical(console_state()$last_call, c(request$session, request$tool_call_id))
}

#' The lines of an approval (D-243): the call line (`  | r  x = 1`, the tool named, R code
#' highlighted and an MCP call's arguments dim as the console's call line has them, fitted to the
#' console before (+N more lines), D-187) unless the console printed it (ui_call_shown()), at most
#' 12 rows of the change a path tool makes (ui_request_change()) as a diff, then dim at column 4
#' the flagged calls one per line, fitted, at most 5 (D-222), and why an `ask_human` request asks
#' in every mode, then the question, and under its text the keys (a and p only with a rule,
#' ui_keys())
#' @noRd
ui_permission_lines = function(request) {
  sym = console_style()
  lines = ui_request_lines(request)
  lines = lines[nzchar(trimws(lines))]
  change = ui_request_change(request)
  more = console_more_lines(lines)
  tool = console_tool_name(request$tool %||% "tool")
  arg = c(lines, "")[1L]
  width = ui_width()
  code = is.character(request$input[["code"]])
  first = paste0("  ", sym$red(sym$tool), " ", cli::style_bold(tool), "  ",
                 if (startsWith(request$tool %||% "", "mcp__") && !code) sym$dim(arg) else
                   console_code(arg, console_lang(request$tool)))
  call = if (!ui_call_shown(request)) {
    paste0(cli::ansi_strtrim(first, max(20L, width - nchar(more))), more)
  }
  fl = ui_flagged(request$risk)
  n = NROW(fl)
  why = request$reason
  can = is.null(ui_no_rule(request))
  keys = c("y", if (can) c("a", "p"), "n", "?")
  what = c("yes", if (can) c("always (session)", "always (project)"), "no", "more")
  c(call,
    console_diff_rows(change, 12L, width, "; ? shows more"),
    if (n) {
      k = seq_len(min(n, 5L))
      lead = c("    flagged: ", rep(strrep(" ", 13L), 4L))[k]
      rows = paste0(lead, ui_flags(fl[k, , drop = FALSE]))
      sym$dim(console_cut(c(rows, if (n > 5L) {
        paste0(strrep(" ", 13L), "(+", n - 5L, " more; ? shows all)")
      }), width))
    },
    if (identical(request$tier, "ask_human") && rlang::is_string(why) && nzchar(why)) {
      sym$dim(console_wrap(paste0("    asks in every mode: ", ui_escape(why)), width))
    },
    paste0("  ", ui_question(ui_permission_question(request), width - 2L)),
    ui_keys(keys, what, width))
}

#' The detail view shown for `?`: at most 40 code rows at column 4 as the call block shows them
#' (console_code_rows(), D-207), or of a path tool's change, its path then named in the first row;
#' the keys as the question shows them, bold, padded to one width, and what they do, dim (D-243),
#' the interrupt key as the banner names it (`ctrl-c`, `esc`). Under the console's ask (`asked`) it
#' leaves out what shows whole above it: the code when the call block showed it (at most 20 rows
#' that fit), the change rows the ask showed (its first 12 when none was cut), the rest under a dim
#' `(continued)`; alone, as the RStudio dialog, it shows them all. Every row is wrapped to the
#' console under its own text: prose at column 2, a change row after its sign, code under its code,
#' a flagged call under its call, a key's words under its words
#' @noRd
ui_permission_detail = function(request, asked = FALSE) {
  risk = request$risk
  sym = console_style()
  width = ui_width()
  lines = ui_request_lines(request)
  change = ui_request_change(request)
  fits = function(x, n) length(x) <= n && all(nchar(x, type = "width") + 4L <= width)
  code = !(asked && ui_call_shown(request) && is.character(request$input$code) && fits(lines, 20L))
  shown = if (asked && fits(utils::head(change, 12L), 12L)) min(12L, length(change)) else 0L
  rest = change[seq_along(change) > shown]
  who = ui_who(request)
  # in the ask's type: who wants which tool bold, its reason and flags dim; the console's name
  first = paste0("  ", if (nzchar(who)) who else "peter", " wants to use ",
                 console_tool_name(request$tool %||% "a tool"),
                 if (length(change)) paste0(" on ", c(lines, "")[[1L]]),
                 # the level, unless the reason row names it
                 if (!is.null(risk$level) && !grepl(paste("level", risk$level),
                                                    request$reason %||% "")) {
                   label = if (rlang::is_string(risk$label)) paste0(": ", ui_escape(risk$label))
                   paste0(" (level ", risk$level, label, ")")
                 },
                 if (identical(request$tier, "ask_human")) ", which needs your decision")
  out = c(cli::style_bold(console_wrap(first, width)),
          if (rlang::is_string(request$reason) && nzchar(request$reason)) {
            sym$dim(console_wrap(paste0("  reason: ", ui_escape(request$reason)), width))
          },
          if (length(rest)) {
            c(if (shown) sym$dim("    (continued)"),
              console_hang(console_diff_rows(rest, 40L - shown), width, 5L))
          } else if (!length(change) && code) {
            console_hang(console_code_rows(lines, console_lang(request$tool), 40L), width, 6L)
          })
  fl = ui_flagged(risk)
  if (NROW(fl)) {
    where = ifelse(is.na(fl$path), "",
                   paste0("  path: ", ui_escape(fl$path), " (", fl$path_class, ")"))
    flags = ui_flags(fl)
    rows = lapply(seq_along(flags), function(k) {
      console_hang(paste0("    ", flags[[k]], where[[k]]), width,
                   5L + nchar(paste0("[", fl$level[[k]], " ", fl$category[[k]], "]")))
    })
    out = c(out, sym$dim(c("  flagged calls:", unlist(rows))))
  }
  note = request$undo_note %||% ui_undo_note(request)
  if (rlang::is_string(note) && nzchar(note)) {
    out = c(out, console_wrap(paste0("  ", ui_escape(note)), width))
  }
  can = is.null(ui_no_rule(request))
  # the console's interrupt key as the banner and live row name it; the words in one column
  keys = c("y", if (can) c("a", "p"), "n", tolower(console_interrupt_key()))
  what = c("yes", if (can) {
    paste0(c("always in this session: ", "always in this project: "),
           ui_escape(request$suggested_rule))
  }, "no (type n <what to do instead> to tell peter)", "abort the run")
  keys = format(keys)
  c(out, console_hang(paste0("    ", cli::style_bold(keys), "  ", sym$dim(what)), width,
                      6L + nchar(keys[[1L]])))
}

#' The "cannot be undone" note of the checkpoint.note service (P16) for a request without one
#' @noRd
ui_undo_note = function(request) {
  if (!ext_service_has("checkpoint.note")) return(NULL)
  call = list(name = request$tool, input = request$input, risk = request$risk,
              nested = isTRUE(request$nested))
  tryCatch(ext_service_get("checkpoint.note")(call, NULL), error = function(e) NULL)
}

#' Read one console answer, never a line typed before the question: a terminal REPL first drains
#' what was typed for the run (console_typed(drain = TRUE): a T console's keys go to its composer;
#' a D console's lines are routed as console_typed() routes them, the partial line the question
#' would take as its answer kept in the history, IC-76), so their lines sit under the question's
#' rows, right above the chevron; then readline_answer(). When the REPL's reader finds lines
#' waiting after the answer (a paste; a last line without a newline is not waiting), the answer and
#' the lines go to the console history as one entry (a `secret` is dropped) and the question is
#' asked again (IC-75); Ctrl-C or EOF gives NA, and in a terminal ends the person's row, which
#' readline() leaves open then. A `secret` is read with the echo off where R reads its own terminal
#' (tty_secret()); elsewhere the console shows it, which a dim row above the chevron says once in
#' the session (IC-77). A T console's draft stays in its composer, for the live row after the
#' answer; a dim row above the chevron says so (ui_draft_kept(), D-243). A whole line that
#' `accept(line)` takes, one of the question's answers, typed once its rows showed is its answer:
#' read by the drain (echoed after the chevron, on the band) or, once the drain read what was typed
#' before, by readline however soon
#' @noRd
ui_console_read = function(prompt, secret = FALSE, accept = NULL) {
  rd = console_repl_find()$reader
  hide = if (secret) tty_secret()
  # an answer on the input band as the prompts are; a secret off it, as typed without echo
  read = if (secret) function(p) gptr_readline(p, hide = hide) else function(p) {
    band_read(p, gptr_readline)
  }
  repeat {
    drained = ui_drain(prompt, accept)
    if (rlang::is_string(drained)) return(drained)
    ui_draft_kept()
    if (secret && is.null(hide) && once_first("visible", "secret")) {
      console_write(ui_hint(paste("This console shows the key as you type; gptr_env() loads keys",
                                  "from a file instead.")))
    }
    ans = tryCatch(readline_answer(prompt, if (!secret) console_typed_ahead,
                                   if (isTRUE(drained)) accept, read),
                   interrupt = function(e) NA_character_)
    if (!rlang::is_string(ans)) {
      if (console_class() %in% c("T", "D")) console_cat("\n")
      return(NA_character_)
    }
    more = if (!is.null(rd)) rd$waiting()
    if (!length(more)) return(ans)
    kept = !secret && console_history_add(paste(c(ans, more), collapse = "\n"))
    console_write(ui_reask("a pasted block is not an answer", kept = kept))
  }
}

#' A question's drain (console_typed(drain = TRUE)), after its rows: what was typed for the run is
#' routed, and the answer of a whole line `accept(line)` takes is returned, echoed after the chevron
#' `prompt` on the band, as readline leaves a line; else TRUE where fd 0 was read, FALSE where not
#' @noRd
ui_drain = function(prompt, accept) {
  got = console_typed(drain = TRUE, accept = accept)
  if (rlang::is_string(got)) console_write(console_band(paste0(prompt, console_escape(got, FALSE))))
  got
}

#' The dim row above a question's chevron where a T console's composer holds a draft (D-243), which
#' stays for the live row after the answer: `<queued> draft kept, back after your
#' answer<sep><draft>`, the draft's head kept, as a queue line keeps it, cut to the width; nothing
#' without a draft
#' @noRd
ui_draft_kept = function() {
  draft = if (isTRUE(the$tty$keys)) console_repl_find()$reader$compose$draft
  if (!nzchar(draft %||% "")) return(invisible(NULL))
  sym = console_style()
  lead = paste0(sym$queued, " draft kept, back after your answer", sym$sep)
  room = max(8L, ui_width() - 5L - live_fit(lead))
  console_write(ui_hint(paste0(lead, live_fit(live_text(draft), room, sym$ellipsis))))
}

#' Is a question's free-text answer a console command (`/exit`, `/help x`)? It waits for the next
#' prompt (console_typed_ahead()), as one typed during the run does, and the question reads again;
#' a path such as `/tmp/fit.rds` names no command and stays an answer (D-243)
#' @noRd
ui_console_command = function(ans) {
  cmd = command_parse(trimws(ans))
  !is.null(cmd) && !is.null(registry_get("command", cmd$name))
}

#' Parse a choice: numbers, or case-insensitive label prefixes (report 18 parse_choice()); NA
#' when any part matches nothing
#' @noRd
ui_parse_choice = function(ans, labels, multiple = FALSE) {
  parts = if (multiple) strsplit(trimws(ans), "[,[:space:]]+")[[1L]] else trimws(ans)
  idx = suppressWarnings(as.integer(parts))
  if (!all(idx %in% seq_along(labels))) {
    idx = pmatch(tolower(parts), tolower(labels), duplicates.ok = TRUE)
  }
  if (length(idx) && !anyNA(idx)) unique(idx) else NA_integer_
}

#' Console select() (D-243): `? <title>`, then under its text its details dim, the numbered
#' choices and a dim hint, then the person's chevron at column 0, each word-wrapped under its own
#' text; NA = cancelled, also by a fifth invalid answer, which a dim row says; attr "other" = free
#' text, unless a console command (ui_console_command())
#' Title line feeds are intentional (also for ask questions); labels and details stay escaped.
#' @noRd
ui_console_select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                             allow_other = FALSE, read = ui_console_read) {
  rlang::local_options(cli.num_colors = console_colors())
  # in a run in the console margin console_before_message() writes the block's separator
  run = console_before_message(kind = "prompt", tools = TRUE)
  on.exit(console_asked(), add = TRUE)
  pad = console_pad()
  sym = console_style()
  labels = as.character(unlist(choices))
  hint = paste0("Choose ", paste(c(if (multiple) "numbers separated by commas" else "a number",
                                   if (allow_other) "or type your own answer"), collapse = ", "),
                if (length(default)) paste0("; Enter = ", paste(labels[default], collapse = ", ")))
  width = ui_width() - nchar(pad)
  num = format(seq_along(labels))
  choice = function(i) {
    rows = console_wrap(ui_escape(labels[[i]]), width - 4L - nchar(num[[i]]))
    paste0(c(cli::style_bold(num[[i]]), rep(strrep(" ", nchar(num[[i]])), length(rows) - 1L)),
           "  ", rows)
  }
  console_write(c(if (!run || !nzchar(pad)) "", paste0(pad, c(
    ui_question(title, width),
    if (length(details)) paste0("  ", sym$dim(console_wrap(ui_escape(details), width - 2L))),
    paste0("  ", unlist(lapply(seq_along(labels), choice))),
    paste0("  ", sym$dim(console_wrap(ui_escape(hint), width - 2L)))
  ))))
  # a choice's numbers answer it however soon they are typed (ui_console_read())
  numbers = function(x) {
    grepl("^[0-9][0-9,[:space:]]*$", trimws(x)) && !anyNA(ui_parse_choice(x, labels, multiple))
  }
  for (attempt in seq_len(5L)) {
    ans = read(paste0(sym$person, " "), accept = numbers)
    if (is.na(ans)) return(NA_integer_)
    if (!nzchar(trimws(ans)) && length(default)) return(as.integer(default))
    idx = ui_parse_choice(ans, labels, multiple)
    if (!anyNA(idx)) return(idx)
    if (allow_other && ui_console_command(ans)) {
      console_typed_ahead(ans)
      next
    }
    if (allow_other && nzchar(trimws(ans))) return(structure(NA_integer_, other = trimws(ans)))
    if (attempt == 5L) break
    console_write(ui_reask(c("not an answer", paste0(
      if (multiple) "numbers separated by commas" else "a number",
      if (allow_other) " or your own answer"))))
  }
  console_write(ui_reask(c("no valid answer after 5 tries", "cancelled")))
  NA_integer_
}

#' Console input() (D-243): `? <prompt>`, a dim `Enter = <default>` under its text and the
#' person's chevron; NA = cancelled; a secret is asked through RStudio's masked dialog there, else
#' read without echo where the console allows (ui_console_read()); a console command typed there
#' waits for the next prompt (ui_console_command())
#' @noRd
ui_console_input = function(prompt, default = "", secret = FALSE, read = ui_console_read) {
  rlang::local_options(cli.num_colors = console_colors())
  console_before_message(kind = "prompt", tools = TRUE)
  on.exit(console_asked(), add = TRUE)
  if (isTRUE(secret) && ui_rstudio()) {
    ans = tryCatch(rstudioapi::askForPassword(prompt), error = function(e) NULL)
    return(if (rlang::is_string(ans)) as_utf8(ans) else NA_character_)
  }
  pad = console_pad()
  sym = console_style()
  width = ui_width() - nchar(pad)
  hint = if (nzchar(default)) {
    paste0("  ", sym$dim(console_wrap(ui_escape(paste0("Enter = ", default)), width - 2L)))
  }
  console_write(paste0(pad, c(ui_question(prompt, width), hint)))
  repeat {
    ans = read(paste0(sym$person, " "), secret = isTRUE(secret))
    if (is.na(ans) || isTRUE(secret) || !ui_console_command(ans)) break
    console_typed_ahead(ans)
  }
  if (!is.na(ans) && !nzchar(ans)) default else ans
}

#' Console permission(): the approval of NS-1 under the call it gates, read after the person's
#' chevron (D-243), `?` for the detail view; every console prompt first ends partial answer lines
#' and clears the live row (D-186), in a T console once typing pauses, and draws it again when it
#' returns (D-243); a remembered answer adds a dim line naming the rule; an
#' invalid answer gets one dim row at column 4 in the console's terms (ui_reask()), `not an
#' answer`, `kept in history` where an interactive session's history kept it, and the keys, and in
#' an IDE console an answer of several words a row noting that a draft typed during the run joins
#' an answer; five (`?` is none) end in a refusal whose reason says so (D-188, D-243); an ask that
#' shows the call's change marks its record (ui_change_asked())
#' @noRd
ui_console_permission = function(request, read = ui_console_read) {
  rlang::local_options(cli.num_colors = console_colors())
  console_before_message(kind = "prompt", tools = TRUE)
  on.exit(console_asked(), add = TRUE)
  why = ui_no_rule(request)
  can = is.null(why)
  console_write(ui_permission_lines(request))
  if (length(ui_request_change(request))) ui_change_asked(request)
  sym = console_style()
  # `no, use base R` too: punctuation right after the key is no part of the text
  deny = "^no?[,.;:!]*(\\s|$)"
  keys = c("y", "yes", if (can) c("a", "always", "p", "project"), "?")
  # its answers answer it however soon they are typed (ui_console_read())
  answers = function(x) tolower(trimws(x)) %in% keys || grepl(deny, tolower(trimws(x)))
  bad = 0L
  while (bad < 5L) {
    a = trimws(read(paste0(sym$person, " "), accept = answers))
    if (is.na(a)) return(ui_answer("abort"))
    low = tolower(a)
    if (low %in% c("y", "yes")) return(ui_answer("allow"))
    if (can && low %in% c("a", "always", "p", "project")) {
      scope = if (low %in% c("a", "always")) "session" else "project"
      console_write(sym$dim(paste0("    allowed ", ui_escape(request$suggested_rule), " for this ",
                                   scope)))
      return(ui_answer("allow", scope))
    }
    if (grepl(deny, low)) {
      fb = trimws(sub("^no?[,.;:!]*", "", a, ignore.case = TRUE))
      return(ui_answer("deny", feedback = if (nzchar(fb)) fb))
    }
    if (low == "?") {
      console_write(ui_permission_detail(request, asked = TRUE))
      next
    }
    bad = bad + 1L
    if (low %in% c("a", "always", "p", "project")) {
      console_write(ui_hint(paste0("a and p are not offered: ", why)))
      next
    }
    kept = nzchar(a) && gptr_is_interactive() && console_history_add(a)
    console_write(c(
      ui_reask("not an answer", c("y", if (can) c("a", "p"), "n", "n <instead>", "?"), kept),
      # an IDE console keeps a draft typed during the run on its input line, before the answer;
      # the reader cannot tell it from text typed at the question, so the row states the rule
      if (grepl("\\s", trimws(a)) && console_class() == "L") {
        ui_hint("a draft typed during the run joins your answer: clear the line first")
      }))
  }
  console_write(ui_reask(c("no valid answer after 5 tries", "refused")))
  ui_answer("deny", reason = "no valid answer was given at the approval prompt")
}

#' The console's record of the call an approval asks about (its session and call ids) says the ask
#' showed the call's change (`asked`), so its result sums the change up (console_result_lines())
#' @noRd
ui_change_asked = function(request) {
  key = paste0("t", request$tool_call_id)
  for (rec in as.list(console_state()$active)) {
    call = if (is.environment(rec$tools)) get0(key, envir = rec$tools, inherits = FALSE)
    if (is.null(call) || !identical(session_data(rec$session)$id, request$session)) next
    call$asked = TRUE
    assign(key, call, envir = rec$tools)
  }
  invisible(NULL)
}

#' questions() through select() and input() (report 18 ui_questions_via()); every choice
#' question also takes a typed answer
#' @noRd
ui_questions_via = function(select, input, qs) {
  answers = list()
  for (q in qs) {
    labels = as.character(unlist(q$options))
    type = q$type %||% (if (length(labels)) "single" else "text")
    title = as.character(q$question %||% q$id)
    if (identical(type, "text")) {
      a = input(title, default = as.character(q$default %||% ""))
      if (!rlang::is_string(a)) return(list(answers = answers, cancelled = TRUE))
      answers[[q$id]] = a
      next
    }
    idx = select(title, labels, default = which(labels %in% q$default),
                 multiple = identical(type, "multi"), allow_other = TRUE)
    other = attr(idx, "other")
    if (!is.null(other)) {
      answers[[q$id]] = structure(other, other = TRUE)
    } else if (length(idx) && !anyNA(idx)) {
      answers[[q$id]] = labels[idx]
    } else {
      return(list(answers = answers, cancelled = TRUE))
    }
  }
  list(answers = answers, cancelled = FALSE)
}

#' The `console` UI: readline() through gptr_readline() (IRkernel answers it too, IC-43); a
#' `.stdin` console passes its reader (P14)
#' @noRd
ui_console_spec = function(read = ui_console_read, name = "console") {
  force(read)
  select = function(...) ui_console_select(..., read = read)
  input = function(...) ui_console_input(..., read = read)
  gptr_spec("ui", name,
            has_ui = function() isTRUE(gptr_can_prompt()),
            select = select,
            input = input,
            questions = function(qs) ui_questions_via(select, input, qs),
            notify = function(text, level = "info") {
              console_notice("[", level, "] ", ui_escape(text), .error = identical(level, "error"))
            },
            permission = function(request) ui_console_permission(request, read))
}

#' The `none` UI: nobody answers; P02's defaults fail closed (contract section 10.2 row 22)
#' @noRd
ui_none_spec = function() {
  gptr_spec("ui", "none", has_ui = function() FALSE, select = function(...) NA_integer_,
            notify = function(text, level = "info") {
              gptr_inform(text, "notice", .stream = if (level == "error") "stderr" else "stdout")
            })
}

#' The state of a scripted UI: its answer queue and log (tests; contract section 12.2)
#' @noRd
ui_scripted_state = function(answers = list()) {
  st = new.env(parent = emptyenv())
  st$queue = as.list(answers)
  st$log = data.frame(method = character(), prompt = character(), answer = character())
  st$remaining = function() length(st$queue)
  st$add = function(method, prompt, answer) {
    st$log[nrow(st$log) + 1L, ] = list(method, paste(prompt, collapse = " "), answer)
  }
  st$take = function(method, prompt) {
    a = if (length(st$queue)) st$queue[[1L]]
    st$queue = st$queue[-1L]
    st$add(method, prompt, if (is.list(a)) json_encode(a) else paste(a, collapse = ","))
    a
  }
  st
}

#' A scripted UI over a state: answers are taken in order; an empty queue fails closed
#' @noRd
ui_scripted_spec = function(st, name = "scripted") {
  select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                    allow_other = FALSE) {
    a = st$take("select", title)
    if (is.numeric(a)) return(as.integer(a))
    if (!rlang::is_string(a)) return(NA_integer_)
    idx = ui_parse_choice(a, as.character(unlist(choices)), multiple)
    if (!anyNA(idx)) idx else if (allow_other) structure(NA_integer_, other = a) else NA_integer_
  }
  gptr_spec("ui", name,
            has_ui = function() TRUE,
            select = select,
            input = function(prompt, default = "", secret = FALSE) {
              a = st$take("input", prompt)
              if (rlang::is_string(a)) a else NA_character_
            },
            questions = function(qs) {
              a = st$take("questions", vapply(qs, function(q) {
                as.character(q$question %||% q$id)[1L]
              }, ""))
              if (is.list(a) && length(a)) return(list(answers = a, cancelled = FALSE))
              list(answers = json_obj(), cancelled = TRUE)
            },
            notify = function(text, level = "info") invisible(st$add("notify", text, "")),
            permission = function(request) {
              a = st$take("permission", ui_permission_lines(request)[1L])
              if (is.list(a)) return(a)
              if (!rlang::is_string(a)) {
                return(ui_answer("deny", reason = "The scripted UI has no answer left."))
              }
              switch(a, y = ui_answer("allow"), a = ui_answer("allow", "session"),
                     p = ui_answer("allow", "project"), abort = ui_answer("abort"),
                     ui_answer("deny"))
            })
}

#' Can rstudioapi show dialogs here?
#' @noRd
ui_rstudio = function() {
  requireNamespace("rstudioapi", quietly = TRUE) &&
    isTRUE(tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE))
}

#' The `rstudio` UI: rstudioapi dialogs; a dismissed or failing dialog is a denial (18 s4.9)
#' @noRd
ui_rstudio_spec = function() {
  select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                    allow_other = FALSE) {
    if (!ui_rstudio()) return(NA_integer_)
    labels = as.character(unlist(choices))
    msg = paste(ui_escape(c(details, sprintf("%d: %s", seq_along(labels), labels))),
                collapse = "\n")
    ans = tryCatch(rstudioapi::showPrompt(ui_escape(title), msg, default = ""),
                   error = function(e) NULL)
    if (!rlang::is_string(ans)) return(NA_integer_)
    idx = ui_parse_choice(ans, labels, multiple)
    if (!anyNA(idx)) return(idx)
    if (allow_other && nzchar(trimws(ans))) return(structure(NA_integer_, other = trimws(ans)))
    NA_integer_
  }
  input = function(prompt, default = "", secret = FALSE) {
    if (!ui_rstudio()) return(NA_character_)
    ans = tryCatch(if (isTRUE(secret)) {
      rstudioapi::askForPassword(ui_escape(prompt))
    } else {
      rstudioapi::showPrompt("gptr", ui_escape(prompt), default = default)
    }, error = function(e) NULL)
    if (rlang::is_string(ans)) as_utf8(ans) else NA_character_
  }
  gptr_spec("ui", "rstudio",
            has_ui = function() isTRUE(gptr_can_prompt()) && ui_rstudio(),
            select = select,
            input = input,
            questions = function(qs) ui_questions_via(select, input, qs),
            notify = function(text, level = "info") {
              gptr_inform(text, "notice", .stream = if (level == "error") "stderr" else "stdout")
            },
            permission = function(request) {
              if (!ui_rstudio()) return(ui_answer("deny"))
              detail = cli::ansi_strip(ui_permission_detail(request))
              ok = tryCatch(rstudioapi::showQuestion("gptr permission",
                                                     paste(detail, collapse = "\n"),
                                                     ok = "Allow", cancel = "Deny"),
                            error = function(e) NULL)
              ui_answer(if (isTRUE(ok)) "allow" else "deny")
            })
}

#' builtin:ui -- the four UI backends (the registered `scripted` one has an empty queue)
#' @noRd
builtin_ui = function(gptr) {
  gptr$register(ui_console_spec())
  gptr$register(ui_none_spec())
  gptr$register(ui_scripted_spec(ui_scripted_state()))
  gptr$register(ui_rstudio_spec())
  invisible(NULL)
}

on_load(ext_declare_builtin("ui", builtin_ui))
on_load(ext_service_set("ui.get", ui_get, provided_by = "P11", builtin = "ui"))

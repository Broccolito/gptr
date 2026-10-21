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

#' A permission answer (contract section 10.2 row 22)
#' @noRd
ui_answer = function(decision, remember = NULL, feedback = NULL) {
  list(decision = decision, remember = remember, feedback = feedback)
}

#' Normalise a permission answer: anything unusable is a denial (a failing dialog is not an
#' approval); `remember` only for an approval that may become a rule
#' @noRd
ui_answer_norm = function(ans, request) {
  if (!is.list(ans) || !isTRUE(ans[["decision"]] %in% c("allow", "deny", "abort"))) {
    return(ui_answer("deny", feedback = "The approval dialog failed; nothing was done."))
  }
  rem = ans[["remember"]]
  keep = identical(ans[["decision"]], "allow") && isTRUE(rem %in% c("session", "project")) &&
    is.null(ui_no_rule(request))
  fb = ans[["feedback"]]
  ui_answer(ans[["decision"]], if (keep) rem, if (rlang::is_string(fb) && nzchar(fb)) fb)
}

#' Why an approval of this request cannot become a rule (IC-77 item 3), else NULL: never for
#' level 4, control or the ask tool, nor without a suggested rule
#' @noRd
ui_no_rule = function(request) {
  risk = request$risk
  if (identical(request$tool, "ask") || !isTRUE(risk$level < 4L) ||
        "control" %in% c(risk$categories, risk$flagged$category)) {
    return("level-4 and control actions are approved one call at a time")
  }
  if (!rlang::is_string(request$suggested_rule)) "no rule covers these calls"
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

#' The flagged calls (level >= 1) of a risk record, highest level first, or NULL
#' @noRd
ui_flagged = function(risk) {
  fl = risk$flagged
  if (!is.data.frame(fl)) return(NULL)
  fl = fl[fl$level >= 1L, , drop = FALSE]
  fl[order(-fl$level), , drop = FALSE]
}

#' Who asks (D-188): "sub-agent <label>" for a sub-agent's request, else ""
#' @noRd
ui_who = function(request) {
  a = request$agent
  if (!rlang::is_string(a) || identical(a, "main")) "" else paste0("sub-agent ", ui_escape(a))
}

#' The rows that open a console question (D-243): `?` (blue) and the title in bold, a title's
#' further lines under its text; escaped
#' @noRd
ui_question = function(title) {
  lines = console_lines(title)
  lead = c(paste0(console_style()$blue("?"), " "), rep("  ", length(lines)))
  paste0(lead[seq_along(lines)], cli::style_bold(lines))
}

#' The lines of an approval (D-243): the call line (`  | r  x = 1`, fitted to the console before
#' (+N more lines), D-187) unless the console's last printed call line is this request's, the
#' flagged calls one per line, fitted, at most 5 (D-222), why an `ask_human` request asks in
#' every mode, and the question with its keys (a and p only with a rule), wrapped between them
#' @noRd
ui_permission_lines = function(request) {
  sym = console_style()
  lines = ui_request_lines(request)
  lines = lines[nzchar(trimws(lines))]
  more = if (length(lines) > 1L) paste0("  (+", length(lines) - 1L, " more lines)") else ""
  tool = ui_escape(request$tool %||% "tool")
  first = paste0("  ", sym$red(sym$tool), " ", cli::style_bold(tool), "  ", c(lines, "")[1L])
  shown = rlang::is_string(request$tool_call_id) &&
    identical(console_state()$last_call, c(request$session, request$tool_call_id))
  width = max(20L, cli::console_width() - nchar(console_pad()))
  fl = ui_flagged(request$risk)
  n = NROW(fl)
  why = request$reason
  who = ui_who(request)
  can = is.null(ui_no_rule(request))
  keys = c("y", if (can) c("a", "p"), "n", "?")
  what = c("yes", if (can) c("always (session)", "always (project)"), "no", "more")
  # no-break spaces keep a key with its words when the line wraps
  opts = paste0(cli::style_bold(keys), sym$dim(paste0(gsub(" ", "\u00a0", paste0(" ", what)),
                                                      c(rep(sym$sep, length(keys) - 1L), ""))),
                collapse = "")
  q = if (nzchar(who)) paste0(who, ": allow ", tool, "?") else paste0("Allow ", tool, "?")
  ask = paste0("  ", ui_question(q), "\u00a0\u00a0", opts)
  c(if (!shown) paste0(cli::ansi_strtrim(first, max(20L, width - nchar(more))), more),
    if (n) {
      k = seq_len(min(n, 5L))
      rows = paste0(c("     flagged: ", rep(strrep(" ", 14L), 4L))[k], "[", fl$level[k], " ",
                    fl$category[k], "] ", ui_escape(fl$call[k]))
      cli::ansi_strtrim(c(rows, if (n > 5L) {
        paste0(strrep(" ", 14L), "(+", n - 5L, " more; ? shows all)")
      }), width)
    },
    if (identical(request$tier, "ask_human") && rlang::is_string(why) && nzchar(why)) {
      paste0("     asks in every mode: ", ui_escape(why))
    },
    gsub("\u00a0", " ", console_wrap(ask, width), fixed = TRUE))
}

#' The detail view shown for `?`: the code as a plain fence (it also feeds the RStudio dialog),
#' a cut one ending in a `# ... +N more lines` line inside the fence (D-207)
#' @noRd
ui_permission_detail = function(request) {
  risk = request$risk
  lines = ui_request_lines(request)
  shown = utils::head(lines, 40L)
  fence = doc_rmd_fence("```", shown)
  who = ui_who(request)
  out = c(paste0("  ", if (nzchar(who)) who else "gptr", " wants to use ",
                 ui_escape(request$tool %||% "a tool"),
                 if (!is.null(risk$level)) {
                   paste0(" (level ", risk$level,
                          if (rlang::is_string(risk$label)) paste0(": ", ui_escape(risk$label)),
                          ")")
                 },
                 if (identical(request$tier, "ask_human")) ", which needs your decision"),
          if (rlang::is_string(request$reason) && nzchar(request$reason)) {
            paste0("  reason: ", ui_escape(request$reason))
          },
          paste0("  ", c(paste0(fence, if (grepl("(^|__)r$", request$tool %||% "")) "r"), shown,
                         if (length(lines) > 40L) {
                           paste0("# ", console_style()$ellipsis, " +", length(lines) - 40L,
                                  " more lines")
                         },
                         fence)))
  fl = ui_flagged(risk)
  if (NROW(fl)) {
    where = ifelse(is.na(fl$path), "",
                   paste0("  path: ", ui_escape(fl$path), " (", fl$path_class, ")"))
    out = c(out, "  flagged calls:",
            paste0("    [", fl$level, "] ", fl$category, "  ", ui_escape(fl$call), where))
  }
  note = request$undo_note %||% ui_undo_note(request)
  if (rlang::is_string(note) && nzchar(note)) out = c(out, paste0("  ", ui_escape(note)))
  c(out, "  [y] yes",
    if (is.null(ui_no_rule(request))) {
      paste0(c("  [a] always in this session: ", "  [p] always in this project: "),
             ui_escape(request$suggested_rule))
    },
    "  [n] no (type n <what to do instead> to tell gptr)", "  Ctrl-C: abort the run")
}

#' The "cannot be undone" note of the checkpoint.note service (P16) for a request without one
#' @noRd
ui_undo_note = function(request) {
  if (!ext_service_has("checkpoint.note")) return(NULL)
  call = list(name = request$tool, input = request$input, risk = request$risk,
              nested = isTRUE(request$nested))
  tryCatch(ext_service_get("checkpoint.note")(call, NULL), error = function(e) NULL)
}

#' Read one console answer, never a line typed before the question (readline_answer()); when the
#' REPL's reader finds lines waiting after the answer (a paste; a last line without a newline is
#' not waiting), the answer and the lines go to the console history as one entry (a `secret` is
#' dropped) and the question is asked again (IC-75); Ctrl-C or EOF gives NA (a terminal echoes
#' even a `secret` itself)
#' @noRd
ui_console_read = function(prompt, secret = FALSE) {
  rd = console_repl_find()$reader
  repeat {
    ans = tryCatch(readline_answer(prompt, if (!secret) console_typed_ahead),
                   interrupt = function(e) NA_character_)
    if (!rlang::is_string(ans)) return(NA_character_)
    more = if (!is.null(rd)) rd$waiting()
    if (!length(more)) return(ans)
    kept = !secret && console_history_add(paste(c(ans, more), collapse = "\n"))
    console_write(paste0("  A pasted block is not an answer", if (kept) " (kept in history)", "."))
  }
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

#' Console select() (D-243): `? <title>`, its details dim under it, the numbered choices, a dim
#' hint and the person's chevron at column 0; NA = cancelled; attr "other" = free text
#' Title line feeds are intentional (also for ask questions); labels and details stay escaped.
#' @noRd
ui_console_select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                             allow_other = FALSE, read = ui_console_read) {
  rlang::local_options(cli.num_colors = console_colors())
  # in a run in the console margin console_before_message() writes the block's separator
  run = console_before_message(kind = "prompt", tools = TRUE)
  pad = console_pad()
  sym = console_style()
  labels = as.character(unlist(choices))
  hint = paste0("Choose ", paste(c(if (multiple) "numbers separated by commas" else "a number",
                                   if (allow_other) "or type your own answer"), collapse = ", "),
                if (length(default)) paste0("; Enter = ", paste(labels[default], collapse = ", ")))
  console_write(c(if (!run || !nzchar(pad)) "", paste0(pad, ui_question(title)),
                  if (length(details)) paste0(pad, "  ", sym$dim(ui_escape(details))),
                  paste0(pad, "  ", cli::style_bold(format(seq_along(labels))), "  ",
                         ui_escape(labels)),
                  paste0(pad, sym$dim(ui_escape(hint)))))
  for (attempt in seq_len(5L)) {
    ans = read(paste0(sym$person, " "))
    if (is.na(ans)) return(NA_integer_)
    if (!nzchar(trimws(ans)) && length(default)) return(as.integer(default))
    idx = ui_parse_choice(ans, labels, multiple)
    if (!anyNA(idx)) return(idx)
    if (allow_other && nzchar(trimws(ans))) return(structure(NA_integer_, other = trimws(ans)))
    console_write("  Please enter one of the numbers shown.")
  }
  NA_integer_
}

#' Console input() (D-243): `? <prompt>`, a dim `Enter = <default>` and the person's chevron;
#' NA = cancelled; a secret is asked through RStudio's masked dialog there
#' @noRd
ui_console_input = function(prompt, default = "", secret = FALSE, read = ui_console_read) {
  rlang::local_options(cli.num_colors = console_colors())
  console_before_message(kind = "prompt", tools = TRUE)
  if (isTRUE(secret) && ui_rstudio()) {
    ans = tryCatch(rstudioapi::askForPassword(prompt), error = function(e) NULL)
    return(if (rlang::is_string(ans)) as_utf8(ans) else NA_character_)
  }
  pad = console_pad()
  sym = console_style()
  hint = if (nzchar(default)) paste0(pad, sym$dim(ui_escape(paste0("Enter = ", default))))
  console_write(c(paste0(pad, ui_question(prompt)), hint))
  ans = read(paste0(sym$person, " "), secret = isTRUE(secret))
  if (!is.na(ans) && !nzchar(ans)) default else ans
}

#' Console permission(): the approval of NS-1 under the call it gates, read after the person's
#' chevron (D-243), `?` for the detail view; every console prompt first ends partial answer lines
#' and clears waiting rows (D-186); a remembered answer adds a dim line naming the rule; an
#' invalid answer is quoted (kept in the console history in an interactive session) above a hint
#' with the question's keys, an empty one gets the hint alone, both wrapped at the prompt rows'
#' width; five (`?` is none) end in a refusal whose feedback says so (D-188, D-243)
#' @noRd
ui_console_permission = function(request, read = ui_console_read) {
  rlang::local_options(cli.num_colors = console_colors())
  console_before_message(kind = "prompt", tools = TRUE)
  why = ui_no_rule(request)
  can = is.null(why)
  console_write(ui_permission_lines(request))
  sym = console_style()
  bad = 0L
  while (bad < 5L) {
    a = trimws(read(paste0(sym$person, " ")))
    if (is.na(a)) return(ui_answer("abort"))
    low = tolower(a)
    if (low %in% c("y", "yes")) return(ui_answer("allow"))
    if (can && low %in% c("a", "always", "p", "project")) {
      scope = if (low %in% c("a", "always")) "session" else "project"
      console_write(sym$dim(paste0("    allowed ", ui_escape(request$suggested_rule), " for this ",
                                   scope)))
      return(ui_answer("allow", scope))
    }
    if (grepl("^no?(\\s|$)", low)) {
      fb = trimws(sub("^no?", "", a, ignore.case = TRUE))
      return(ui_answer("deny", feedback = if (nzchar(fb)) fb))
    }
    if (low == "?") {
      console_write(ui_permission_detail(request))
      next
    }
    bad = bad + 1L
    if (low %in% c("a", "always", "p", "project")) {
      msg = paste0("  a and p are not offered: ", why, "; answer y, n or ?.")
    } else {
      kept = nzchar(a) && gptr_is_interactive() && console_history_add(a)
      msg = c(if (nzchar(a)) {
        paste0("  Not an answer: '", ui_escape(substr(a, 1L, 40L)), "'",
               if (kept) " (kept in history)", ".")
      }, paste0("  Type ", if (can) "y, a, p or n" else "y or n",
                " (n <text> says what to do instead), or ?."))
    }
    console_write(console_wrap(msg, max(20L, cli::console_width() - nchar(console_pad()))))
  }
  console_write("  No valid answer after 5 tries; refused.")
  ui_answer("deny", feedback = "no valid answer was given at the approval prompt")
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
                return(ui_answer("deny", feedback = "The scripted UI has no answer left."))
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
              ok = tryCatch(rstudioapi::showQuestion("gptr permission",
                                                     paste(ui_permission_detail(request),
                                                           collapse = "\n"),
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

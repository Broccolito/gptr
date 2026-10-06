# console-ui.R -- the UI backends console, none, scripted and rstudio (builtin:ui, P11) and the
# ui.get service. Adapted from report 18 Appendix A.3 (c1_ui.R) and A.4 (permission_prompt()):
# the one-line prompt of architecture 6.8.3 / NS-1 with IC-53's display rules (every flagged call,
# "+N more lines", controls, bidi and zero-width characters as <U+XXXX>). Never askYesNo(), menu()
# or select.list(). A front-end file (L5): it calls no perm-* function, so a remembered answer
# reaches builtin:permissions as the channel event `permissions:remember`.

#' Escape control (except TAB), bidi and zero-width characters for display as <U+XXXX>
#'
#' The rule of perm-classify.R's risk_escape(); a front-end file may not call a capability file
#' (architecture section 2.2).
#' @noRd
ui_escape = function(x) {
  vapply(as_utf8(as.character(x)), function(s) {
    cp = utf8ToInt(s)
    if (anyNA(cp)) return(iconv(s, "UTF-8", "ASCII", sub = "byte"))
    bad = (cp <= 0x1F & cp != 0x09) | (cp >= 0x7F & cp <= 0x9F) | cp == 0x061C |
      (cp >= 0x200B & cp <= 0x200F) | (cp >= 0x202A & cp <= 0x202E) |
      (cp >= 0x2060 & cp <= 0x2069) | cp == 0xFEFF
    out = vapply(cp, intToUtf8, character(1))
    out[bad] = sprintf("<U+%04X>", cp[bad])
    paste(out, collapse = "")
  }, character(1), USE.NAMES = FALSE)
}

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
    ui_can_remember(request)
  fb = ans[["feedback"]]
  ui_answer(ans[["decision"]], if (keep) rem, if (rlang::is_string(fb) && nzchar(fb)) fb)
}

#' May an approval of this request become a rule? Never for level 4, control or the ask tool
#' @noRd
ui_can_remember = function(request) {
  risk = request$risk
  !identical(request$tool, "ask") && isTRUE(risk$level < 4L) &&
    !"control" %in% c(risk$categories, risk$flagged$category)
}

#' The escaped lines a request shows: its code, else its path, else P06's summary
#' @noRd
ui_request_lines = function(request) {
  input = request$input
  ui_escape(text_lines(input[["code"]] %||% input[["path"]] %||% request$summary))
}

#' The flagged calls (level >= 1) of a risk record, or NULL
#' @noRd
ui_flagged = function(risk) {
  fl = risk$flagged
  if (is.data.frame(fl)) fl[fl$level >= 1L, , drop = FALSE]
}

#' The lines of the one-line prompt: the first line (+N more lines) and every flagged call (IC-53)
#' @noRd
ui_permission_lines = function(request) {
  lines = ui_request_lines(request)
  lines = lines[nzchar(trimws(lines))]
  more = if (length(lines) > 1L) paste0("  (+", length(lines) - 1L, " more lines)")
  fl = ui_flagged(request$risk)
  c(paste0("  ", ui_escape(request$tool %||% "tool"), "  ", cap_lines(c(lines, "")[1L], 72L), more),
    if (NROW(fl)) {
      paste0("     flagged: ", paste0(ui_escape(fl$call), " [", fl$level, " ", fl$category, "]",
                                     collapse = "; "))
    })
}

#' The detail view shown for `?`
#' @noRd
ui_permission_detail = function(request) {
  risk = request$risk
  lines = ui_request_lines(request)
  out = c(paste0("  gptr wants to use ", ui_escape(request$tool %||% "a tool"),
                 if (!is.null(risk$level)) {
                   paste0(" (level ", risk$level, ": ", ui_escape(risk$label %||% ""), ")")
                 },
                 if (identical(request$tier, "ask_human")) ", which needs your decision"),
          if (rlang::is_string(request$reason) && nzchar(request$reason)) {
            paste0("  reason: ", ui_escape(request$reason))
          },
          paste0("    > ", utils::head(lines, 40L)),
          if (length(lines) > 40L) paste0("    > ... (+", length(lines) - 40L, " more lines)"))
  fl = ui_flagged(risk)
  if (NROW(fl)) {
    where = ifelse(is.na(fl$path), "",
                   paste0("  path: ", ui_escape(fl$path), " (", fl$path_class, ")"))
    out = c(out, "  flagged calls:",
            paste0("    [", fl$level, "] ", fl$category, "  ", ui_escape(fl$call), where))
  }
  note = request$undo_note %||% ui_undo_note(request)
  if (rlang::is_string(note) && nzchar(note)) out = c(out, paste0("  ", ui_escape(note)))
  rule = request$suggested_rule
  rule = if (rlang::is_string(rule)) paste0(": ", ui_escape(rule)) else " (a rule for these calls)"
  c(out, "  [y] yes",
    if (ui_can_remember(request)) {
      paste0(c("  [a] always in this session", "  [p] always in this project"), rule)
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

#' Read one console line; Ctrl-C or EOF gives NA
#' @noRd
ui_console_read = function(prompt) {
  ans = tryCatch(gptr_readline(prompt), interrupt = function(e) NA_character_)
  if (rlang::is_string(ans)) ans else NA_character_
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

#' Console select(): numbered choices; NA = cancelled; attr "other" = free text
#' @noRd
ui_console_select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                             allow_other = FALSE) {
  labels = as.character(unlist(choices))
  msg_verbatim(ui_escape(c("", title, if (length(details)) paste0("  | ", details),
                           sprintf("  %d: %s", seq_along(labels), labels))))
  hint = c(if (multiple) "numbers separated by commas" else "a number",
           if (allow_other) "or type your own answer",
           if (length(default)) paste0("Enter = ", paste(labels[default], collapse = ", ")))
  for (attempt in seq_len(5L)) {
    ans = ui_console_read(ui_escape(paste0("Choose (", paste(hint, collapse = "; "), "): ")))
    if (is.na(ans)) return(NA_integer_)
    if (!nzchar(trimws(ans)) && length(default)) return(as.integer(default))
    idx = ui_parse_choice(ans, labels, multiple)
    if (!anyNA(idx)) return(idx)
    if (allow_other && nzchar(trimws(ans))) return(structure(NA_integer_, other = trimws(ans)))
    msg_verbatim("  Please enter one of the numbers shown.")
  }
  NA_integer_
}

#' Console input(); NA = cancelled; a secret is asked through RStudio's masked dialog there
#' @noRd
ui_console_input = function(prompt, default = "", secret = FALSE) {
  if (isTRUE(secret) && ui_rstudio()) {
    ans = tryCatch(rstudioapi::askForPassword(prompt), error = function(e) NULL)
    return(if (rlang::is_string(ans)) as_utf8(ans) else NA_character_)
  }
  ans = ui_console_read(ui_escape(paste0(prompt, if (nzchar(default)) paste0(" [", default, "]"),
                                         ": ")))
  if (!is.na(ans) && !nzchar(ans)) default else ans
}

#' Console permission(): the one-line prompt of NS-1, `?` for the detail view
#' @noRd
ui_console_permission = function(request) {
  can = ui_can_remember(request)
  opts = if (can) "[y]es / [a]lways / [n]o / [?]" else "[y]es / [n]o / [?]"
  msg_verbatim(ui_permission_lines(request))
  for (attempt in seq_len(5L)) {
    a = trimws(ui_console_read(paste0("  allow? ", opts, ": ")))
    if (is.na(a)) return(ui_answer("abort"))
    low = tolower(a)
    if (low %in% c("y", "yes")) return(ui_answer("allow"))
    if (can && low %in% c("a", "always")) return(ui_answer("allow", "session"))
    if (can && low %in% c("p", "project")) return(ui_answer("allow", "project"))
    if (grepl("^no?(\\s|$)", low)) {
      fb = trimws(sub("^no?", "", a, ignore.case = TRUE))
      return(ui_answer("deny", feedback = if (nzchar(fb)) fb))
    }
    msg_verbatim(if (low == "?") ui_permission_detail(request) else paste0("  Answer ", opts, "."))
  }
  ui_answer("deny")
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

#' The `console` UI: readline() through gptr_readline() (IRkernel answers it too, IC-43)
#' @noRd
ui_console_spec = function() {
  gptr_spec("ui", "console",
            has_ui = function() isTRUE(gptr_can_prompt()),
            select = ui_console_select,
            input = ui_console_input,
            questions = function(qs) ui_questions_via(ui_console_select, ui_console_input, qs),
            notify = function(text, level = "info") {
              msg_verbatim(paste0("[", level, "] ", ui_escape(text)), "stderr")
            },
            permission = ui_console_permission)
}

#' The `none` UI: nobody answers; P02's defaults fail closed (contract section 10.2 row 22)
#' @noRd
ui_none_spec = function() {
  gptr_spec("ui", "none", has_ui = function() FALSE, select = function(...) NA_integer_,
            notify = function(text, level = "info") gptr_inform(text, "notice"))
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
            notify = function(text, level = "info") gptr_inform(text, "notice"),
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

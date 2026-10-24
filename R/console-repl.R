# console-repl.R -- the `console` built-in (P14, layer L5, area console; contract 7.14, 10.3):
# the REPL behind `peter()` with no prompt (report 18 section 4.3) and its input grammar
# (architecture 6.17). Options read here (contract 3.1): gptr.max_turns_console, gptr.history.

#' REPL state: an environment (`envir` is reset to NULL when the REPL ends, rule R2)
#'
#' `call` is the gateway's `gptr_call` record of the console call (contract 7.8): its resolved
#' identifiers, budget and `.opts` apply to the first prompt, also on a piped session, and its
#' plain-symbol context objects are attached to it.
#' @noRd
repl_state = function(session, envir, stdin = FALSE, call = NULL) {
  check_class(session, "gptr_session", "s", null = TRUE)
  check_env(envir, "envir")
  check_flag(stdin, "stdin")
  rs = new.env(parent = emptyenv())
  rs$session = session
  rs$envir = envir
  rs$envir_given = isTRUE(call$args$envir_given)
  rs$stdin = stdin
  rs$reader = NULL
  ids = call$ids
  rs$model = ids$model
  rs$mode = ids$mode
  rs$skills = ids$skills
  rs$tools = ids$tools
  rs$plugins = ids$plugins
  rs$extensions = ids$extensions
  rs$budget = call$args$budget
  opts = call$args$opts %||% list()
  opts$frontend = NULL
  rs$opts = opts
  syms = Filter(function(item) identical(item$kind, "symbol") && is.character(item$name),
                call$context)
  rs$attach = unique(vapply(syms, function(item) item$name, ""))
  rs$pending_call = !is.null(call)
  rs$notes = character()
  rs$files = character()
  rs$next_skills = NULL
  rs$sending = NULL
  rs$mask = NULL
  rs$exit = FALSE
  rs$interrupts = 0L
  rs$waiting = 0L
  rs
}

#' Where `!expr` runs and prompts evaluate (IC-40): an explicit `envir` of the console call, else
#' the session's kept home, else the console call's environment
#' @noRd
repl_eval_env = function(rs) {
  if (isTRUE(rs$envir_given) || is.null(rs$session)) return(rs$envir)
  session_home(rs$session) %||% rs$envir
}

#' @noRd
repl_mode = function(rs) {
  if (!is.null(rs$session)) return(rs$session$mode)
  rs$mode %||% setting_get("mode", default = "manual")
}

#' The model as a label; a resolved model may be a provider or router spec
#' @noRd
repl_model = function(rs) {
  if (!is.null(rs$session)) return(rs$session$model)
  m = rs$model
  if (inherits(m, "gptr_spec")) m = m$id %||% m$name
  as.character(m %||% setting_get("model") %||% "the default model")[1L]
}

#' The prompt: `"peter> "` in manual mode, `"peter[<mode>]> "` otherwise
#' @noRd
repl_prompt = function(rs) {
  mode = repl_mode(rs)
  if (identical(mode, "manual")) "peter> " else paste0("peter[", mode, "]> ")
}

#' The persistent stdin connection of `peter(.stdin = TRUE)` (tests mock this function): a fresh
#' file("stdin") per read loses buffered lines (report 18 2.1.3). Where R reads its own commands
#' from the process's standard input (`R < file`: not interactive, no -f, --file= or -e), R's
#' console connection, whose buffer already holds the lines after the call
#' @noRd
console_stdin_open = function() {
  args = commandArgs()
  args = args[seq_len(match("--args", args, nomatch = length(args) + 1L) - 1L)]
  piped = !interactive() && !any(args %in% c("-f", "-e") | startsWith(args, "--file="))
  if (piped) stdin() else file("stdin", open = "r")
}

#' The longest console line readline() delivers whole (report 18 fact-check 2)
#' @noRd
readline_limit = function() {
  if (getRversion() >= "4.5.0") 8190L else 4095L
}

#' A line reader: gptr_readline() or the persistent stdin connection (closed by `close()`, IC-59)
#'
#' Returns an environment with `read(prompt = "", stream = "stdout", secret = FALSE)` -> chr(1), NA
#' at the end of piped input; `waiting()` -> the lines a paste left on a macOS terminal (none
#' elsewhere, IC-75); `close()`; `flag` (TRUE when a line reached the readline limit); `held`,
#' the lines a paste left after a block's closer, which the terminal reader returns first,
#' unechoed (the terminal showed them); `typed`, the /command and !code lines and the follow-ups
#' typed during an answer, which it returns next, in order, echoed after the prompt (IC-76,
#' D-242); `compose`, the state of a T console's composer (console_compose(): its draft), whose
#' draft a run left it then edits at the prompt (console_idle()), the line sent echoed alike, on
#' the input band (console_band()) as are readline()'s prompts in a T console (IC-82),
#' `sent`, the kind of message queued last (policy_enqueue()), and `complete`, TRUE where the REPL
#' completes after its trigger characters (repl_main(), IC-81): the console reader's readline()
#' then has console_completer() as R's custom completer, the caller's kept for ! lines, but at
#' `+ `, where the line continues !code and R's own completion applies; `caller`, list() of the
#' caller's completer where the REPL's is installed for its whole life (RStudio). With `echo` the
#' stdin reader writes the prompt and the escaped line (never a `secret` one) on `stream`, so a
#' piped session reads like a terminal session.
#' @noRd
console_reader = function(stdin = FALSE, echo = stdin) {
  rd = new.env(parent = emptyenv())
  rd$flag = FALSE
  rd$con = NULL
  rd$fd = NULL
  rd$held = character()
  rd$typed = character()
  # only a macOS terminal (BSD tty driver) hands a waiting paste over as complete lines
  paste_tty = !isTRUE(stdin) && is_macos() && console_readline_tty()
  rd$waiting = function() if (paste_tty) console_typed_lines(rd) else character()
  echo = isTRUE(echo)
  if (isTRUE(stdin)) {
    rd$con = console_stdin_open()
    # a question's `accept` (ui_console_read()) means nothing on a pipe
    rd$read = function(prompt = "", stream = "stdout", secret = FALSE, ...) {
      if (is.null(rd$con)) return(NA_character_)
      stream = gptr_message_stream(stream)
      if (echo) gptr_message_write(prompt, stream)
      # R's console connection echoes what it reads where R echoes its input; the reader echoes
      if (as.integer(rd$con) == 0L) {
        old = options(echo = FALSE)
        on.exit(options(old), add = TRUE)
      }
      x = readLines(rd$con, n = 1L, warn = FALSE, encoding = "UTF-8")
      if (!length(x)) {
        if (echo) gptr_message_write("\n", stream)
        return(NA_character_)
      }
      x = as_utf8(x)
      if (echo) gptr_message_write(paste0(if (!secret) console_escape(x, FALSE), "\n"), stream)
      x
    }
  } else {
    # RStudio's console completes nothing in a frame identical() to base::readline (D-183)
    rl = structure(readline, gptr = TRUE)
    rd$read = function(prompt = "", stream = "stdout") {
      if (length(rd$held)) {
        x = rd$held[[1L]]
        rd$held = rd$held[-1L]
        return(x)
      }
      x = NULL
      if (length(rd$typed)) {
        x = rd$typed[[1L]]
        rd$typed = rd$typed[-1L]
      } else if (nzchar(rd$compose$draft %||% "")) {
        x = console_idle(rd, prompt)
      }
      if (!is.null(x)) {
        console_write(console_band(strsplit(paste0(prompt, console_escape(x)), "\n")[[1L]]))
        return(x)
      }
      # the idle editor's modes, echo off, are restored as the last step before readline(), whose
      # prompt erases its row for a key the terminal echoed in that moment
      tty = rd$handed
      rd$handed = NULL
      on.exit(tty_restore(tty), add = TRUE)
      if (isTRUE(rd$complete)) {
        prev = utils::rc.getOption("custom.completer")
        caller = if (is.null(rd$caller)) prev else rd$caller[[1L]]
        utils::rc.options(custom.completer = if (identical(prompt, "+ ")) caller else
          console_completer(caller))
        on.exit(utils::rc.options(custom.completer = prev), add = TRUE)
      }
      # on the input band, as a question's answer is (band_read())
      x = band_read(prompt, function(p) {
        if (!is.null(tty)) {
          p = paste0("\001\r\033[K\002", p)
          tty_restore(tty)
        }
        gptr_readline(p, rl)
      })
      if (length(x) != 1L || is.na(x)) return(NA_character_)
      n = nchar(x, type = "bytes")
      if (n >= readline_limit()) {
        rd$flag = TRUE
        gptr_warn(paste0("That line was ", n, " bytes long, at the console limit of ",
                         readline_limit(), " bytes: its end was dropped (on R < 4.5 the next ",
                         "line you entered was merged into it), so it was not sent. ",
                         "Use @file or a \"\"\" block for long input."),
                  "readline_limit")
      }
      x
    }
  }
  rd$close = function() {
    con = rd$con
    rd$con = NULL
    rd$fd = NULL
    # R's console connection (number 0) stays open
    if (!is.null(con) && as.integer(con) != 0L) close(con)
    invisible(NULL)
  }
  rd
}

#' The terminal's background, asked once at a T REPL's start (IC-82, D-245): OSC 11 with a DA1
#' query after it, whose reply ends the wait (tty_query()); an answer sets `the$background`
#' (background_reply()), else COLORFGBG decides (console_background()). Not asked where no band
#' shows, below 256 colours (`NO_COLOR` too), nor on the Linux console. Keys typed meanwhile are
#' the reader `rd`'s, each line read as the composer reads it (console_line_text()): each line they
#' end that is not blank is a next prompt of its own, as readline would have read it, the rest a
#' draft at the prompt (console_idle()). Asked after the first-use setup, whose menu reads first
#' @noRd
repl_background = function(rd) {
  if (cli::num_ansi_colors() < 256L || identical(Sys.getenv("TERM"), "linux")) {
    return(invisible(NULL))
  }
  got = tty_query("\033]11;?\033\\\033[c")
  bg = background_reply(got)
  if (!is.na(bg)) the$background = bg
  lines = console_typed_split(tty_unreply(got))
  part = isTRUE(attr(lines, "partial"))
  typed = vapply(lines, console_line_text, "", USE.NAMES = FALSE)
  ended = typed[seq_along(typed) < length(typed) + !part]
  rd$typed = c(rd$typed, ended[nzchar(trimws(ended))])
  draft = if (part) typed[[length(typed)]] else ""
  if (nzchar(draft)) rd$compose = list(draft = draft)
  invisible(NULL)
}

#' Does this REPL read a terminal, whose typed lines wait on fd 0 while an answer runs (IC-76)? A
#' T or D console (console_class()), not a piped REPL. Not on Windows: processx cannot poll a
#' console handle; not in Positron's console, whose own input holds what is typed
#' @noRd
repl_terminal = function(rs) {
  !isTRUE(rs$stdin) && console_class() %in% c("T", "D")
}

#' The text typed or pasted on fd 0 that waits to be read, without blocking: one
#' conn_read_chars() per ready poll (the first waits `wait` ms, later ones 50 ms), as a line read
#' waits for a newline a partial line never sends. `rd$fd` is reopened after an end of input and
#' dropped, never closed: closing it closes fd 0 (IC-75). An error reads nothing, as it would end
#' the REPL.
#' @noRd
console_typed_chars = function(rd, wait = 50L) {
  tryCatch({
    if (is.null(rd$fd) || !processx::conn_is_incomplete(rd$fd)) {
      rd$fd = processx::conn_create_fd(0L, close = FALSE)
    }
    txt = ""
    while (identical(processx::poll(list(rd$fd), wait)[[1L]], "ready")) {
      x = processx::conn_read_chars(rd$fd)
      if (!nzchar(x)) break
      txt = paste0(txt, x)
      wait = 50L
    }
    txt
  }, error = function(e) "")
}

#' The lines typed or pasted on fd 0 that wait to be read (console_typed_chars())
#' @noRd
console_typed_lines = function(rd, wait = 50L) {
  console_typed_split(console_typed_chars(rd, wait))
}

#' The lines of text read from fd 0 (`\r\n`, `\r` or `\n` ends one); attr "partial" (TRUE) marks
#' a last line without a line end: a partial line in the drain's mode (tty_drain_mode()), else a
#' line Ctrl-D ended
#' @noRd
console_typed_split = function(txt) {
  lines = if (nzchar(txt)) as_utf8(strsplit(txt, "\r\n|\r|\n")[[1L]]) else character()
  if (grepl("[^\r\n]$", txt)) attr(lines, "partial") = TRUE
  lines
}

#' Lines held or waiting after an input line (a paste) join it, then one more line is read at
#' "... ": Enter sends, typed text is appended (it ends a paste whose last line had no newline).
#' After a line at the readline limit the waiting lines are dropped with it.
#' @noRd
repl_paste_more = function(rd, text) {
  more = c(rd$held, rd$waiting())
  rd$held = character()
  if (!length(more) || rd$flag) return(text)
  console_notice(console_style()$dim("  (pasted: Enter sends it as one message)"))
  x = rd$read("... ")
  paste(c(text, more, if (!is.na(x) && nzchar(x)) x), collapse = "\n")
}

#' Is R code incomplete? Locale-independent (the messages are translated): the parse error of an
#' incomplete input points at column 0 of the line after the last, or is an INCOMPLETE_STRING
#' @noRd
r_incomplete = function(code) {
  msg = tryCatch({
    parse(text = code, keep.source = FALSE)
    NULL
  }, error = conditionMessage)
  !is.null(msg) && (grepl("INCOMPLETE_STRING", msg, fixed = TRUE) ||
                      grepl("^<text>:[0-9]+:0:", msg))
}

#' Read one logical input (report 18 A.7, architecture 6.17)
#'
#' A `"""` block is one multi-line prompt; a fence with an `r`, `R`, `{r...}` or empty info string
#' is R code (returned as `!code`), any other fence prompt text (CommonMark: closed by a fence at
#' least as long, the body loses the opener's indentation); `!code` and `!!code` continue while
#' the code is incomplete; a trailing backslash continues a line; lines a paste left waiting join
#' a prompt, slash or `!code` line, and a block takes its lines from them before reading at "... "
#' (the lines after its closer stay held as the next input, IC-75); the end of piped input ends
#' every block. Returns NA at the end of input, "" when a line hit the readline limit (the whole
#' input is dropped rather than sent half).
#' @noRd
repl_read_logical = function(rd, prompt) {
  rd$flag = FALSE
  line = rd$read(prompt)
  if (is.na(line)) return(NA_character_)
  out = line
  block_line = function() {
    if (!length(rd$held) && !length(rd$typed)) rd$held = rd$waiting()
    rd$read("... ")
  }
  if (grepl('^\\s*"""', line)) {
    body = sub('^\\s*"""', "", line)
    while (!grepl('"""\\s*$', body)) {
      x = block_line()
      if (is.na(x)) break
      body = paste0(body, "\n", x)
    }
    out = trimws(sub('"""\\s*$', "", body))
  } else if (grepl("^\\s*```", line)) {
    m = regmatches(line, regexec("^(\\s*)(`+)(.*)$", line))[[1L]]
    body = character()
    repeat {
      x = block_line()
      if (is.na(x) || grepl(paste0("^\\s*", m[[3L]], "`*\\s*$"), x)) break
      body = c(body, sub(paste0("^ {0,", nchar(m[[2L]]), "}"), "", x))
    }
    out = if (grepl("^([rR]|\\{r\\b.*)?$", trimws(m[[4L]]), perl = TRUE)) {
      paste0("!", paste(body, collapse = "\n"))
    } else {
      paste(c(trimws(line), body, m[[3L]]), collapse = "\n")
    }
  } else if (startsWith(line, "!")) {
    bang = if (startsWith(line, "!!")) "!!" else "!"
    code = repl_paste_more(rd, substring(line, nchar(bang) + 1L))
    while (r_incomplete(code)) {
      x = rd$read("+ ")
      if (is.na(x)) break
      code = paste0(code, "\n", x)
    }
    out = paste0(bang, code)
  } else {
    out = repl_paste_more(rd, line)
    while (endsWith(out, "\\")) {
      out = substr(out, 1L, nchar(out) - 1L)
      x = rd$read("... ")
      if (is.na(x)) break
      out = paste0(out, "\n", x)
    }
  }
  if (rd$flag) "" else out
}

# ---------------------------------------------------------------------------------------------
# `!expr`, notes, @mentions and the prompt call (Task 5). `!code` and `!!code` are the user's own
# R: evaluated through the `eval.r` service in the REPL's environment (no permission gate, no
# guard), shown as it runs; `!code` also leaves a note that the `user_ran` block adds to the next
# prompt within 300 tokens (IC-73). `@file` mentions add the file's head to the `user_files`
# block; `@object` mentions attach the object by name (P09's `attached` block describes it).
# Both blocks answer only the gateway call that console_send() built: the call record's
# `sys_call` is that call.
# ---------------------------------------------------------------------------------------------

#' Escape an attribute value of a context tag
#' @noRd
attr_escape = function(x) {
  gsub("\"", "&quot;", gsub("&", "&amp;", x, fixed = TRUE), fixed = TRUE)
}

#' The <file> block of an @file mention: the first 40 lines of a text file (redacted with the
#' `context` profile), or a one-line note for a binary file (report 18 section 4.3); attr "said"
#' names what it holds (`2 lines`, `first 40 lines`, `binary, 3 bytes`)
#' @noRd
repl_file_block = function(path, shown, max_lines = 40L) {
  head_raw = readBin(path, "raw", n = 8192L)
  if (any(head_raw == as.raw(0L))) {
    bytes = format(file.size(path), scientific = FALSE)
    return(structure(paste0("<file path=\"", attr_escape(shown), "\" binary=\"true\" bytes=\"",
                            bytes, "\"/>"), said = paste0("binary, ", bytes, " bytes")))
  }
  x = readLines(path, n = max_lines + 1L, warn = FALSE, encoding = "UTF-8")
  more = length(x) > max_lines
  n = min(length(x), max_lines)
  x = redact(clean_terminal(utils::head(x, max_lines)), profile = "context")
  structure(paste0("<file path=\"", attr_escape(shown), "\"", if (more) " truncated=\"true\"",
                   ">\n", paste(x, collapse = "\n"), "\n</file>"),
            said = paste0(if (more) "first ", n, if (n == 1L) " line" else " lines"))
}

#' The objects an @mention names: those bound in `env` and its parents up to the global
#' environment, names starting with a dot only with `all` (ls() forces nothing; namespaces and
#' base are not searched, so `@c` is not the function c), sorted
#' @noRd
console_objects = function(env, all = TRUE) {
  out = character()
  e = env
  while (!identical(e, emptyenv()) && !isNamespace(e) && !identical(e, baseenv())) {
    out = c(out, ls(e, all.names = all, sorted = FALSE))
    if (identical(e, globalenv())) break
    e = parent.env(e)
  }
  sort(unique(out), method = "radix")
}

#' Resolve @mentions, words starting with @ (readline's word breaks before it, as for completion,
#' so an e-mail address stays text): files (relative to the working directory or the project root,
#' or absolute/home paths) become <file> blocks; syntactic names bound in `env` become context
#' objects passed by name. `said` names what each mention resolved to, in order (D-244): `@ notes.md
#' (2 lines)`, `@ fit (lm)` or `@ tbl (data.frame, 32 x 11)` (its class and dimensions), or
#' `@ fit2 not found, sent as text` (`is a folder` for a directory), each `@ ` and the name
#' @noRd
repl_mentions = function(text, env) {
  pattern = "(?<![^\\s\"'\\\\`><=%;,|&{()}!])@(\"[^\"]+\"|[A-Za-z0-9_./~-]*[A-Za-z0-9_/~-])"
  toks = regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1L]]
  files = character()
  objects = character()
  said = character()
  for (t in unique(toks)) {
    nm = gsub("^@\"?|\"$", "", t)
    cand = unique(c(path.expand(nm), file.path(project_root(), nm)))
    dir = path_info(cand)$isdir
    hit = cand[dir %in% FALSE]
    if (length(hit)) {
      shown = path_rel(hit[[1L]])
      block = repl_file_block(hit[[1L]], shown)
      files = c(files, block)
      said = c(said, paste0("@ ", shown, " (", attr(block, "said"), ")"))
    } else if (identical(make.names(nm), nm) && nm %in% console_objects(env)) {
      objects = c(objects, nm)
      said = c(said, paste0("@ ", nm, " (", mention_kind(nm, env), ")"))
    } else {
      said = c(said, paste0("@ ", nm, if (any(dir %in% TRUE)) " is a folder" else " not found",
                            ", sent as text"))
    }
  }
  list(files = files, objects = objects, said = said)
}

#' An @object's class and dimensions, `data.frame, 32 x 11`: a leaf returning a string, so no
#' frame keeps the object (architecture 6.4 R4)
#' @noRd
mention_kind = function(nm, env) {
  x = get0(nm, envir = env)
  d = paste(dim(x), collapse = " x ")
  paste0(class(x)[[1L]], if (nzchar(d)) ", ", d)
}

#' The note an `!expr` leaves for the next prompt: the code and its output as #> lines
#' (redacted with the `context` profile)
#' @noRd
repl_note = function(code, res) {
  out = strsplit(format_eval_result(res, 300L)$text, "\n", fixed = TRUE)[[1L]]
  note = paste(c(paste0("> ", strsplit(code, "\n", fixed = TRUE)[[1L]]),
                 if (length(out)) paste0("#> ", out)), collapse = "\n")
  redact(note, profile = "context")
}

#' Text of the `user_ran` block: the newest notes that fit `budget` tokens (the
#' `workspace_changes` rules, IC-73); one over-long note is cut from its end
#' @noRd
console_notes_text = function(notes, budget = 300L) {
  notes = as.character(notes)
  if (!length(notes)) return(NULL)
  header = "The user ran this R code in the session (output as #> lines):"
  # the reserve covers the "(n earlier omitted)" suffix added after the selection
  fits = function(x) {
    est_tokens(paste(c(header, " (999 earlier omitted)", x), collapse = "\n"), "r_output") <=
      budget
  }
  keep = character()
  i = length(notes)
  while (i >= 1L && fits(c(notes[[i]], keep))) {
    keep = c(notes[[i]], keep)
    i = i - 1L
  }
  if (!length(keep)) {
    lines = strsplit(notes[[length(notes)]], "\n", fixed = TRUE)[[1L]]
    while (length(lines) > 1L && !fits(c(lines, "#> [... output cut]"))) {
      lines = lines[-length(lines)]
    }
    keep = paste(c(lines, "#> [... output cut]"), collapse = "\n")
  }
  dropped = length(notes) - length(keep)
  if (dropped > 0L) header = paste0(header, " (", dropped, " earlier omitted)")
  paste(c(header, keep), collapse = "\n")
}

#' Text of the `user_files` block: the <file> blocks that fit `budget` tokens, in order
#' @noRd
console_files_text = function(files, budget = 2000L) {
  files = as.character(files)
  if (!length(files)) return(NULL)
  keep = character()
  for (f in files) {
    if (est_tokens(paste(c(keep, f), collapse = "\n"), "code") > budget) break
    keep = c(keep, f)
  }
  if (!length(keep)) {
    lines = strsplit(files[[1L]], "\n", fixed = TRUE)[[1L]]
    while (length(lines) > 2L && est_tokens(paste(lines, collapse = "\n"), "code") > budget) {
      lines = lines[-(length(lines) - 1L)]
    }
    keep = paste(lines, collapse = "\n")
  }
  paste(keep, collapse = "\n")
}

#' The REPL whose prompt call is being assembled, when `ctx` renders that call's context
#' @noRd
repl_sending = function(ctx) {
  rs = console_repl_find()
  if (is.null(rs$sending) || !identical(ctx$input$call$sys_call, rs$sending)) return(NULL)
  rs
}

#' provide() of the `user_ran` context block: the pending `!expr` notes (taken once)
#' @noRd
console_notes_provide = function(ctx, budget) {
  rs = repl_sending(ctx)
  if (is.null(rs) || !length(rs$notes)) return(NULL)
  text = console_notes_text(rs$notes, budget)
  rs$notes = character()
  text
}

#' provide() of the `user_files` context block: the files mentioned in the prompt (taken once)
#' @noRd
console_files_provide = function(ctx, budget) {
  rs = repl_sending(ctx)
  if (is.null(rs) || !length(rs$files)) return(NULL)
  text = console_files_text(rs$files, budget)
  rs$files = character()
  text
}

#' The context blocks registered by builtin:console (placement both: first and later turns)
#' @noRd
console_blocks = function() {
  list(
    gptr_context_block("user_ran", console_notes_provide, placement = "both",
                       authority = "data", budget = 300L, order = 550L),
    gptr_context_block("user_files", console_files_provide, placement = "both",
                       authority = "data", budget = 2000L, order = 560L)
  )
}

#' `!code` / `!!code`: the user's own R code in the REPL's environment
#'
#' The `input` event (source "passthrough") may handle or transform the code first. Errors are
#' shown on stderr; `!code` leaves a note for the next prompt. The `console:direct` channel
#' tells transcript writers (P15) what ran. A gptr_wait() in the code waits through console_wait()
#' (`.gptr_console_wait`).
#' @noRd
repl_passthrough = function(rs, text) {
  noted = !startsWith(text, "!!")
  code = substring(text, if (noted) 2L else 3L)
  ev = ev_dispatch("input", ev_new("input", text = code, source = "passthrough"),
                   session = rs$session)
  if (identical(ev$action, "handled")) return(invisible(NULL))
  code = ev$text
  if (!nzchar(trimws(code))) return(invisible(NULL))
  # gptr_wait() in the code shows what it waits for as the console's foreground
  .gptr_console_wait = function(ss, pump) console_wait(rs, ss, pump)
  force(.gptr_console_wait)
  # the evaluator of the `evaluator` setting (04 section 7.0 service `eval.r`, IC-69); the
  # built-in eval_r() when builtin:workspace is filtered out
  evaluate = if (ext_service_has("eval.r")) ext_service_get("eval.r") else eval_r
  res = evaluate(code, repl_eval_env(rs), plots = "auto", tee = TRUE, guard = FALSE)
  for (e in res$events) {
    if (identical(e$type, "error")) {
      console_notice("Error: ", console_escape(as.character(e$message %||% ""), FALSE),
                     .error = TRUE)
    }
  }
  if (res$status %in% c("interrupt", "timeout")) {
    said = c(interrupt = "interrupted", timeout = "timed out")[[res$status]]
    console_notice(console_style()$dim(said), .error = identical(res$status, "timeout"))
  }
  if (noted) rs$notes = utils::tail(c(rs$notes, repl_note(code, res)), 20L)
  data = list(code = code, output = as.character(unlist(res$outputs)), status = res$status,
              noted = noted)
  ev_dispatch("console:direct", list(data = data), session = rs$session)
  invisible(res$status)
}

#' Abort a run left without a pump by an interrupt that hit before the policy did
#' @noRd
console_abort_stray = function(s) {
  run = session_live(s)$run
  if (inherits(run, "gptr_run") && policy_active(run)) run_abort(run, reason = "user")
  invisible(NULL)
}

#' Build the gateway call of one prompt (no closure or handler is created in this frame, which
#' binds the evaluation environment; rule R3)
#'
#' Returns `gptr::peter(.gptr_session, <@objects>, prompt = "<text>", envir = .gptr_env, .opts =
#' ...)` (on the first prompt of a new or piped-in session also the console call's model, mode,
#' tools, plugins, extensions, skills and context objects). `.gptr_session` and `.gptr_env` are
#' bound in the mask `rs$mask`, whose parent is the evaluation environment, so @objects reach
#' the gateway as plain symbols (read by name, never forced, IC-41). The literal prompt gets
#' `{identifier}` interpolation like a typed one; the gateway shows the interpolated text at
#' verbosity 2 (03 section 4.1.4). `men`: the prompt's @mentions (repl_mentions()). The call
#' carries the attribute `gptr_console`, so P15 records it as a console turn even when a sourced
#' script or an editor holds the statement that started the console (IC-49).
#' @noRd
console_call = function(rs, text, men) {
  env = repl_eval_env(rs)
  first = is.null(rs$session)
  # the console call's identifiers and objects go with the first prompt of a new session and
  # with the first prompt on a piped-in session (`s |> peter(mode = auto)`)
  extras = first || isTRUE(rs$pending_call)
  rs$pending_call = FALSE
  objs = unique(c(if (extras) rs$attach, men$objects))
  opts = rs$opts
  if (is.null(opts$max_turns)) opts$max_turns = as.integer(gptr_opt("max_turns_console"))
  skills = unique(c(if (extras) rs$skills, rs$next_skills))
  rs$next_skills = NULL
  rs$files = men$files
  mask = new.env(parent = env)
  assign(".gptr_env", env, envir = mask)
  rs$mask = mask
  head = list(quote(gptr::peter))
  if (!first) {
    assign(".gptr_session", rs$session, envir = mask)
    head = c(head, list(quote(.gptr_session)))
  }
  args = list(prompt = text, envir = quote(.gptr_env), .opts = opts)
  if (!is.null(rs$budget)) args$budget = rs$budget
  if (extras) {
    extra = list(model = rs$model, mode = rs$mode, tools = rs$tools, plugins = rs$plugins,
                 extensions = rs$extensions)
    args = c(args, extra[!vapply(extra, is.null, NA)])
    rs$opts$images = NULL
  }
  if (length(skills)) args$skills = skills
  structure(as.call(c(head, lapply(objs, as.name), args)), gptr_console = TRUE)
}

#' Release the mask of a prompt call: bindings removed, parent reset to emptyenv() (R2)
#' @noRd
console_call_release = function(rs) {
  mask = rs$mask
  rs$mask = NULL
  rs$sending = NULL
  rs$files = character()
  if (is.environment(mask)) {
    rm(list = ls(mask, all.names = TRUE), envir = mask)
    parent.env(mask) = emptyenv()
  }
  invisible(NULL)
}

#' The reactor task of a terminal prompt (IC-76): every 0.05 s, what was typed while a session of
#' this call runs. A T console's call reads keys (tty_call()), which the composer takes
#' (console_keys()); a D console's lines are routed by console_typed_route(). Nothing is read
#' outside a terminal REPL or while no session runs (the next prompt reads it). With `drain` (before
#' a question) a D console reads fd 0 in tty_drain_mode(), so the partial line the question would
#' take as its answer is read too; it goes to the console history, its echoed row erased first.
#' With `accept` (a question's drain, after its rows) the first whole line that `accept(line)` takes
#' (typed_answer()) is not routed but returned: typed once the question showed, it answers it.
#' @return The reactor task's next interval, or FALSE to end; with `accept`, the answer it read,
#'   else TRUE where it read fd 0, FALSE where it did not
#' @noRd
console_typed = function(drain = FALSE, accept = NULL) {
  rs = console_repl_find()
  rd = rs$reader
  if (is.null(rd) || !repl_terminal(rs)) return(FALSE)
  pol = policy_find()
  target = Find(function(t) !is.null(t$session), policy_targets(pol$runs))
  if (is.null(target)) return(if (is.null(accept)) 0.05 else FALSE)
  read = if (is.null(accept)) 0.05 else TRUE
  s = target$session
  if (isTRUE(the$tty$keys)) {
    chars = console_typed_chars(rd, 0L)
    ans = if (is.function(accept)) typed_answer(console_typed_split(chars), accept)
    if (is.null(ans)) {
      console_keys(rd, s, chars)
      return(read)
    }
    # the lines around it, as typed
    after = ans$after
    if (length(ans$before)) console_keys(rd, s, paste0(ans$before, "\n", collapse = ""))
    if (length(after)) {
      console_keys(rd, s, paste0(paste(after, collapse = "\n"),
                                 if (!isTRUE(attr(after, "partial"))) "\n"))
    }
    return(ans$answer)
  }
  modes = if (drain) tty_drain_mode()
  if (length(modes) == 1L) on.exit(tty_modes(modes), add = TRUE)
  lines = console_typed_lines(rd, 0L)
  ans = if (is.function(accept)) typed_answer(lines, accept)
  if (!is.null(ans)) {
    console_typed_route(rd, s, ans$before)
    lines = ans$after
  }
  part = ""
  if (length(modes) == 1L && isTRUE(attr(lines, "partial"))) {
    part = lines[[length(lines)]]
    lines = lines[-length(lines)]
    # the terminal echoed it once the question turned the echo back on: its row is erased first, as
    # the D live row is, so what is written next stands alone
    console_cat(paste0("\r", strrep(" ", max(0L, cli::console_width() - 1L)), "\r"))
  }
  console_typed_route(rd, s, lines, part)
  ans$answer %||% read
}

#' The first whole line of `lines` (console_typed_split()) that `accept(line)` takes, its edit keys
#' applied (console_line_text()): list(answer, before, after), the lines around it, `after` marked
#' "partial" as `lines` is; NULL when none does
#' @noRd
typed_answer = function(lines, accept) {
  part = isTRUE(attr(lines, "partial"))
  text = vapply(lines, console_line_text, "", USE.NAMES = FALSE)
  hit = Position(function(x) isTRUE(accept(x)), utils::head(text, length(text) - part))
  if (is.na(hit)) return(NULL)
  after = lines[-seq_len(hit)]
  if (part) attr(after, "partial") = TRUE
  list(answer = text[[hit]], before = lines[seq_len(hit - 1L)], after = after)
}

#' Route the lines typed for a run of session `s` (IC-76, D-242): /command and !code lines, and the
#' lines that continue a held !code line still incomplete (typed_code_open()), wait in the reader
#' for the next prompt, each entry (a !code line with its continuation) shown as a follow-up's
#' queue line; the others become one message queued on `s` as the `type_ahead` setting says (a
#' follow-up waits with the held lines, after those typed before its first line); a partial line
#' `part` goes to the console history. Their lines go between the answer's whole rows, above the
#' live row (D-245). A cursor key's escape sequence (CSI, SS3) is dropped, as the composer drops it,
#' and a line it alone made with it
#' @noRd
console_typed_route = function(rd, s, lines, part = "") {
  esc = "\033(\\[[0-?]*[ -/]*[@-~]|O.)"
  text = gsub(esc, "", lines, perl = TRUE)
  lines = text[nzchar(text) | !nzchar(lines)]
  part = gsub(esc, "", part, perl = TRUE)
  later = cont = logical(length(lines))
  for (i in seq_along(lines)) {
    cont[[i]] = typed_code_open(c(rd$typed, lines[later]))
    later[[i]] = cont[[i]] || grepl("^\\s*[/!]", lines[[i]])
  }
  text = paste(lines[!later], collapse = "\n")
  if (!any(later) && !nzchar(trimws(paste0(text, part)))) return(invisible(NULL))
  hold = function(k) {
    for (x in split(lines[k], cumsum(!cont[k]))) {
      console_queue_line(s, paste(x, collapse = "\n"), "follow_up")
    }
    rd$typed = c(rd$typed, lines[k])
  }
  before = cumsum(!later) == 0L
  hold(before)
  if (nzchar(trimws(text))) policy_enqueue(s, text, setting_get("type_ahead", s), source = "repl")
  hold(later & !before)
  if (nzchar(trimws(part))) console_keep(part)
}

#' Text the person typed that gptr will not send: added to the console history in order
#' (console_history_add()) and listed once as the person's held text, dim at column 0 like a queue
#' line, `<queued glyph> kept in history <Up glyph><sep><a><sep><b>` cut to three rows, or
#' `... not kept (gptr.history is off)<sep>...`; inside an evaluation in the console's colours
#' (D-242, D-243)
#' @noRd
console_keep = function(texts) {
  if (!length(texts)) return(invisible(NULL))
  kept = all(vapply(texts, console_history_add, NA))
  rlang::local_options(cli.num_colors = console_colors())
  sym = console_style()
  what = if (kept) paste("kept in history", sym$up) else "not kept (gptr.history is off)"
  console_write(sym$dim(console_person_rows(sym$queued, paste0(
    what, sym$sep, paste(texts, collapse = sym$sep)), n = 3L)))
}

#' Is the last held `!code` line, with the held lines after it, incomplete R code? The next line
#' then continues it, as at the prompt's "+ " (repl_read_logical())
#' @noRd
typed_code_open = function(held) {
  code = NULL
  for (x in held) {
    if (!is.null(code) && r_incomplete(code)) {
      code = paste0(code, "\n", x)
    } else {
      code = if (startsWith(x, "!")) sub("^!!?", "", x)
    }
  }
  !is.null(code) && r_incomplete(code)
}

#' One prompt as an ordinary gateway call (console_call())
#'
#' The frame binds the REPL state (`.gptr_repl`, found by the context blocks) and
#' `.gptr_interrupt_barrier`, so the policy of this call's run is the outermost one and its
#' re-signalled interrupt ends here. A failed call keeps its session (the condition's `$session`,
#' else a new gptr_last()); a stray run left by an early interrupt is aborted. On a terminal the
#' call's console_typed() task reads what is typed, in the call's modes until it ends (tty_call():
#' a T console's keys, a D console's lines without echo; IC-76, D-243); the end of its run settles
#' what it held (console_queue_left()), and keys read with a Ctrl-C that no question took
#' (console_ahead()) are the composer's draft at the next prompt. `men`: the prompt's @mentions.
#' @return list(status = "ok" | "error" | "interrupt", value, error); `rs$session` is updated.
#' @noRd
console_send = function(rs, text, men = repl_mentions(text, repl_eval_env(rs))) {
  .gptr_repl = rs
  .gptr_interrupt_barrier = TRUE
  force(.gptr_repl)
  force(.gptr_interrupt_barrier)
  on.exit(console_call_release(rs), add = TRUE)
  cl = console_call(rs, text, men)
  rs$sending = cl
  before = gptr::gptr_last()
  res = console_reading(rs, function() {
    tryCatch(list(status = "ok", value = eval(cl, envir = rs$mask)),
             error = function(e) list(status = "error", error = e),
             interrupt = function(e) list(status = "interrupt"))
  })
  # keys read with a Ctrl-C that no question took (after [a]) are typed at the next prompt
  rd = rs$reader
  if (nzchar(rd$after_interrupt %||% "")) {
    left = sub("[\r\n]+$", "", rd$after_interrupt)
    rd$after_interrupt = ""
    rd$compose = console_compose(rd$compose, left, reactor_now(), "steer", console_complete,
                                 TRUE)$state
  }
  s = NULL
  if (inherits(res$value, "gptr_session")) {
    s = res$value
  } else if (inherits(res$error$session, "gptr_session")) {
    s = res$error$session
  } else {
    last = gptr::gptr_last()
    if (inherits(last, "gptr_session") && !identical(last, before)) s = last
  }
  if (!is.null(s)) rs$session = s
  if (identical(res$status, "interrupt") && !is.null(rs$session)) console_abort_stray(rs$session)
  res
}

#' `body()` while a terminal REPL's console_typed() task reads what is typed, in the call's modes
#' (tty_call(): a T console's keys, a D console's lines without echo; IC-76, D-243): the terminal
#' never echoes type-ahead into an answer, and gptr_readline() echoes its own reads
#' @noRd
console_reading = function(rs, body) {
  task = if (repl_terminal(rs)) reactor_task(console_typed)
  on.exit(if (!is.null(task)) reactor_cancel(task), add = TRUE)
  if (!is.null(task)) {
    on.exit(tty_restore(), add = TRUE)
    tty_call(console_class() == "T")
  }
  body()
}

#' A wait of the console's R code (`!!gptr_wait(s)`, repl_passthrough()) on sessions `ss`, a run the
#' pause menu's [b] sent to the background among them: while `pump()` waits they are the console's
#' foreground (`console_state()$waited`, console_foreground()), so their rows, live row and status
#' line show as a prompt's do, in the console's colours, outside the code's evaluation (its
#' `.gptr_eval_outside`), and a terminal reads keys as during a prompt's call, Enter steering: the
#' REPL counts as sending (`rs$sending`, console_repl_prompt()), so the live row shows the draft and
#' the queue, and follow-ups wait for the next prompt
#' @noRd
console_wait = function(rs, ss, pump) {
  .gptr_repl = rs
  force(.gptr_repl)
  st = console_state()
  old = st$waited
  sending = rs$sending
  on.exit({
    st$waited = old
    rs$sending = sending
  }, add = TRUE)
  st$waited = c(old, vapply(ss, function(s) session_data(s)$id, ""))
  rs$sending = sending %||% TRUE
  outside = console_eval_value(".gptr_eval_outside") %||% function(f) f()
  outside(function() {
    # as the live row draws: the evaluation's capture, which its writer puts back, says 1 colour
    rlang::local_options(cli.num_colors = console_colors())
    console_render_resume(Filter(Negate(is.null), lapply(ss, function(s) session_live(s)$run)))
    console_reading(rs, pump)
  })
}

# ---------------------------------------------------------------------------------------------
# The REPL (Task 7): report 18 A.7 gptr_repl() on gptr's gateway. Each logical input is a slash
# command (console-commands.R), `!code`/`!!code` (repl_passthrough()) or a prompt (console_send());
# errors are printed escaped on stderr and the REPL goes on.
# ---------------------------------------------------------------------------------------------

#' The banner (architecture 6.17, NS-1; D-245): dim lines at column 2 as a notice, their terms
#' joined by the separator in rows of whole terms (console_terms()), in ASCII `gptr <version> -
#' <model> - <mode> - .gptr/ found`, `objects: ` and up to six names of the evaluation environment,
#' then the keys in bold, `/help lists commands - tab completes after @ ! / - ctrl-c twice leaves`:
#' the tab only where the REPL completes (after ! and / in RStudio's console, which puts other words
#' in backticks), the console's own interrupt key, which does not pause at the prompt. In Positron,
#' whose console holds what is typed while peter works as R code, a line says so and that the key,
#' then s, steers, in the live row's words (`ctrl-c, then s, to steer`). A blank line ends it, after
#' the yolo notice
#' @noRd
repl_banner = function(rs) {
  sym = console_style()
  sep = sym$sep
  key = function(k, words) paste0(cli::style_bold(k), sym$dim(words))
  esc = tolower(console_interrupt_key())
  ws = if (is.null(workspace_dir())) "no .gptr/" else ".gptr/ found"
  nms = sort(ls(repl_eval_env(rs)), method = "radix")
  more = if (length(nms) > 6L) paste0(" (+ ", length(nms) - 6L, " more)")
  after = if (front_end() == "rstudio") "! /" else "@ ! /"
  # rows of whole terms (console_terms()), at the content width
  width = max(20L, cli::console_width() - 2L * nchar(console_pad()))
  terms = function(x) console_terms(x, width, sym$dim(sep))
  console_notice(paste(c(
    sym$dim(console_terms(c(paste("gptr", utils::packageVersion("gptr")),
                            console_escape(c(repl_model(rs), repl_mode(rs)), FALSE), ws), width)),
    if (length(nms)) {
      sym$dim(paste0("objects: ", console_escape(paste(utils::head(nms, 6L), collapse = ", "),
                                                 FALSE), more))
    },
    terms(c(key("/help", " lists commands"),
            if (isTRUE(rs$reader$complete)) key("tab", paste0(" completes after ", after)),
            key(esc, " twice leaves"))),
    if (console_menu_available() && front_end() == "positron") {
      terms(c(sym$dim("text typed while peter works waits as R code"),
              paste0(key(esc, ", then "), key("s", ", to steer"))))
    }), collapse = "\n"))
  mode_notice(repl_mode(rs))
  console_write("")
}

#' A notice when background sessions wait for approval; P21 asks at the next blocking call
#' (IC-57), dim in the banner's words. Said again only when their number changes.
#' @noRd
repl_waiting_notice = function(rs) {
  n = sum(job_list("session")$status == "waiting")
  if (n > 0L && n != rs$waiting) {
    sym = console_style()
    console_notice(sym$dim(paste0(n, if (n == 1L) " background session waits" else
      " background sessions wait", " for approval", sym$sep,
      "the next prompt or gptr_wait() asks")))
  }
  rs$waiting = n
  invisible(NULL)
}

#' Print an error on stderr: escaped, its line feeds kept
#' @noRd
repl_error = function(e) {
  console_notice("Error: ", console_escape(conditionMessage(e)), .error = TRUE)
}

#' The line under a sent prompt that names what its @mentions resolved to (D-244): dim, the
#' escaped terms `said` (repl_mentions()) joined by the separator, wrapped between terms at the
#' console's content width (a term wider than it cut)
#' @noRd
mention_line = function(said) {
  rows = console_terms(console_escape(said, FALSE), max(20L, cli::console_width() - 4L))
  paste(console_style()$dim(rows), collapse = "\n")
}

#' One prompt through console_send(), after the line naming what its @mentions resolved to
#' (mention_line()); the answer is printed here when the renderer hooks did not stream it
#' (verbosity < 2), any other value is printed. A prompt to a session that runs (in the
#' background: after the pause menu's [b], or `background = TRUE`) steers it (route_continue()),
#' so its queue line says so, `<queued glyph> steer<sep><text>` (console_queue_line()), once sent
#' @noRd
repl_turn = function(rs, text) {
  men = repl_mentions(text, repl_eval_env(rs))
  if (length(men$said)) console_notice(mention_line(men$said))
  s = rs$session
  steer = !is.null(s) && session_data(s)$status %in% c("running", "waiting")
  st = console_state()
  st$ended = NULL
  res = console_send(rs, text, men)
  if (identical(res$status, "error")) {
    # the run's status line said why; any other error keeps the gap before the prompt
    e = res$error
    if (inherits(e$session, "gptr_session") && identical(st$ended, session_data(e$session)$id)) {
      return(invisible(NULL))
    }
    repl_error(e)
    if (nzchar(console_pad())) console_cat("\n")
    return(invisible(NULL))
  }
  if (!identical(res$status, "ok")) return(invisible(NULL))
  if (steer) return(console_queue_line(s, text, "steer"))
  value = res$value
  if (!inherits(value, "gptr_session")) {
    console_out(print_lines(value))
  } else if (verbosity() < 2L) {
    console_print_text(value$text)
  }
  invisible(NULL)
}

#' Dispatch one logical input: /command, !code or a prompt; inputs of an interactive console go
#' to R's history (gptr.history, console_history_add())
#' @noRd
repl_dispatch = function(rs, line) {
  text = trimws(line)
  if (!nzchar(text)) return(invisible(NULL))
  if (!rs$stdin && gptr_is_interactive()) console_history_add(line)
  tryCatch({
    if (startsWith(text, "/")) {
      console_command(text, rs$session, send = function(prompt) repl_turn(rs, prompt))
    } else if (startsWith(text, "!")) {
      repl_passthrough(rs, text)
    } else {
      repl_turn(rs, text)
    }
  }, interrupt = function(e) {
    if (!is.null(rs$session)) console_abort_stray(rs$session)
    console_notice(console_style()$dim("interrupted"))
  }, error = repl_error)
  invisible(NULL)
}

#' The REPL loop on a repl_state(); returns the session invisibly (NULL when none was started)
#'
#' Ctrl-C at the prompt prints a hint, twice in a row leaves; `/exit` and the end of piped input
#' leave too. Under `.stdin = TRUE` the console is a person at a pipe (plan ambiguity 8): unset,
#' `gptr.interactive` becomes TRUE and `gptr.ui` P11's console UI on the REPL's reader until the
#' REPL ends. The session returned gets `session_shutdown` (reason "exit") unless the caller
#' piped it in.
#' @noRd
repl_main = function(rs) {
  .gptr_repl = rs
  force(.gptr_repl)
  piped = rs$session
  on.exit(repl_close(rs), add = TRUE)
  rs$reader = console_reader(rs$stdin)
  # completion only after the trigger characters (IC-81) where R's completion calls the custom
  # completer (console_completes()); on R's own Unix readline on a tty (an IDE's terminal tab too)
  # ! breaks its words, so the R code after !/!! is completed; a caller-owned completer keeps its
  # words and completes the ! lines
  if (console_completes(rs$stdin)) rs$reader$complete = TRUE
  # RStudio asks also while peter works, in the evaluation's frames, and a line typed then is the
  # next prompt: its console has the completer for the REPL's whole life, the caller's kept
  if (isTRUE(rs$reader$complete) && front_end() == "rstudio") {
    caller = utils::rc.getOption("custom.completer")
    rs$reader$caller = list(caller)
    utils::rc.options(custom.completer = console_completer(caller))
    on.exit(utils::rc.options(custom.completer = caller), add = TRUE)
  }
  if (isTRUE(rs$reader$complete) && console_readline_tty()) {
    breaks = getOption("rl_word_breaks", " \t\n\"\\'`><=%;,|&{()}")
    if (!is.function(utils::rc.getOption("custom.completer")) &&
        !grepl("!", breaks, fixed = TRUE)) {
      completion_options = options(rl_word_breaks = paste0(breaks, "!"))
      on.exit(options(completion_options), add = TRUE)
    }
  }
  if (rs$stdin) {
    set = list()
    if (is.null(getOption("gptr.interactive"))) set$gptr.interactive = TRUE
    if (is.null(getOption("gptr.ui"))) {
      set$gptr.ui = ui_console_spec(rs$reader$read, "console_stdin")
    }
    old = options(set)
    on.exit(options(old), add = TRUE)
  }
  if (!repl_setup(rs)) return(invisible(NULL))
  if (!rs$stdin && console_class() == "T") repl_background(rs$reader)
  repl_banner(rs)
  repeat {
    if (rs$exit) break
    repl_waiting_notice(rs)
    # a readline-limit warning would wait for the REPL to return (warn = 0): shown at once
    line = tryCatch(withCallingHandlers(
      repl_read_logical(rs$reader, repl_prompt(rs)),
      gptr_warning_readline_limit = function(w) {
        console_notice("Warning: ", conditionMessage(w))
        invokeRestart("muffleWarning")
      }), interrupt = function(e) FALSE)
    if (isFALSE(line)) {
      rs$interrupts = rs$interrupts + 1L
      if (rs$interrupts >= 2L) break
      # in the banner's words, the keys bold
      sym = console_style()
      console_notice("\n", cli::style_bold(tolower(console_interrupt_key())),
                     sym$dim(paste0(" again leaves", sym$sep)), cli::style_bold("/exit"))
      next
    }
    if (is.na(line)) break
    rs$interrupts = 0L
    repl_dispatch(rs, line)
  }
  s = rs$session
  if (!is.null(s) && !identical(s, piped)) {
    d = session_data(s)
    ev_dispatch("session_shutdown", ev_new("session_shutdown", session = d$id, run = NULL,
                                           agent = "main", turn = d$turns, reason = "exit"),
                session = s)
  }
  invisible(s)
}

#' Choose and save a default before the first interactive chat; FALSE returns to R
#' @noRd
repl_setup = function(rs) {
  if (!is.null(rs$session) || !is.null(rs$model) || !is.null(setting_get("model")) ||
      rs$stdin || !gptr_can_prompt()) return(TRUE)
  ids = c("codex", "claude-cli")
  refs = c("codex/default", "claude-cli/default")
  providers = gptr::gptr_providers(check_login = TRUE)
  rows = match(ids, providers$id)
  api = providers$api[rows]
  is_cli = !is.na(api) & api == c("cli-codex", "cli-claude")
  status = providers$status[rows]
  status[is.na(status)] = "not available"
  status[!is_cli] = "not a CLI provider"
  login = providers$login[rows]
  login[is.na(login)] = "unknown"
  login[!is_cli] = "unknown"
  shown_status = console_escape(status, newlines = FALSE)
  shown_login = c(`signed in` = "Signed in", `not signed in` = "Not signed in",
                  unknown = "Unknown")[login]
  cli_names = c("Codex CLI", "Claude Code CLI")
  labels = c(sprintf("%-*s  %-*s  %s", max(nchar(cli_names)), cli_names,
                      max(nchar(shown_status)), shown_status, shown_login),
              "Manual setup (API or Ollama)", "Cancel and return to R")
  choice = ui_get()$select(
    "Welcome to Peter.\nChoose a default model provider.", labels, default = 4L,
    details = c("Saved in your user settings for future sessions.",
                "CLI login status does not verify billing or online access.",
                "Manual setup shows API and Ollama commands, then returns to R."))
  if (length(choice) != 1L || !choice %in% 1:3) {
    console_notice("Setup cancelled. No default provider was saved.")
    return(FALSE)
  }
  if (choice == 3L) {
    console_out(c(
      "Configure an API provider in R:",
      '  gptr_login("openai", method = "key")',
      '  # Or load an existing key file with gptr_env("~/keys/.env").',
      '  gptr_config(model = "openai/gpt-6-sol", .scope = "user")',
      "Or use an installed local Ollama model:",
      '  gptr_models(provider = "ollama", refresh = TRUE)',
      "  # Replace <installed-model> with a local chat model from this listing.",
      '  gptr_config(model = "ollama/<installed-model>", .scope = "user")',
      "  peter()",
      "Use gptr_providers(), gptr_models(), and ?gptr_config for other providers."))
    return(FALSE)
  }
  if (!is_cli[choice]) {
    console_notice("The ", ids[choice], " provider is not using the expected CLI adapter. ",
                     "Choose another provider or use manual setup. ",
                     "No default provider was saved.")
    return(FALSE)
  }
  if (!status[choice] %in% c("found", "ready")) {
    command = c("codex", "claude")[choice]
    console_notice("The ", command, " CLI is not available. Install it and sign in in your ",
                     "terminal, then run peter() again. Use gptr_providers(check = TRUE) ",
                     "to check its status.")
    return(FALSE)
  }
  if (login[choice] == "not signed in") {
    command = c("codex login", "claude auth login")[choice]
    console_notice("Sign in in your terminal with `", command, "`, then run peter() again. ",
                     "No default provider was saved.")
    return(FALSE)
  }
  if (login[choice] == "unknown") {
    console_notice("Login status is unknown. If needed, sign in in your CLI before chatting.")
  }
  ref = refs[choice]
  gptr::gptr_config(model = ref, .scope = "user")
  rs$model = ref
  console_notice("Default provider saved: ", ids[choice], " (user settings).")
  TRUE
}

#' End a REPL: its reader closed (IC-59), its environment released (rule R2)
#' @noRd
repl_close = function(rs) {
  if (!is.null(rs$reader)) rs$reader$close()
  rs$envir = NULL
  invisible(NULL)
}

#' The REPL on `s`, a new session from the first prompt when `s` is NULL (contract 7.14)
#' @noRd
console_run = function(s, envir, stdin = FALSE) {
  repl_main(repl_state(s, envir, stdin))
}

#' run() of the `console` frontend: the REPL on the call's session and environment, else on the
#' session's kept home
#' @noRd
console_frontend_run = function(session, ..., call = NULL) {
  envir = call$envir
  if (is.null(envir) && !is.null(session)) envir = session_home(session)
  repl_main(repl_state(session, envir, isTRUE(call$args$stdin), call))
}

#' match() of the `console` route (contract 6.1.1): no prompt, and someone can answer (IC-43) or
#' `.stdin = TRUE`; never while a run's tool executes, so model code cannot open a REPL that reads
#' the user's input or sets `gptr.ui` (plan ambiguity 25)
#' @noRd
console_route_match = function(call) {
  is.null(call$prompt) && is.null(run_current()) &&
    (isTRUE(call$args$stdin) || gptr_can_prompt())
}

#' run() of the `console` route: the frontend named by `.opts$frontend`, else the setting
#' `frontend`, else `console` (IC-69); its value comes back invisibly
#' @noRd
console_route_run = function(call) {
  name = call$args$opts$frontend %||% setting_get("frontend") %||% "console"
  fe = registry_get("frontend", name, session = call$session)
  if (is.null(fe)) {
    gptr_abort(paste0("No frontend named '", name, "' is registered."), "invalid_argument",
               arg = "frontend", expected = "a registered frontend name")
  }
  invisible(fe$run(call$session, call = call))
}

#' builtin:console (contract 7.14, 10.3): renderer hooks, context blocks, the slash commands, the
#' `console` frontend and route; the console.interrupt_policy service (console-interrupt.R) is
#' owned by it
#' @noRd
builtin_console = function(gptr) {
  specs = c(console_hooks(), console_blocks(), console_commands(), list(
    gptr_spec("frontend", "console", run = console_frontend_run),
    gptr_spec("route", "console", order = 30, match = console_route_match,
              run = console_route_run,
              description = "peter() with no prompt: the console on the piped or a new session")))
  for (spec in specs) gptr$register(spec)
  invisible(NULL)
}

on_load(ext_declare_builtin("console", builtin_console))

#' @section The interactive console:
#' `peter()` without a prompt opens a console when someone can answer (interactive R or
#' IRkernel); `peter(.stdin = TRUE)` reads its input from standard input, and
#' `session |> peter()` opens it on `session`. With no explicit or configured model, the
#' interactive console first offers Codex CLI, Claude Code CLI or API configuration
#' instructions. Choosing an available CLI saves its default model at user scope; cancelling
#' returns to R. Piped input skips this setup.
#' Each input is one of:
#'
#' * a prompt, sent as `session |> peter("...")` with `{name}` interpolation; `@file` adds
#'   the head of a file (at most 40 lines) and `@object` attaches an object by name;
#' * `!code`: R code run in the session's environment; the code and its output go with the next
#'   prompt (at most 300 estimated tokens). `!!code` omits that note. Both execute your own R
#'   immediately, without the model's permission gate or a model request. Workspace changes
#'   remain visible to later calls, and enabled transcripts can record the code; `!!` is not a
#'   privacy boundary. A fenced block marked `r`, `R`, `{r}` or unmarked works like `!code`
#'   (other fences are prompt text), a `"""` block is a multi-line prompt, and a trailing
#'   backslash continues a line;
#' * a slash command such as `/model`, `/mode`, `/cost` or `/exit`; `/help` lists them all.
#'
#' In CRAN's R for macOS in a terminal a pasted block is one input: its lines join the first one
#' and `... ` waits for Enter (text typed there is added); a pasted fence or `"""` block is read
#' up to its closer at once, and a block pasted at an approval or a choice is kept in the console
#' history and the question asked again. A last pasted line without a newline waits for Enter at
#' the next prompt, so a two-line paste without a final newline answers with its first line.
#' Elsewhere (Homebrew or conda R, Linux terminals, RStudio, R.app, Positron, Windows) pasted
#' lines arrive one at a time; wrap a multi-line paste in `"""`. Lines typed, pasted or run from a
#' script before a question (an approval, a choice) appeared never answer it: while an answer
#' runs they are queued for the agent as `type_ahead` says (below; a /command or !code line waits
#' for the next prompt), otherwise they go to the console history. Answer after the prompt.
#'
#' What you type while peter works, and the key that pauses it, depend on the console:
#'
#' \tabular{lll}{
#'   \strong{Console} \tab \strong{Typed while peter works} \tab \strong{Pause} \cr
#'   Terminal R on macOS or Linux, an IDE's Terminal tab \tab a draft: Enter steers, Tab sends a
#'     follow-up \tab Ctrl-C \cr
#'   TERM=dumb, Emacs shell, ESS \tab each line, as \code{type_ahead} says \tab Ctrl-C \cr
#'   RStudio, R.app \tab the next prompt, unless a question reads it \tab Esc \cr
#'   Positron \tab R code, run after \code{peter()} returns \tab Ctrl-C \cr
#'   Windows Rterm \tab the next prompt, unless a question reads it \tab Ctrl-C \cr
#'   Windows Rgui, Jupyter \tab the next input \tab none: Esc or interrupt stops \cr
#'   Rscript, pipes, knitr \tab nothing; \code{.stdin = TRUE} reads the pipe \tab none
#' }
#'
#' In terminal R and an IDE's Terminal tab what you type while peter works is a draft on the
#' bottom row, under the transcript, so it never mixes into the answer; a block pasted there is
#' one message. Enter sends it as a steer: the agent reads it at its next step boundary, when the
#' response in flight ends after the results of all its tool calls (an answer about to end gets
#' one more request), and it then shows as your own line. Tab sends it as a follow-up: the next
#' prompt, sent as its own run once the answer ends. `type_ahead = "follow_up"` ([gptr_config()])
#' swaps the two keys. A draft that starts with `/` or `!` is always a follow-up, so `/command`
#' and `!code` lines run at the next prompt, in the order typed. The bottom row counts what is
#' queued; Up on an empty draft takes back the newest message not yet delivered, to edit and send
#' again, and Ctrl-U clears the draft. A question (an approval, a choice) waits until typing
#' pauses for a second, or three while the draft has text, and the draft stays: through
#' questions, Ctrl-C and the pause menu, and to the next prompt, where Enter sends it. Keys typed
#' while R code runs in this process (the `r` tool) show when it returns. A steer the answer did
#' not take (it ended first) is the next prompt; after an abort or an error nothing queued is
#' sent: the queued text and the draft go to the console history, and Up recalls them. Under
#' TERM=dumb or in ESS a line typed with Enter is queued as `type_ahead` says. On the CLI routes
#' (`claude-cli`, `codex`) the agent reads a steer after the CLI's answer, which is often the
#' whole run.
#'
#' RStudio, R.app, Positron and Windows consoles hold what is typed until R reads again. In
#' RStudio, R.app and Windows consoles a line typed while peter works is the next prompt, one
#' prompt per line, unless a question comes first: it reads the line, queues it as `type_ahead`
#' says and asks again. Positron's console keeps typed text as R code, which runs after `peter()`
#' returns, and clears it at Ctrl-C. To steer in these consoles, pause and press `s` (Windows'
#' Rgui cannot pause). In RStudio an Esc first closes RStudio's own completion list, if open, then
#' clears a line being typed, so the menu comes at the next Esc. During `peter("...")` at R's
#' prompt, outside the chat, typed lines stay R's next input.
#'
#' Tab completes only after `@` (objects, then files), `@obj$` (its members), `peter$`, a leading
#' `/` (commands) and on a `!` or `!!` line (R code), never in plain text: in terminal R, R in an
#' IDE's Terminal tab, Windows' Rgui and Rterm, and RStudio's console, which completes only what its
#' popup inserts as offered (the commands after `/` and R code after `!`, not words holding `@` or
#' `$`, which it would wrap in backticks). In a terminal Tab completes the draft the same way while
#' peter works, and on such a word never sends it. R.app, radian and Positron's console keep their
#' own completion. gptr never changes RStudio's preferences: as you type in its console, RStudio
#' adds closing brackets and quotes unless `insert_matching` is off, and opens completions unless
#' `console_code_completion` is off (Tools > Global Options > Code).
#'
#' The pause key opens a pause menu while an answer runs, with the keys `s` steer, `f` follow-up,
#' `c` continue, `a` abort and, for a foreground call (a chat turn included) when available, `b`
#' background. `s` and `f` ask for the text and queue it as Enter and Tab do; in a `peter("...")`
#' call a follow-up is sent when the agent would otherwise stop. A key typed right after the pause
#' key answers the menu. Continuing leaves the work as if it had not paused, and pressing the
#' pause key again aborts. Abort keeps the partial session; what you queued and the draft go to
#' the history, unsent. Background returns to the chat prompt and keeps the run: what was
#' queued for after the answer and the draft go to the history, unsent, as after an abort, and
#' another prompt steers the running session. Nothing runs it while the chat waits for input: use
#' `!!gptr::gptr_wait(gptr::gptr_last())` there to continue it, its answer then shown as a prompt's
#' and Enter steering it. Under Rscript, background runs advance only inside blocking gptr calls.
#' Where an interrupt cannot be resumed (Windows' Rgui, Jupyter) the key stops the answer instead.
#'
#' `/exit`, two consecutive interrupts at the prompt or the end of piped input return the session
#' invisibly, so `session = peter()` keeps the conversation. In a terminal the chat reads keys with
#' the terminal's echo off and restores it on return, on an error, at an interrupt and at `q()`;
#' if R is killed or crashes while peter works, type `stty sane` and press Enter to get it back.
#'
#' Options: `gptr.verbose` (0 silent, 1 progress, 2 streamed console, 3 debug; default 0 in
#' knitr and testthat, 1 under Rscript, 2 at the console), `gptr.max_turns_console`
#' (turns per console prompt, default 200) and `gptr.history` (console inputs to R's history,
#' default `TRUE`). Ordinary progress uses normal output; actual errors use stderr.
#' `vignette("interactive-console", package = "gptr")` gives input examples and the complete
#' built-in command table.
#' @name peter
#' @rdname peter
NULL

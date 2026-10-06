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
  rs$render = TRUE
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

#' The prompt: "peter> " in manual mode, "peter[<mode>]> " otherwise
#' @noRd
repl_prompt = function(rs) {
  mode = repl_mode(rs)
  if (identical(mode, "manual")) "peter> " else paste0("peter[", mode, "]> ")
}

#' The persistent stdin connection of `peter(.stdin = TRUE)` (tests mock this function): a fresh
#' file("stdin") per read loses buffered lines (report 18 2.1.3)
#' @noRd
console_stdin_open = function() {
  file("stdin", open = "r")
}

#' The longest console line readline() delivers whole (report 18 fact-check 2)
#' @noRd
readline_limit = function() {
  if (getRversion() >= "4.5.0") 8190L else 4095L
}

#' A line reader: gptr_readline() or the persistent stdin connection (closed by `close()`, IC-59)
#'
#' Returns an environment with `read(prompt = "", stream = "stdout")` -> chr(1), NA at the end of
#' piped input; `close()`; `flag` (TRUE when a line reached the readline limit). With `echo` the
#' stdin reader writes the prompt and the escaped line on `stream`, so a piped session reads like
#' a terminal session.
#' @noRd
console_reader = function(stdin = FALSE, echo = stdin) {
  rd = new.env(parent = emptyenv())
  rd$flag = FALSE
  rd$con = NULL
  echo = isTRUE(echo)
  if (isTRUE(stdin)) {
    rd$con = console_stdin_open()
    rd$read = function(prompt = "", stream = "stdout") {
      if (is.null(rd$con)) return(NA_character_)
      out = if (identical(stream, "stderr")) stderr() else stdout()
      if (echo) cat(prompt, file = out, sep = "")
      x = readLines(rd$con, n = 1L, warn = FALSE, encoding = "UTF-8")
      if (!length(x)) {
        if (echo) cat("\n", file = out)
        return(NA_character_)
      }
      x = as_utf8(x)
      if (echo) cat(console_escape(x, FALSE), "\n", file = out, sep = "")
      x
    }
  } else {
    rd$read = function(prompt = "", stream = "stdout") {
      x = gptr_readline(prompt)
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
    if (!is.null(con)) close(con)
    invisible(NULL)
  }
  rd
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
#' A `"""` block is one multi-line prompt; a fenced block is R code (returned as `!code`); `!code`
#' and `!!code` continue while the code is incomplete; a trailing backslash continues a line; the
#' end of piped input ends every block. Returns NA at the end of input, "" when a line hit the
#' readline limit (the whole input is dropped rather than sent half).
#' @noRd
repl_read_logical = function(rd, prompt) {
  rd$flag = FALSE
  line = rd$read(prompt)
  if (is.na(line)) return(NA_character_)
  out = line
  if (grepl('^\\s*"""', line)) {
    body = sub('^\\s*"""', "", line)
    while (!grepl('"""\\s*$', body)) {
      x = rd$read("... ")
      if (is.na(x)) break
      body = paste0(body, "\n", x)
    }
    out = trimws(sub('"""\\s*$', "", body))
  } else if (grepl("^\\s*```", line)) {
    body = character()
    repeat {
      x = rd$read("... ")
      if (is.na(x) || grepl("^\\s*```\\s*$", x)) break
      body = c(body, x)
    }
    out = paste0("!", paste(body, collapse = "\n"))
  } else if (startsWith(line, "!")) {
    bang = if (startsWith(line, "!!")) "!!" else "!"
    code = substring(line, nchar(bang) + 1L)
    while (r_incomplete(code)) {
      x = rd$read("+ ")
      if (is.na(x)) break
      code = paste0(code, "\n", x)
    }
    out = paste0(bang, code)
  } else {
    while (endsWith(out, "\\")) {
      out = substr(out, 1L, nchar(out) - 1L)
      x = rd$read("... ")
      if (is.na(x)) break
      out = paste0(out, "\n", x)
    }
  }
  if (rd$flag) "" else out
}

#' Add a REPL input to the console history (report 18: utils::timestamp(); never fails)
#' @noRd
console_history_add = function(x) {
  tryCatch(utils::timestamp(stamp = x, prefix = "", suffix = "", quiet = TRUE),
           error = function(e) NULL)
  invisible(NULL)
}

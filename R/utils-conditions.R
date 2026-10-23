# Conditions and argument checkers (contract sections 1.1 and 2.1).
# Rule C1: condition messages are built by plain concatenation, never interpolated by cli or glue,
# so untrusted text inside a message can never be evaluated.

#' Build (without signalling) a gptr condition object
#'
#' `kind` is "error", "warning" or "message". P04, P12 and P13 use this to create the unsignalled
#' condition objects that travel in `error` events.
#' @noRd
gptr_condition = function(message, class, kind = "error", fields = list(), call = NULL) {
  if (!is.character(class) || !length(class) || anyNA(class) || !all(nzchar(class))) {
    class = "internal"
  }
  text = paste(as.character(message), collapse = "\n")
  text = redact_hook(as_utf8(text), profile = "persist")
  if (identical(kind, "message")) text = paste0(text, "\n")
  prefix = paste0("gptr_", kind)
  nms = names(fields)
  if (is.null(nms)) {
    fields = list()
  } else {
    fields = fields[nzchar(nms) & !(nms %in% c("message", "call"))]
  }
  structure(
    c(list(message = text, call = call), fields),
    class = c(paste0(prefix, "_", class), prefix, kind, "condition")
  )
}

#' Signal a gptr error
#'
#' Creates a condition of class `c("gptr_error_<class>", ..., "gptr_error", "error",
#' "condition")` and signals it. The message is pasted, never interpolated, and passes the
#' redaction hook.
#' @param message Character vector, joined with newlines.
#' @param class Class suffixes, most specific first.
#' @param ...,.data Named extra condition fields.
#' @param call The call shown with the error (`NULL`: none).
#' @noRd
gptr_abort = function(message, class, ..., .data = NULL, call = NULL) {
  stop(gptr_condition(message, class, "error", c(list(...), .data), call))
}

#' Signal a gptr warning (at most once per process for a given `.once` key)
#' @noRd
gptr_warn = function(message, class, ..., .data = NULL, .once = NULL) {
  if (!once_first(.once, "warning")) return(invisible(NULL))
  warning(gptr_condition(message, class, "warning", c(list(...), .data)))
  invisible(NULL)
}

#' Signal an informational condition and display ordinary console output unless muffled
#'
#' Protocol frontends reserve stdout with a scoped `.gptr_message_stream` binding. Conditions
#' still reach calling handlers with the standard muffleMessage restart before any display.
#' @noRd
gptr_inform = function(message, class, ..., .data = NULL, .once = NULL, .stream = NULL) {
  if (isTRUE(getOption("gptr.quiet"))) return(invisible(NULL))
  if (!once_first(.once, "message")) return(invisible(NULL))
  cnd = gptr_condition(message, class, "message", c(list(...), .data))
  stream = gptr_message_stream(.stream)
  withRestarts({
    signalCondition(cnd)
    gptr_message_write(conditionMessage(cnd), stream, margin = TRUE)
  }, muffleMessage = function() NULL)
  invisible(NULL)
}

#' Resolve the display stream without changing options or suppressing caller handlers
#' @noRd
gptr_message_stream = function(stream = NULL) {
  k = sys.nframe() - 1L
  while (k >= 1L) {
    scoped = get0(".gptr_message_stream", envir = sys.frame(k), inherits = FALSE)
    if (identical(scoped, "stderr")) return("stderr")
    k = k - 1L
  }
  if (is.null(stream)) "stdout" else check_choice(stream, c("stdout", "stderr"), ".stream")
}

#' Display a condition or console control through a scoped evaluator writer when present
#' The evaluator records conditions separately and excludes control text from tool output; a
#' writer hands the text to the next one below frame `from` (D-188); a notice's own display
#' (`margin`) keeps the console margin. Text written where the console's live row is shown (the
#' sink it was drawn at, `the$live_row`, console_live()) clears the row first and, once it ends a
#' line, redraws it where the row erases cleanly; where the row is padded with spaces it stays
#' cleared until the run next waits (D-243).
#' @noRd
gptr_message_write = function(text, stream, margin = FALSE, from = sys.nframe() - 1L) {
  k = from
  while (k >= 1L) {
    write = get0(".gptr_message_write", envir = sys.frame(k), inherits = FALSE)
    if (is.function(write)) return(invisible(write(text, stream, margin, k)))
    k = k - 1L
  }
  if (margin) text = gptr_message_margin(text)
  out = function(x, file = stdout()) {
    cat(x, file = file, sep = "")
    utils::flush.console()
  }
  row = the$live_row
  shown = isTRUE(row$shown) && sink.number() == row$sinks
  if (shown) row$clear(out)
  out(text, if (stream == "stderr") stderr() else stdout())
  if (shown) {
    if (row$erase && endsWith(text, "\n")) row$draw(write = out) else row$on = FALSE
  }
  invisible(NULL)
}

#' What an evaluation on the stack holds about the console it started from (eval_one()'s
#' `.gptr_console_pad` and `.gptr_console_colors`), or NULL outside one
#' @noRd
console_eval_value = function(name) {
  k = sys.nframe() - 1L
  while (k >= 1L) {
    x = get0(name, envir = sys.frame(k), inherits = FALSE)
    if (!is.null(x)) return(x)
    k = k - 1L
  }
  NULL
}

#' The left margin of console output (D-186): two columns where the console renderer is active
#' (verbosity 2+ on a dynamic console, so also in capture.output() of an interactive call), else
#' none, so Rscript, knitr, jsonl and tests keep the plain layout. Inside an evaluation, whose
#' options say no dynamic console, the margin of the console it started from
#' @noRd
console_pad = function() {
  console_eval_value(".gptr_console_pad") %||%
    (if (verbosity() >= 2L && cli::is_dynamic_tty()) "  " else "")
}

#' The colours of console output: inside an evaluation, whose options say 1 colour, those of the
#' console it started from (D-245)
#' @noRd
console_colors = function() console_eval_value(".gptr_console_colors") %||% cli::num_ansi_colors()

#' The console's style table (IC-82, D-245): the glyphs of the logo's cursor vocabulary (the
#' person's chevron, a tool call's thin strip, the agent's block), the logo's red and a darker
#' logo blue (basic red and blue below 256 colours; cli drops them at 1 colour, `NO_COLOR`), the
#' one grey `dim` (halfway between the logo's ink and cream where 256 colours show, as consoles
#' that ignore SGR 2 show it too; else SGR 2), the input band in a T console (console_class())
#' where the background is known and 256 colours show it, with `band_dim` the grey of words on it
#' (also where the band is drawn inside an evaluation), and the R code theme in those colours.
#' ASCII where the output is not
#' UTF-8 and in Windows consoles outside Windows Terminal and RStudio (Rgui among them), whose
#' fonts lack U+258E and U+21B3 (WGL4); there the person's chevron is doubled, `>>`, so an answer
#' never reads as R's own prompt. Here in L0, so an evaluation's display of its output can use it
#' (eval_echo(); visual review).
#' @noRd
console_style = function() {
  ascii = !cli::is_utf8_output() ||
    (is_windows() && !nzchar(Sys.getenv("WT_SESSION")) && front_end() != "rstudio")
  glyphs = if (ascii) {
    list(person = ">>", tool = "|", agent = "#", queued = "->", up = "Up", bullet = "-",
         nested = "-", sep = " - ", ellipsis = "...")
  } else {
    list(person = "\u203a", tool = "\u258e", agent = "\u258c", queued = "\u21b3", up = "\u2191",
         bullet = "\u2022", nested = "\u25e6", sep = " \u00b7 ", ellipsis = "\u2026")
  }
  deep = cli::num_ansi_colors() >= 256L
  red = if (deep) "#b85450" else "red"
  blue = if (deep) "#557ea8" else "blue"
  grey = if (deep) "#878787" else "dim"
  bg = console_background()
  known = deep && !is.na(bg)
  # never in RStudio's or a Windows console, TERM=dumb or Rscript
  band = if (known && console_class() == "T") {
    c(dark = "\033[48;5;237m", light = "\033[48;5;254m")[[bg]]
  } else {
    ""
  }
  # the grey of words on the band, a step darker (light) or lighter (dark), so they keep contrast
  on_band = if (known) c(dark = "#a8a8a8", light = "#6c6c6c")[[bg]] else grey
  c(glyphs, list(
    red = cli::make_ansi_style(red),
    blue = cli::make_ansi_style(blue),
    dim = cli::make_ansi_style(grey),
    band = band,
    band_dim = cli::make_ansi_style(on_band),
    code = list(reserved = red, string = blue, number = blue, null = blue, call = "bold",
                comment = grey)
  ))
}

#' The terminal's background, "dark", "light" or NA, in `the$background` (IC-82): a T REPL's
#' terminal answers at its start (repl_background()); else the last field of COLORFGBG, read once,
#' 0-6 or 8 dark, 7 or 9-15 light
#' @noRd
console_background = function() {
  if (is.null(the$background)) {
    i = suppressWarnings(as.integer(sub(".*;", "", Sys.getenv("COLORFGBG"))))
    the$background = if (i %in% c(0:6, 8L)) "dark" else if (i %in% 0:15) "light" else NA_character_
  }
  the$background
}

#' The background a terminal's answer to `ESC ] 11 ; ?` in `x` names (IC-82): "dark" where the
#' luminance of its `rgb:` colour (1 to 4 hex digits a component, ended by BEL or ST), weighed as
#' Codex does (0.299 red, 0.587 green, 0.114 blue), is below 0.5, else "light"; NA without one
#' @noRd
background_reply = function(x) {
  hex = "([[:xdigit:]]{1,4})"
  m = regmatches(x, regexec(paste0("\033\\]11;rgb:", hex, "/", hex, "/", hex, "(\a|\033\\\\)"),
                            x, perl = TRUE))[[1L]]
  if (!length(m)) return(NA_character_)
  v = strtoi(m[2:4], 16L) / (16^nchar(m[2:4]) - 1)
  if (sum(c(0.299, 0.587, 0.114) * v) < 0.5) "dark" else "light"
}

#' Notice lines inside the console margin; a line that does not fit is word-wrapped at the
#' content width and keeps its indentation (D-186); unchanged without a margin
#' @noRd
gptr_message_margin = function(text) {
  pad = console_pad()
  if (!nzchar(pad) || !nzchar(text)) return(text)
  lines = console_wrap(strsplit(text, "\n", fixed = TRUE)[[1L]],
                       max(20L, cli::console_width() - 4L))
  paste0(ifelse(nzchar(lines), pad, ""), lines, "\n", collapse = "")
}

#' Rows cut to `width` display columns, each cut one ending in `ellipsis`; one row at a time, as
#' cli 3.6.6's ansi_strtrim() of a vector also shortens rows that fit when another is cut
#' @noRd
console_cut = function(rows, width, ellipsis = console_style()$ellipsis) {
  vapply(as.character(rows), function(r) as.character(cli::ansi_strtrim(r, width, ellipsis)), "",
         USE.NAMES = FALSE)
}

#' Lines wrapped at `width`, continuation rows indented like their line (a wider word stays whole)
#' @noRd
console_wrap = function(lines, width) {
  as.character(unlist(lapply(lines, function(line) {
    if (cli::ansi_nchar(line, type = "width") <= width) return(line)
    lead = attr(regexpr("^ *", cli::ansi_strip(line)), "match.length")
    cli::ansi_strwrap(line, width, indent = lead, exdent = lead)
  })))
}

#' The lines print(x) shows; in the console margin at its content width, so that
#' gptr_message_margin() does not wrap them again (D-186)
#' @noRd
print_lines = function(x) {
  if (nzchar(console_pad())) {
    width = max(20L, cli::console_width() - 4L)
    old = options(width = width, cli.width = width)
    on.exit(options(old))
  }
  utils::capture.output(print(x))
}

#' TRUE the first time a once-key is seen in this process (always TRUE for NULL keys)
#' @noRd
once_first = function(key, kind) {
  if (is.null(key)) return(TRUE)
  slot = paste0(kind, ":", key)
  if (isTRUE(the$once[[slot]])) return(FALSE)
  assign(slot, TRUE, envir = the$once)
  TRUE
}

#' Print untrusted text verbatim (never as a format string)
#' @noRd
msg_verbatim = function(x, stream = c("stdout", "stderr")) {
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  stream = gptr_message_stream(stream)
  x = as_utf8(as.character(x))
  if (identical(stream, "stdout")) {
    if (length(x)) cat(paste0(x, "\n"), sep = "")
    utils::flush.console()
  } else {
    cat(x, file = stderr(), sep = "\n")
  }
  invisible(NULL)
}

#' Deprecation notice: a warning once per `what`, an error with options(gptr.deprecations = "error")
#' @noRd
gptr_deprecated = function(what, since, instead = NULL) {
  check_string(what, "what")
  check_string(since, "since")
  text = paste0("`", what, "` is deprecated since gptr ", since)
  if (!is.null(instead)) text = paste0(text, "; use `", instead, "` instead")
  text = paste0(text, ".")
  if (identical(gptr_opt("deprecations"), "error")) {
    gptr_abort(text, "deprecated", what = what)
  }
  gptr_warn(text, "deprecated", what = what, .once = paste0("deprecated:", what))
}

# Argument checkers (contract section 1.1). Each returns the (possibly normalised) value
# invisibly or signals gptr_error_invalid_argument with fields `arg` and `expected`. Messages
# name the class and length of a bad value, never the value itself.

#' @noRd
arg_abort = function(x, arg, expected) {
  what = if (is.null(x)) "NULL" else paste0("a ", class(x)[1L], " of length ", length(x))
  gptr_abort(
    paste0("`", arg, "` must be ", expected, ", not ", what, "."),
    "invalid_argument",
    arg = arg,
    expected = expected
  )
}

#' @noRd
check_string = function(x, arg, null = FALSE, empty = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  ok = rlang::is_string(x) && (empty || nzchar(x))
  if (!ok) arg_abort(x, arg, if (empty) "a single string" else "a single non-empty string")
  invisible(x)
}

#' @noRd
check_strings = function(x, arg, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.character(x) || anyNA(x)) arg_abort(x, arg, "a character vector without NA")
  invisible(x)
}

#' @noRd
check_flag = function(x, arg, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.logical(x) || length(x) != 1L || is.na(x)) arg_abort(x, arg, "TRUE or FALSE")
  invisible(x)
}

#' @noRd
check_number = function(x, arg, min = -Inf, max = Inf, int = FALSE, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  ok = is.numeric(x) && length(x) == 1L && !is.na(x) && x >= min && x <= max
  if (ok && int) {
    ok = is.finite(x) && x == round(x) && abs(x) <= .Machine$integer.max
  }
  if (!ok) {
    expected = paste0(
      if (int) "a whole number" else "a number",
      if (is.finite(min) || is.finite(max)) paste0(" between ", min, " and ", max) else ""
    )
    arg_abort(x, arg, expected)
  }
  if (int) x = as.integer(x)
  invisible(x)
}

#' Exact choice matching; a missing argument (the full default vector) gives its first element
#' @noRd
check_choice = function(x, choices, arg) {
  if (identical(x, choices)) return(invisible(choices[[1L]]))
  ok = rlang::is_string(x) && x %in% choices
  if (!ok) arg_abort(x, arg, paste0("one of ", paste0("\"", choices, "\"", collapse = ", ")))
  invisible(x)
}

#' @noRd
check_function = function(x, arg, null = FALSE, args = NULL) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.function(x)) arg_abort(x, arg, "a function")
  if (length(args)) {
    formal_names = names(formals(x))
    if (!("..." %in% formal_names) && !all(args %in% formal_names)) {
      arg_abort(x, arg, paste0("a function with arguments ", paste(args, collapse = ", ")))
    }
  }
  invisible(x)
}

#' @noRd
check_env = function(x, arg, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.environment(x)) arg_abort(x, arg, "an environment")
  invisible(x)
}

#' @noRd
check_list = function(x, arg, named = FALSE, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.list(x)) arg_abort(x, arg, if (named) "a named list" else "a list")
  if (named && length(x)) {
    nms = names(x)
    if (is.null(nms) || anyNA(nms) || !all(nzchar(nms)) || anyDuplicated(nms)) {
      arg_abort(x, arg, "a list with unique, non-empty names")
    }
  }
  invisible(x)
}

#' @noRd
check_class = function(x, class, arg, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!inherits(x, class)) {
    arg_abort(x, arg, paste0("an object of class <", paste(class, collapse = "/"), ">"))
  }
  invisible(x)
}

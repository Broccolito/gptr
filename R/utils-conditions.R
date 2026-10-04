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

#' Signal a gptr message (silenced by options(gptr.quiet = TRUE))
#' @noRd
gptr_inform = function(message, class, ..., .data = NULL, .once = NULL) {
  if (isTRUE(getOption("gptr.quiet"))) return(invisible(NULL))
  if (!once_first(.once, "message")) return(invisible(NULL))
  message(gptr_condition(message, class, "message", c(list(...), .data)))
  invisible(NULL)
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
  x = as_utf8(as.character(x))
  if (identical(stream, "stdout")) {
    cli::cli_verbatim(x)
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
  ok = is.character(x) && length(x) == 1L && !is.na(x) && (empty || nzchar(x))
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
  ok = is.character(x) && length(x) == 1L && !is.na(x) && x %in% choices
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

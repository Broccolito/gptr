# Package state, the load-time registry and the redaction hook (contract IC-32, IC-34).
# This file collates first (it is the one exception to the <area>-<topic>.R naming rule), so every
# later file may call on_load() at top level: R evaluates package code at install time in
# collation order, and on_load() only stores its expression.

#' Package state
#'
#' `the` holds process-level state only (contract section 7.0). The fields set here are P01's;
#' every other plan adds its own fields from its own files.
#' @noRd
the = new.env(parent = emptyenv())
the$on_load = list()
the$on_unload = list()
the$once = new.env(parent = emptyenv())
the$out = NULL
the$services = list()
the$redactor = NULL
the$load_errors = list()

#' Null default (base R has `%||%` only from R 4.4.0)
#' @noRd
`%||%` = function(x, y) if (is.null(x)) y else x # nolint: object_name_linter.

#' A function of this namespace by name, or NULL when no plan has defined it yet
#'
#' The documented late binding to functions of later plans (`ext_load_builtins()`, the registry
#' of P02): P01 works, and passes R CMD check, before those plans exist.
#' @noRd
ns_fun = function(name) {
  get0(name, envir = environment(ns_fun), mode = "function", inherits = FALSE)
}

#' Register an expression to run when the namespace loads
#'
#' Stores `substitute(expr)` and the calling environment; `.onLoad` evaluates them in
#' registration order (contract IC-32). Nothing in `expr` needs to exist when `on_load()` runs.
#' @noRd
on_load = function(expr) {
  the$on_load[[length(the$on_load) + 1L]] = list(expr = substitute(expr), env = parent.frame())
  invisible(NULL)
}

#' Evaluate stored load-time expressions in order; failures are kept in the$load_errors
#' @noRd
on_load_run = function(entries = the$on_load) {
  failed = 0L
  for (entry in entries) {
    err = tryCatch({
      eval(entry$expr, entry$env)
      NULL
    }, error = function(e) e)
    if (!is.null(err)) {
      failed = failed + 1L
      the$load_errors[[length(the$load_errors) + 1L]] = list(expr = entry$expr, error = err)
    }
  }
  invisible(failed == 0L)
}

#' Register a zero-argument cleanup run by .onUnload (reverse order, each in try())
#' @noRd
on_unload = function(fun) {
  check_function(fun, "fun")
  the$on_unload[[length(the$on_unload) + 1L]] = fun
  invisible(NULL)
}

#' Run and clear the registered unload callbacks
#' @noRd
on_unload_run = function() {
  callbacks = rev(the$on_unload)
  the$on_unload = list()
  for (fun in callbacks) try(fun(), silent = TRUE)
  invisible(NULL)
}

#' Install the function used by redact_hook(); returns the previous one invisibly
#'
#' P03 installs `redact()`; before that the hook is the identity (contract IC-34).
#' @noRd
redactor_set = function(fun) {
  check_function(fun, "fun", null = TRUE)
  old = the$redactor
  the$redactor = fun
  invisible(old)
}

#' Redact text through the installed redactor (the identity until P03 installs one)
#'
#' A failing redactor never lets text through: character input becomes a marker.
#' @noRd
redact_hook = function(x, profile = "persist") {
  fun = the$redactor
  if (is.null(fun)) return(x)
  tryCatch(fun(x, profile = profile), error = function(e) {
    if (!is.character(x)) stop(e)
    rep("[redaction failed]", length(x))
  })
}

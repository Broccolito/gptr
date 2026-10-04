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

# The bootstrap service table (contract IC-09, IC-34, section 7.0). Services are functions that a
# later plan provides and an earlier plan calls. Each is registered from an on_load() expression
# of its provider plan and owned by a built-in: when that built-in is filtered out, the service is
# not available. Once P02 is loaded, a `service` registry record wins over this table.

#' Service name -> providing plan (contract section 7.0); used in "not available" messages and by
#' tests/testthat/helper-arch.R
#' @noRd
service_plans = c(
  "settings.get" = "P08", "prompt.freeze" = "P07", "context.first" = "P07",
  "context.turn" = "P07", "request.build" = "P07", "prefix.guard" = "P07",
  "compact.should" = "P07", "compact.run" = "P07", "ns.resolve" = "P10",
  "console.interrupt_policy" = "P14", "ui.get" = "P11", "risk.classify" = "P11",
  "plan.pending" = "P11", "s1.decide" = "P13", "doc.site" = "P15", "doc.edit" = "P15",
  "doc.s1_block" = "P15", "doc.replay" = "P15", "checkpoint.note" = "P16",
  "agent_def.get" = "P17", "skill.catalog" = "P17", "skill.body" = "P17",
  "plugin.enable" = "P17", "mcp.catalog" = "P18", "mcp.dispatch_local" = "P18",
  "mcp.serve_ensure" = "P18", "bg.register" = "P21", "check.adapter" = "P12",
  "trust.get" = "P08", "identifier.resolve" = "P08", "secret.lookup" = "P03",
  "ctx.kernel" = "P06", "ctx.input" = "P07", "ns.names" = "P10", "eval.r" = "P09",
  "describe" = "P09", "router.call" = "P08", "session.add_tools" = "P07",
  "search.sources" = "P10"
)

#' Register a service in the bootstrap table (contract section 7.1)
#'
#' A second registration of the same name replaces the first; once P02 is loaded the replacement
#' is also recorded as a registry diagnostic.
#' @noRd
ext_service_set = function(name, fun, provided_by, builtin = NULL) {
  check_string(name, "name")
  check_function(fun, "fun")
  check_string(provided_by, "provided_by")
  check_string(builtin, "builtin", null = TRUE)
  replaced = !is.null(the$services[[name]])
  the$services[[name]] = list(name = name, fun = fun, provided_by = provided_by, builtin = builtin)
  diagnostic = ns_fun("registry_diagnostic")
  if (replaced && !is.null(diagnostic)) {
    try(
      diagnostic(
        source = if (is.null(builtin)) "service" else paste0("builtin:", builtin),
        event = "service_replaced",
        class = "service",
        message = paste0("service '", name, "' was registered again and replaced")
      ),
      silent = TRUE
    )
  }
  invisible(name)
}

#' The function of a service, or NULL: a `service` registry record (P02) wins; otherwise the
#' bootstrap entry, provided its owning built-in is active (IC-34)
#' @noRd
service_lookup = function(name) {
  fun = service_from_registry(name)
  if (!is.null(fun)) return(fun)
  entry = the$services[[name]]
  if (is.null(entry) || !service_builtin_active(entry$builtin)) return(NULL)
  entry$fun
}

#' Fetch a service function, or signal gptr_error_not_available naming the providing plan
#' @noRd
ext_service_get = function(name) {
  check_string(name, "name")
  fun = service_lookup(name)
  if (!is.null(fun)) return(fun)
  provider = the$services[[name]]$provided_by %||% unname(service_plans[name])
  if (is.na(provider)) provider = "no known plan"
  gptr_abort(
    paste0(
      "The gptr service '", name, "' is not available: it is provided by ", provider,
      ", which is not loaded or is disabled."
    ),
    "not_available",
    member = name,
    provided_by = provider
  )
}

#' TRUE when a service can be fetched
#' @noRd
ext_service_has = function(name) {
  check_string(name, "name")
  !is.null(service_lookup(name))
}

#' The function of a `service` registry record (P02), or NULL before P02 or when none exists
#' @noRd
service_from_registry = function(name) {
  registry_get = ns_fun("registry_get")
  if (is.null(registry_get)) return(NULL)
  spec = tryCatch(registry_get("service", name), error = function(e) NULL)
  if (is.null(spec) || !is.function(spec$fun)) NULL else spec$fun
}

#' Is the built-in that owns a bootstrap service loaded and not filtered out?
#'
#' Before P02 exists every built-in counts as active. Afterwards a built-in counts as filtered
#' out when gptr_registry() lists records but none of source `builtin:<name>` is enabled (every
#' built-in of contract section 10.3 registers at least one record); an empty registry (while
#' the built-ins are still loading) counts as active.
#' @noRd
service_builtin_active = function(builtin) {
  if (is.null(builtin)) return(TRUE)
  registry = ns_fun("gptr_registry")
  if (is.null(registry)) return(TRUE)
  records = tryCatch(registry(), error = function(e) NULL)
  if (is.null(records) || !nrow(records)) return(TRUE)
  active = records$source[records$state != "disabled"]
  paste0("builtin:", builtin) %in% active
}

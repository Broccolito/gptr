# ext-check.R -- the extension API version and features (contract 6.7 gptr_api()), the
# deprecation helper for API members (contract 10.9; architecture 3.2, 11.4) and the gptr_check()
# conformance suites for specs, factories and installed plugin packages (contract 6.7, 7.2;
# IC-42, IC-69). No network: adapter fixture replay is the `check.adapter` service of P12.

#' Extension API version and features
#'
#' The version of gptr's public extension API (independent of the package version) and the
#' features this build offers: `kind.<name>` for every registered kind, `event.<name>` for every
#' catalogued event, and the named features `lazy_activation`, `declarations`, `ctx.decide`,
#' `ctx.secret`, `route` and `services`. Plugins test features instead of comparing versions.
#'
#' @return A `gptr_api` list with `version` (a `package_version`) and `features` (character).
#' @examples
#' gptr_api()$version
#' "kind.router" %in% gptr_api()$features
#' @export
gptr_api = function() {
  structure(list(version = package_version(ext_api_version),
                 features = c(paste0("kind.", kind_names()), paste0("event.", ev_table$event),
                              "lazy_activation", "declarations", "ctx.decide", "ctx.secret",
                              "route", "services")),
            class = "gptr_api")
}

#' Print the API version and the number of features
#' @export
#' @noRd
print.gptr_api = function(x, ...) {
  cat("<gptr_api ", format(x$version), "> ", length(x$features), " features\n", sep = "")
  invisible(x)
}

#' Deprecated members of the API object ("api") and of ctx ("ctx"): member -> list(since,
#' instead). Extension API 1.0 deprecates nothing; a MINOR release adds entries here and keeps the
#' member for at least one MINOR release and six months (contract 10.9)
#' @noRd
ext_deprecations = function() list(api = list(), ctx = list())

#' Warn once per session about a deprecated member (an error with
#' options(gptr.deprecations = "error")); FALSE when the member is not deprecated
#' @noRd
ext_warn_deprecated = function(object, name) {
  dep = ext_deprecations()[[object]][[name]]
  if (is.null(dep)) return(invisible(FALSE))
  prefix = if (identical(object, "api")) "gptr$" else "ctx$"
  gptr_deprecated(paste0(prefix, name), dep$since, dep$instead)
  invisible(TRUE)
}

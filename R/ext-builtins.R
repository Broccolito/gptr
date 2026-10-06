# ext-builtins.R -- the built-in declaration table and its load order (contract 7.2, 10.3). Each
# built-in declares itself from its own file with on_load(ext_declare_builtin(...)), so later
# plans never edit a shared list (IC-32); .onLoad then calls ext_load_builtins().

the$builtins = list()

#' Declare a built-in extension (contract 7.2); a second declaration of a name replaces the first
#'
#' `after` names built-ins loaded first; `replaceable = FALSE` means no `-builtin:<name>` filter
#' can disable it (contract 10.3, IC-53, IC-69).
#' @noRd
ext_declare_builtin = function(name, factory, after = character(), replaceable = TRUE) {
  check_string(name, "name")
  check_function(factory, "factory")
  check_strings(after, "after")
  check_flag(replaceable, "replaceable")
  if (!grepl("\\A[a-z0-9][a-z0-9-]*\\z", name, perl = TRUE)) {
    gptr_abort("A built-in name must match ^[a-z0-9][a-z0-9-]*$.", "invalid_argument",
               arg = "name", expected = "a lower-case built-in name")
  }
  b = the$builtins %||% list()
  b[[name]] = list(name = name, factory = factory, after = after, replaceable = replaceable)
  the$builtins = b
  invisible(name)
}

#' Built-in names in load order, each after the declared built-ins of its `after`; a cycle is a
#' diagnostic and loads in declaration order
#' @noRd
ext_builtin_order = function(builtins = the$builtins %||% list()) {
  pending = names(builtins)
  done = character()
  while (length(pending)) {
    ready = pending[vapply(pending, function(n) {
      all(intersect(builtins[[n]]$after, names(builtins)) %in% done)
    }, NA)]
    if (!length(ready)) {
      registry_diagnostic("builtins", "load", "cycle",
                          paste0("circular `after` among built-ins ",
                                 paste(pending, collapse = ", "),
                                 "; they are loaded in declaration order"))
      ready = pending
    }
    done = c(done, ready)
    pending = setdiff(pending, ready)
  }
  done
}

#' Load the declared built-ins into the current registry in dependency order (contract 7.2)
#'
#' Each is attempted once per registry (a failed one is not retried) unless a filter disables
#' it; returns the names loaded now, invisibly.
#' @noRd
ext_load_builtins = function() {
  b = the$builtins %||% list()
  reg = registry_env()
  loaded = character()
  for (nm in ext_builtin_order(b)) {
    src = paste0("builtin:", nm)
    if (nm %in% reg$builtins_loaded || registry_source_filtered(src)) next
    reg$builtins_loaded = c(reg$builtins_loaded, nm)
    if (ext_load(b[[nm]]$factory, source = src, rank = 6L)) loaded = c(loaded, nm)
  }
  invisible(loaded)
}

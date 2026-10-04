# ext-builtins.R -- the built-in declaration table and its load order (contract 7.2, 10.3;
# architecture 2.2 rule 3, 3.2). Each built-in is declared from its own file with
# on_load(ext_declare_builtin("<name>", builtin_<name>)); P01's .onLoad evaluates the on_load()
# expressions and then calls ext_load_builtins(), which loads every declared built-in through
# ext_load(source = "builtin:<name>", rank = 6L), so later plans never edit a shared list (IC-32).

the$builtins = list()

#' Declare a built-in extension (contract 7.2)
#'
#' `after` names built-ins that must be loaded first; `replaceable = FALSE` means no
#' `-builtin:<name>` filter can disable it (contract 10.3, IC-53, IC-69). Declaring a name again
#' replaces the earlier declaration.
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

#' Built-in names in load order: every built-in after the declared built-ins it names in `after`
#' (names that are not declared are ignored); a cycle is reported and loaded in declaration order
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
#' Skips built-ins already attempted in this registry and built-ins disabled by a
#' `-builtin:<name>` filter; called by .onLoad and again when a `+builtin:<name>` filter
#' re-enables one. Failed factories stay disabled for this registry's lifetime, preventing
#' automatic retries of their load-time effects; a fresh registry can attempt them again.
#' Returns only the names successfully loaded now, invisibly.
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

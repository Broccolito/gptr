# ext-api.R -- the factory API object (contract 5.6, 10.5) and the ctx object handlers receive
# (contract 5.6, 10.6). Both are classed environments. No binding is locked (IC-26, rule R5): the
# `$<-` and `[[<-` methods refuse assignment instead. Shapes follow the verified G1 prototype
# (report G1 3.3, 5.1 api_new() and session_ctx(), 5.3), minus its binding locks, with the
# verification-log fix of row 25 (one-component requirements such as "2" become "2.0").

# ---- the factory API object (contract 5.6, 10.5) ------------------------------------------------

#' A new extension record (one per ext_load() or ext_api_new() call)
#'
#' `ids` are the committed record ids, `placeholders` the ids of lazy placeholders, `stage` the
#' registrations staged while the factory runs; `unloaded = TRUE` makes its API object stale.
#' @noRd
ext_info_new = function(source, dir = NULL, manifest = NULL) {
  registry_check_source(source)
  reg = registry_env()
  reg$ext_seq = reg$ext_seq + 1L
  info = new.env(parent = emptyenv())
  info$id = paste0("e", reg$ext_seq)
  info$source = source
  info$dir = dir
  info$manifest = manifest
  info$rank = ext_source_rank(source)
  info$session = NULL
  info$status = "active"
  info$stage = list()
  info$ids = character()
  info$placeholders = character()
  info$factory = NULL
  info$lazy = FALSE
  info$lazy_origin = FALSE
  info$api = NULL
  info$unloaded = FALSE
  assign(info$id, info, envir = reg$exts)
  info
}

#' Rank of a source string (contract 10.1)
#' @noRd
ext_source_rank = function(source) {
  if (startsWith(source, "builtin:")) return(6L)
  if (startsWith(source, "plugin:")) return(5L)
  switch(source, session = 0L, project = 1L, user = 3L, 3L)
}

#' The process-lifetime state environment behind `gptr$state` (contract 10.5): one per plugin or
#' built-in source; extensions loaded as session, user or project code get one per load
#' @noRd
ext_state = function(info) {
  key = if (info$source %in% c("session", "user", "project")) info$id else info$source
  reg = registry_env()
  st = get0(key, envir = reg$states, inherits = FALSE)
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    assign(key, st, envir = reg$states)
  }
  st
}

#' Signal gptr_error_stale_api unless the API object is still current
#' @noRd
api_alive = function(info, reg, gen) {
  current = identical(the$registry, reg) && identical(reg$generation, gen) && !isTRUE(info$unloaded)
  if (!current) {
    gptr_abort(paste0("This extension API object of ", info$source, " is stale: the registry was ",
                      "reloaded or the extension was unloaded. Use the API object passed to the ",
                      "current factory call."),
               "stale_api", plugin = info$source, generation = gen)
  }
  invisible(TRUE)
}

#' Commit one spec for an extension; returns the record id
#' @noRd
ext_commit_one = function(info, spec) {
  reg = registry_env()
  prev = reg$current_ext
  reg$current_ext = info$id
  on.exit({
    reg$current_ext = prev
  }, add = TRUE)
  id = registry_add(spec, source = info$source, rank = info$rank, session = info$session)
  info$ids = c(info$ids, id)
  id
}

#' The unregister closure of one registration (cancels it while staged)
#' @noRd
ext_item_unregister = function(item, info) {
  force(item)
  force(info)
  reg = registry_env()
  gen = reg$generation
  function() {
    api_alive(info, reg, gen)
    if (is.null(item$id)) item$cancelled = TRUE else registry_remove(item$id)
    invisible(TRUE)
  }
}

#' The register() verb: staged while the factory runs, committed directly afterwards (10.5)
#' @noRd
ext_register = function(info, spec) {
  if (!inherits(spec, "gptr_spec")) {
    gptr_abort("register() needs a spec made by gptr_spec() or a gptr_*() constructor.",
               "invalid_spec", kind = "?", name = "?", field = "spec",
               problem = "is not a gptr_spec")
  }
  item = new.env(parent = emptyenv())
  item$spec = spec
  item$id = NULL
  item$cancelled = FALSE
  if (identical(info$status, "loading")) {
    if (identical(spec$kind, "kind")) kind_stage(spec, info$id, info$source)
    info$stage = c(info$stage, list(item))
  } else {
    item$id = ext_commit_one(info, spec)
  }
  invisible(ext_item_unregister(item, info))
}

#' Parse an API requirement: "1.2" is caret (>= 1.2, < 2); otherwise comma-separated
#' "op version" with op in >=, >, <=, <, == (report G1 3.5; "2" is normalised to "2.0")
#' @noRd
api_parse_requires = function(requires, plugin = "?") {
  check_string(requires, "requires")
  invalid = function(part) {
    gptr_abort(paste0("Cannot parse the API requirement '", part, "'."), "api_version",
               plugin = plugin, required = requires, available = ext_api_version)
  }
  if (grepl(",\\s*\\z", requires, perl = TRUE)) invalid(requires)
  parts = trimws(strsplit(requires, ",", fixed = TRUE)[[1]])
  lapply(parts, function(p) {
    m = regmatches(p, regexec("\\A(>=|<=|==|>|<)?\\s*([0-9]+(\\.[0-9]+)*)\\z",
                              p, perl = TRUE))[[1]]
    if (!length(m) || (length(parts) > 1L && !nzchar(m[[2]]))) invalid(p)
    components = suppressWarnings(as.double(strsplit(m[[3]], ".", fixed = TRUE)[[1]]))
    if (any(!is.finite(components) | components > .Machine$integer.max)) invalid(p)
    v = if (grepl(".", m[[3]], fixed = TRUE)) m[[3]] else paste0(m[[3]], ".0")
    version = tryCatch(package_version(v), error = function(e) invalid(p),
                        warning = function(w) invalid(p))
    list(op = if (nzchar(m[[2]])) m[[2]] else "^", v = version)
  })
}

#' Does this API satisfy a requirement string? (`plugin` names the requirer in parse errors)
#' @noRd
api_satisfies = function(requires, provided = package_version(ext_api_version), plugin = "?") {
  for (cn in api_parse_requires(requires, plugin)) {
    ok = switch(cn$op,
                ">=" = provided >= cn$v, ">" = provided > cn$v, "<=" = provided <= cn$v,
                "<" = provided < cn$v, "==" = provided == cn$v,
                "^" = provided >= cn$v && provided$major == cn$v$major)
    if (!isTRUE(ok)) return(FALSE)
  }
  TRUE
}

#' gptr$require(): signal gptr_error_api_version when unmet
#' @noRd
api_require = function(requires, plugin) {
  check_string(requires, "requires")
  if (!api_satisfies(requires, plugin = plugin)) {
    gptr_abort(paste0(plugin, " requires gptr extension API ", requires, ", but this gptr ",
                      "provides API ", ext_api_version, "."),
               "api_version", plugin = plugin, required = requires, available = ext_api_version)
  }
  invisible(TRUE)
}

#' The register_<kind>() sugar: gptr$register(gptr_spec("<kind>", ...)) (contract 10.5)
#' @noRd
api_sugar = function(api, kind) {
  force(api)
  force(kind)
  function(...) api$register(gptr_spec(kind, ...))
}

#' Member names of an API object
#' @noRd
api_members = function(x) {
  c("name", "dir", "state", "register", paste0("register_", kind_names()), "on", "require", "has")
}

#' Build the API object of an extension record
#' @noRd
api_build = function(info, reg) {
  gen = reg$generation
  api = new.env(parent = emptyenv())
  api$name = info$source
  api$dir = info$dir
  api$state = ext_state(info)
  api$register = function(spec) {
    api_alive(info, reg, gen)
    ext_register(info, spec)
  }
  api$on = function(event, handler, matcher = NULL) {
    api_alive(info, reg, gen)
    ext_register(info, gptr_hook(event, handler, matcher))
  }
  api$require = function(requires) {
    api_alive(info, reg, gen)
    api_require(requires, info$source)
  }
  api$has = function(feature) {
    api_alive(info, reg, gen)
    check_string(feature, "feature")
    feature %in% gptr_api()$features
  }
  class(api) = "gptr_extension_api"
  info$api = api
  api
}

#' The API object handed to a factory (contract 7.2)
#' @noRd
ext_api_new = function(source, dir = NULL, manifest = NULL) {
  check_string(source, "source")
  check_string(dir, "dir", null = TRUE)
  check_list(manifest, "manifest", null = TRUE)
  info = ext_info_new(source, dir, manifest)
  api_build(info, registry_env())
}

#' Get an API member; register_<kind> sugar exists for every registered kind
#' @export
#' @noRd
`$.gptr_extension_api` = function(x, name) {
  ext_warn_deprecated("api", name)
  if (exists(name, envir = x, inherits = FALSE)) return(get(name, envir = x, inherits = FALSE))
  if (startsWith(name, "register_") && substring(name, 10L) %in% kind_names()) {
    return(api_sugar(x, substring(name, 10L)))
  }
  gptr_abort(paste0("The gptr extension API ", ext_api_version, " has no member '", name,
                    "'; test with gptr$has() or require a newer API."),
             "unknown_member", name = name, available = api_members(x))
}

#' Get an API member by name
#' @export
#' @noRd
`[[.gptr_extension_api` = function(x, i, ...) `$.gptr_extension_api`(x, i)

#' The API object is read-only except for re-assigning its own state environment (IC-26)
#' @export
#' @noRd
`$<-.gptr_extension_api` = function(x, name, value) {
  if (identical(name, "state") && identical(value, get("state", envir = x, inherits = FALSE))) {
    return(x)
  }
  gptr_abort(paste0("The gptr extension API object is read-only; '", name, "' cannot be ",
                    "assigned. Keep extension state in gptr$state."),
             "readonly", object = "gptr_extension_api", field = name)
}

#' The API object is read-only (IC-26)
#' @export
#' @noRd
`[[<-.gptr_extension_api` = function(x, i, value) `$<-.gptr_extension_api`(x, i, value)

#' Print an API object: its version, source and members
#' @export
#' @noRd
print.gptr_extension_api = function(x, ...) {
  cat("<gptr_extension_api ", ext_api_version, "> ", get("name", envir = x), "\n", sep = "")
  cat("members: ", paste(api_members(x), collapse = ", "), "\n", sep = "")
  invisible(x)
}

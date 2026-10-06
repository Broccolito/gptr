# ext-load.R -- transactional factory loading (stage, commit, rollback), API requirements, lazy
# activation from manifests, session-scoped extensions, package unload and gptr_reload()
# (contract 7.2, 10.8; IC-69; architecture 11.2).

#' The API requirement of an extension: the manifest's `gptr.api`, else the factory attribute
#' `gptr_api` (report G1 3.5); NULL when none is declared
#' @noRd
ext_requirement = function(factory, manifest) {
  manifest[["gptr"]][["api"]] %||% attr(factory, "gptr_api", exact = TRUE)
}

#' Signal gptr_error_api_version unless the requirement `req` (or NULL) is met
#' @noRd
ext_check_requirement = function(req, source) {
  if (!is.null(req)) api_require(req, source)
  invisible(TRUE)
}

#' The `provides` table of a manifest as kind -> character vector of names
#' @noRd
ext_provides = function(manifest) {
  p = manifest[["extension"]][["provides"]]
  if (is.null(p) || identical(p, list())) return(list())
  check_list(p, "provides", named = TRUE)
  out = lapply(p, function(x) {
    if (!length(x)) return(character())
    value = unlist(x, use.names = FALSE)
    check_strings(value, "provided names")
    if (any(!nzchar(value)) || anyDuplicated(value)) {
      gptr_abort("Manifest provides must name unique capabilities.", "invalid_argument",
                 arg = "provides", expected = "unique capability names")
    }
    value
  })
  out[lengths(out) > 0L]
}

#' Is the manifest's activation lazy (anything but "eager")?
#' @noRd
ext_manifest_lazy = function(manifest) {
  eager = identical(manifest[["extension"]][["activation"]], "eager")
  !eager && length(ext_provides(manifest)) > 0L
}

#' A lazy placeholder spec for one provided name (contract 10.8); its manifest `declaration`
#' lets catalogs list the capability before the factory runs (hooks are provided by event name)
#' @noRd
ext_placeholder = function(kind, name, source, declaration = NULL) {
  spec = list(kind = kind, name = name, lazy = TRUE, source = source, declaration = declaration,
              api_version = ext_api_version)
  if (identical(kind, "hook")) spec$event = name
  structure(spec, class = c(paste0("gptr_", kind), "gptr_spec"))
}

#' Remove an extension's lazy placeholders
#' @noRd
ext_drop_placeholders = function(info) {
  for (id in info$placeholders) registry_remove(id)
  info$placeholders = character()
  invisible(NULL)
}

#' Undefine the kinds staged by an extension whose load failed
#' @noRd
kinds_unstage = function(ext_id) {
  k = kinds_env()
  for (nm in ls(k)) {
    d = get(nm, envir = k, inherits = FALSE)
    if (identical(d$staged, ext_id)) rm(list = nm, envir = k)
  }
  registry_touch()
  invisible(NULL)
}

#' Snapshot the extension's state bindings before its factory runs (restored on failure; effects
#' through reference objects in them are not)
#' @noRd
ext_state_snapshot = function(info) {
  key = if (info$source %in% c("session", "user", "project")) info$id else info$source
  env = get0(key, envir = registry_env()$states, inherits = FALSE)
  info$state_before = list(key = key, env = env,
                           values = if (is.null(env)) NULL else as.list(env, all.names = TRUE))
  invisible(NULL)
}

#' Restore or remove the state owned by a failed factory
#' @noRd
ext_state_restore = function(info) {
  before = info$state_before
  if (is.null(before)) return(invisible(NULL))
  states = registry_env()$states
  if (is.null(before$env)) {
    if (exists(before$key, envir = states, inherits = FALSE)) rm(list = before$key, envir = states)
  } else {
    env = before$env
    rm(list = ls(env, all.names = TRUE), envir = env)
    list2env(before$values, envir = env)
    assign(before$key, env, envir = states)
  }
  info$state_before = NULL
  invisible(NULL)
}

#' Roll back the resources owned by a failed or interrupted extension
#' @noRd
ext_rollback = function(info) {
  kinds_unstage(info$id)
  info$stage = list()
  for (id in info$ids) registry_remove(id)
  info$ids = character()
  ext_drop_placeholders(info)
  ext_state_restore(info)
  info$status = "failed"
  ext_forget(info)
  invisible(NULL)
}

#' Roll a failed extension back with a diagnostic and a `plugin` warning once per source
#' @noRd
ext_fail = function(info, err) {
  ext_rollback(info)
  msg = conditionMessage(err)
  registry_diagnostic(info$source, "load", class(err)[[1]], msg)
  gptr_warn(paste0("The gptr extension ", info$source, " was disabled: ", msg), "plugin",
            diagnostic = msg, .once = paste0("plugin:", info$source))
  FALSE
}

#' Commit the staged registrations: kinds first, then the rest in registration order
#' @noRd
ext_commit = function(info, reg, generation) {
  items = Filter(function(it) !isTRUE(it$cancelled), info$stage)
  is_kind = vapply(items, function(it) identical(it$spec$kind, "kind"), NA)
  info$stage = list()
  kinds_unstage(info$id)
  for (it in c(items[is_kind], items[!is_kind])) {
    it$id = ext_commit_one(info, it$spec)
    api_alive(info, reg, generation)
  }
  invisible(NULL)
}

#' Diagnostics for provided names the factory did not register (report G1 4.4 rule 4)
#' @noRd
ext_check_provided = function(info) {
  reg = registry_env()
  provides = ext_provides(info$manifest)
  for (kind in names(provides)) {
    for (nm in provides[[kind]]) {
      if (identical(kind, "hook")) {
        ids = get0(nm, envir = reg$hooks, inherits = FALSE)
      } else {
        ids = get0(paste(kind, nm, sep = "\r"), envir = reg$by_key, inherits = FALSE)
      }
      recs = registry_recs(reg, ids)
      mine = vapply(recs, function(r) identical(r$ext, info$id) && !identical(r$state, "lazy"), NA)
      if (!any(mine)) {
        registry_diagnostic(info$source, "activate", "missing_provided",
                            paste0(info$source, " declares ", kind, " '", nm,
                                   "' in its manifest but its factory did not register it"))
      }
    }
  }
  invisible(NULL)
}

#' Run an extension's factory transactionally: stage, then commit; an error rolls back with a
#' diagnostic, an interrupt rolls back on exit and propagates (contract 7.2)
#' @noRd
ext_run_factory = function(info) {
  reg = registry_env()
  # a lookup the factory makes does not drain deferred events under it (D-085)
  registry_enter(reg, drain = FALSE)
  on.exit(registry_leave(reg), add = TRUE)
  generation = reg$generation
  info$status = "loading"
  on.exit(if (identical(info$status, "loading")) ext_rollback(info), add = TRUE)
  ext_drop_placeholders(info)
  info$lazy = FALSE
  info$stage = list()
  err = tryCatch({
    ext_provides(info$manifest)
    ext_check_requirement(ext_requirement(info$factory, info$manifest), info$source)
    ext_state_snapshot(info)
    info$factory(api_build(info, reg))
    api_alive(info, reg, generation)
    ext_commit(info, reg, generation)
    ext_check_provided(info)
    if (startsWith(info$source, "plugin:")) {
      pkg = substring(info$source, 8L)
      if (isNamespaceLoaded(pkg)) ext_watch_unload(pkg, info$source)
    }
    NULL
  }, error = function(e) e)
  if (!is.null(err)) return(ext_fail(info, err))
  info$status = "active"
  info$state_before = NULL
  TRUE
}

#' Register the placeholders and declarations of a lazy extension (contract 10.8)
#' @noRd
ext_declare_lazy = function(info) {
  reg = registry_env()
  provides = ext_provides(info$manifest)
  decl = info$manifest[["extension"]][["declarations"]] %||% list()
  info$status = "lazy"
  info$lazy = TRUE
  prev = reg$current_ext
  reg$current_ext = info$id
  on.exit({
    reg$current_ext = prev
  }, add = TRUE)
  for (kind in names(provides)) {
    for (nm in provides[[kind]]) {
      spec = ext_placeholder(kind, nm, info$source, decl[[nm]])
      id = registry_add(spec, source = info$source, rank = info$rank, session = info$session,
                        state = "lazy")
      info$placeholders = c(info$placeholders, id)
    }
  }
  TRUE
}

#' Load an extension factory (contract 7.2); TRUE when it is loaded or declared
#'
#' With `lazy` and a manifest that provides capabilities, only placeholders are registered until
#' first use; with `session` every record is scoped to that session (IC-69).
#' @noRd
ext_load = function(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE,
                    session = NULL) {
  check_function(factory, "factory")
  registry_check_source(source)
  rank = check_number(rank, "rank", min = 0, max = 99, int = TRUE)
  check_string(dir, "dir", null = TRUE)
  check_list(manifest, "manifest", null = TRUE)
  check_flag(lazy, "lazy")
  sid = ext_session_id(session)
  check_string(sid, "session", null = is.null(session) && !identical(source, "session"))
  if (registry_source_filtered(source)) {
    registry_diagnostic(source, "load", "filtered", paste0(source, " is disabled by a filter"))
    return(FALSE)
  }
  reg = registry_env()
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  info = ext_info_new(source, dir, manifest)
  info$rank = rank
  info$session = sid
  info$factory = factory
  result = tryCatch({
    if (lazy && ext_manifest_lazy(manifest)) {
      ext_check_requirement(ext_requirement(factory, manifest), source)
      info$lazy_origin = TRUE
      ext_declare_lazy(info)
    } else {
      ext_run_factory(info)
    }
  }, error = function(e) e)
  if (inherits(result, "error")) ext_fail(info, result) else result
}

#' Activate the lazy extensions of a source (contract 7.2); TRUE when one was activated
#' @noRd
ext_activate = function(source) {
  check_string(source, "source")
  reg = registry_env()
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  done = FALSE
  for (eid in ls(reg$exts)) {
    info = get0(eid, envir = reg$exts, inherits = FALSE)
    if (is.null(info)) next
    if (identical(info$source, source) && identical(info$status, "lazy")) {
      done = ext_run_factory(info) || done
    }
  }
  done
}

#' Activate the extension behind a lazy placeholder record; a placeholder whose extension is gone
#' is removed
#' @noRd
ext_activate_record = function(rec) {
  info = get0(rec$ext %||% "", envir = registry_env()$exts, inherits = FALSE)
  if (is.null(info) || !identical(info$status, "lazy")) {
    registry_remove(rec$id)
    return(FALSE)
  }
  ext_run_factory(info)
}

#' Remove every record of a source and make its API objects stale (package unload, contract
#' 10.8); returns the number of records removed
#' @noRd
ext_unload = function(source) {
  check_string(source, "source")
  reg = registry_env()
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  n = registry_drop_where("source", source, reg)
  registry_diagnostic(source, "unload", "unloaded",
                      paste0(source, " was unloaded; ", n, " record(s) removed"))
  invisible(n)
}

#' Remove one function from a hook list
#' @noRd
ext_unhook = function(hook, fun) {
  keep = Filter(function(h) !identical(h, fun), getHook(hook))
  setHook(hook, if (length(keep)) keep else NULL, action = "replace")
  invisible(NULL)
}

#' Remove a plugin package's records when its namespace unloads (contract 10.8); the hook leaves
#' with gptr (on_unload())
#' @noRd
ext_watch_unload = function(pkg, source = paste0("plugin:", pkg)) {
  check_string(pkg, "pkg")
  reg = registry_env()
  if (pkg %in% reg$watched) return(invisible(FALSE))
  reg$watched = c(reg$watched, pkg)
  hook = packageEvent(pkg, "onUnload")
  fun = function(...) ext_unload(source)
  setHook(hook, fun)
  on_unload(function() ext_unhook(hook, fun))
  invisible(TRUE)
}

#' Reload extensions
#'
#' Bumps the registry generation, so that extension API objects captured by old code signal
#' `gptr_error_stale_api`, and re-declares lazily activated plugins from their manifests (their
#' factories run again on first use). Discovery of declarative resources (skills, prompts, agents,
#' MCP configurations, plugin manifests) is keyed on the generation, so it runs again on next
#' use. Sessions whose prompt is already frozen are not changed. Refused from model code while a
#' run executes a tool, unless the user approved that call.
#'
#' @return The new registry generation (an integer), invisibly.
#' @examples
#' gptr_reload()
#' @export
gptr_reload = function() {
  ext_control_guard("gptr_reload")
  reg = registry_env()
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  reg$generation = reg$generation + 1L
  for (eid in ls(reg$exts)) {
    info = get0(eid, envir = reg$exts, inherits = FALSE)
    if (is.null(info)) next
    redeclare = isTRUE(info$lazy_origin) && identical(info$status, "active") &&
      !isTRUE(info$unloaded)
    if (!redeclare) next
    for (id in info$ids) registry_remove(id)
    info$ids = character()
    info$status = "reloaded"
    fresh = ext_info_new(info$source, info$dir, info$manifest)
    fresh$rank = info$rank
    fresh$session = info$session
    fresh$factory = info$factory
    fresh$lazy_origin = TRUE
    ext_forget(info, reg)
    ext_declare_lazy(fresh)
  }
  invisible(reg$generation)
}

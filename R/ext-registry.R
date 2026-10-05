# ext-registry.R -- the registry keyed by (kind, name) with ranks, filters, diagnostics and a
# generation counter (contract 5.5, 7.2, 10.1; architecture 5.10, 11.1). Adapted from the verified
# G1 prototype (report G1 5.1) with its verification-log fixes: every regex on a registration or
# dispatch path uses perl = TRUE (row 9), overrides are per record (IC-69), filters are applied at
# resolution time (G1 pitfall 8), and no binding is ever locked (IC-26, rule R5).

#' A fresh registry environment holding all P02 state (contract 5.13 `gptr_registry_env`)
#'
#' `recs` maps record ids to records (contract 5.5); `by_kind`, `by_key` and `hooks` index them;
#' `exts` holds one environment per loaded extension and `states` the `gptr$state` environments;
#' `runs` and `executing` mirror the active runs and executing tools seen through ev_dispatch();
#' `grants` holds one-shot approvals of control exports (IC-53); `builtins_loaded` names the
#' built-ins already loaded into this registry and `watched` the packages whose unload is watched;
#' `version` counts changes that can alter gptr_registry() and `listing` caches its full listing.
#' `deferred` queues the events that GC-time session finalizers defer (ev_defer()), keyed by
#' `deferred_seq`; `busy` counts the registry work in progress and `draining` marks a running
#' ev_drain(), which only starts when no registry work is in progress (D-085).
#' @noRd
registry_new = function() {
  reg = new.env(parent = emptyenv())
  reg$recs = new.env(parent = emptyenv())
  reg$by_kind = new.env(parent = emptyenv())
  reg$by_key = new.env(parent = emptyenv())
  reg$hooks = new.env(parent = emptyenv())
  reg$exts = new.env(parent = emptyenv())
  reg$states = new.env(parent = emptyenv())
  reg$diag = new.env(parent = emptyenv())
  reg$diag$rows = list()
  reg$kinds = kinds_new()
  reg$filters = list(user = character(), project = character(), session = character())
  reg$eff = character()
  reg$runs = character()
  reg$executing = character()
  reg$grants = list()
  reg$builtins_loaded = character()
  reg$watched = character()
  reg$generation = 1L
  reg$seq = 0L
  reg$ext_seq = 0L
  reg$version = 0L
  reg$listing = NULL
  reg$listing_key = NULL
  reg$current_ext = NULL
  reg$ctx0 = NULL
  reg$deferred = new.env(parent = emptyenv())
  reg$deferred_seq = 0L
  reg$busy = 0L
  reg$draining = FALSE
  class(reg) = "gptr_registry_env"
  reg
}

#' Begin registry work (a lookup, a dispatch, a factory run): first drain the deferred events when
#' `drain` is TRUE and no other registry work is in progress, then count this work, so that no
#' drain runs under it. Pair with `on.exit(registry_leave(reg), add = TRUE)` (D-085)
#' @noRd
registry_enter = function(reg, drain = TRUE) {
  if (drain && length(reg$deferred)) ev_drain(reg)
  reg$busy = reg$busy + 1L
  invisible(reg)
}

#' End registry work begun by registry_enter()
#' @noRd
registry_leave = function(reg) {
  reg$busy = max(reg$busy - 1L, 0L)
  invisible(NULL)
}

#' Note a change that can alter gptr_registry() (records, filters, kinds); the cached listing
#' is rebuilt on its next call
#' @noRd
registry_touch = function(reg = registry_env()) {
  reg$version = reg$version + 1L
  invisible(NULL)
}

#' Make `reg` the process registry and point the P02 fields of `the` at it (contract 7.0)
#' @noRd
registry_bind = function(reg) {
  the$registry = reg
  the$kinds = reg$kinds
  the$hooks = reg$hooks
  the$diagnostics = reg$diag
  invisible(reg)
}

#' The process registry, created on first use
#' @noRd
registry_env = function() {
  reg = the$registry
  if (is.null(reg)) {
    reg = registry_new()
    registry_bind(reg)
  }
  reg
}

#' A scratch registry holding only the built-in kinds (gptr_check() and tests)
#' @noRd
registry_scratch = function() registry_new()

#' Swap the process registry; returns the previous one invisibly
#' @noRd
registry_swap = function(reg) {
  old = registry_env()
  registry_bind(reg)
  invisible(old)
}

#' The session id of a session object (anything with an `id` string), an id string, or NULL
#' @noRd
ext_session_id = function(session) {
  if (is.null(session)) return(NULL)
  if (is.character(session) && length(session) == 1L && !is.na(session)) return(session)
  if (!is.environment(session) && !is.list(session)) return(NULL)
  id = tryCatch(session$id, error = function(e) NULL)
  if (is.character(id) && length(id) == 1L && !is.na(id)) id else NULL
}

# ---- records (contract 5.5, 7.2, 10.1) ----------------------------------------------------------

#' Append an id to an index entry
#' @noRd
registry_index_push = function(env, key, id) {
  assign(key, c(get0(key, envir = env, inherits = FALSE), id), envir = env)
  invisible(NULL)
}

#' Drop an id from an index entry
#' @noRd
registry_index_drop = function(env, key, id) {
  ids = get0(key, envir = env, inherits = FALSE)
  if (is.null(ids)) return(invisible(NULL))
  ids = ids[ids != id]
  if (length(ids)) assign(key, ids, envir = env) else rm(list = key, envir = env)
  invisible(NULL)
}

#' Records for a vector of ids, skipping ids whose record is gone: callers pass a snapshot of an
#' index, and a record may be removed between that snapshot and this read (D-085)
#' @noRd
registry_recs = function(reg, ids) {
  if (!length(ids)) return(list())
  recs = mget(ids, envir = reg$recs, mode = "list", ifnotfound = list(NULL), inherits = FALSE)
  unname(recs[!vapply(recs, is.null, NA)])
}

#' Order records by rank, then registration
#' @noRd
registry_sort = function(recs) {
  if (length(recs) < 2L) return(recs)
  rank = vapply(recs, function(r) r$rank, 0L)
  ord = vapply(recs, function(r) r$order, 0L)
  recs[order(rank, ord)]
}

#' Is a record visible to a session (process records, or that session's own)?
#' @noRd
registry_visible = function(rec, sid) is.null(rec$session) || identical(rec$session, sid)

#' Registry key of a spec: tools with a namespace are "<namespace>/<name>" (contract 10.2)
#' @noRd
spec_key = function(spec) {
  ns = spec[["namespace"]]
  if (identical(spec[["kind"]], "tool") && is.character(ns) && length(ns) == 1L) {
    return(paste0(ns, "/", spec[["name"]]))
  }
  spec[["name"]]
}

#' Declaration cost of a spec in estimated tokens (the `tokens` column; report G1 4.8)
#' @noRd
spec_tokens = function(spec) {
  n = tryCatch({
    if (isTRUE(spec[["lazy"]])) {
      d = spec[["declaration"]]
      if (is.null(d)) 0 else est_tokens(paste(d$signature %||% "", d$description %||% ""), "code")
    } else if (identical(spec$kind, "tool")) {
      params = if (is.list(spec[["parameters"]])) spec[["parameters"]] else json_obj()
      if (identical(spec[["exposure"]], "direct")) {
        est_tokens(json_encode(list(name = spec$name, description = spec[["description"]],
                                    input_schema = params)), "json")
      } else if (identical(spec[["exposure"]], "r")) {
        ns = spec[["namespace"]]
        prefix = if (is.null(ns)) "gptr$" else paste0("gptr$", ns, "$")
        sig = spec[["signature"]] %||%
          schema_signature(spec$name, params, spec[["description"]], prefix = prefix)
        est_tokens(sig, "code")
      } else {
        0
      }
    } else if (identical(spec$kind, "prompt_section")) {
      text = spec[["text"]]
      if (is.character(text)) est_tokens(text, "prose") else as.numeric(spec[["budget"]])
    } else if (identical(spec$kind, "context_block")) {
      as.numeric(spec[["budget"]])
    } else if (identical(spec$kind, "skill")) {
      spec[["tokens"]] %||% est_tokens(paste(spec$name, spec[["description"]] %||% ""), "prose")
    } else {
      0
    }
  }, error = function(e) 0)
  as.numeric(n)
}

#' Member and namespace names reserved for built-ins and MCP (IC-37, contract 9.4)
#' @noRd
ext_reserved_members = c("read", "write", "edit", "grep", "find", "ls", "help", "search",
                         "describe", "plot", "out", "sh", "script", "bg", "jobs", "py", "sql",
                         "knit", "app", "mcp")

#' Names of un-namespaced, non-hidden tool records with a `fun` (the gptr$ members, IC-37)
#' @noRd
registry_member_names = function(reg) {
  recs = registry_recs(reg, get0("tool", envir = reg$by_kind, inherits = FALSE))
  keep = vapply(recs, function(r) {
    s = r$spec
    is.null(s[["namespace"]]) && is.function(s[["fun"]]) && !identical(s[["exposure"]], "hidden")
  }, NA)
  unique(vapply(recs[keep], function(r) r$name, ""))
}

#' Source- and rank-dependent registration rules (IC-37, IC-52)
#' @noRd
registry_admit = function(spec, source, rank, reg) {
  operator = identical(spec[["kind"]], "context_block") &&
    identical(spec[["authority"]], "operator")
  if (operator && rank < 3L) {
    spec_abort(spec, "authority",
               paste0("'operator' is accepted only from records of rank 3 or more (user, ",
                      "plugin, built-in); this record has rank ", rank))
  }
  if (identical(spec$kind, "tool")) {
    ns = spec[["namespace"]]
    if (startsWith(source, "plugin:") && identical(spec[["exposure"]], "r") && is.null(ns)) {
      spec_abort(spec, "namespace", "is required for plugin members with exposure 'r'")
    }
    if (!is.null(ns)) {
      if (ns %in% ext_reserved_members) spec_abort(spec, "namespace", "is a reserved member name")
      if (ns %in% registry_member_names(reg)) {
        spec_abort(spec, "namespace", "equals an existing gptr$ member name")
      }
    }
  }
  invisible(TRUE)
}

#' Record a collision diagnostic for a tie at the same rank (contract 10.1)
#' @noRd
registry_collision = function(rec, reg) {
  if (identical(rec$state, "lazy")) return(invisible(NULL))
  k = kind_get(rec$kind)
  if (!identical(k$resolve, "first")) return(invisible(NULL))
  ids = get0(paste(rec$kind, rec$name, sep = "\r"), envir = reg$by_key, inherits = FALSE)
  for (other in registry_recs(reg, setdiff(ids, rec$id))) {
    tie = identical(other$rank, rec$rank) && identical(other$session, rec$session) &&
      !identical(other$source, rec$source) && !identical(other$state, "lazy")
    if (tie) {
      registry_diagnostic(rec$source, "register", "collision",
                          paste0(rec$kind, " '", rec$name, "' from ", rec$source, " ties with ",
                                 other$source, " at rank ", rec$rank,
                                 "; the first registered record wins"))
      break
    }
  }
  invisible(NULL)
}

#' Check a registry source string (contract 10.1): session, project, user, builtin:<name> or
#' plugin:<name>
#' @noRd
registry_check_source = function(source) {
  check_string(source, "source")
  if (!grepl("\\A(session|project|user|builtin:[^\\r\\n]+|plugin:[^\\r\\n]+)\\z",
             source, perl = TRUE)) {
    gptr_abort("`source` must be session, project, user, builtin:<name> or plugin:<name>.",
               "invalid_argument", arg = "source", expected = "a registry source string")
  }
  invisible(source)
}

#' Store a validated spec as a registry record; returns its id (contract 7.2). Lazy placeholders
#' (state "lazy", made by ext_load()) are stored unvalidated and may name a kind that their
#' factory defines on activation.
#' @noRd
registry_add = function(spec, source, rank, session = NULL, state = "active") {
  check_class(spec, "gptr_spec", "spec")
  registry_check_source(source)
  rank = check_number(rank, "rank", min = 0, max = 99, int = TRUE)
  state = check_choice(state, c("active", "lazy"), "state")
  reg = registry_env()
  rank = as.integer(rank)
  sid = ext_session_id(session)
  if (identical(source, "session") || !is.null(session)) {
    check_string(sid, "session")
  }
  if (identical(state, "active")) {
    spec = spec_finish(unclass(spec), kind_get(spec$kind))
    registry_admit(spec, source, rank, reg)
  }
  key = spec_key(spec)
  reg$seq = reg$seq + 1L
  id = paste0("r", reg$seq)
  if (identical(spec$kind, "kind") && identical(state, "active")) kind_from_spec(spec, source, id)
  rec = list(id = id, kind = spec$kind, name = key, spec = spec, rank = rank, source = source,
             state = state, generation = reg$generation, tokens = spec_tokens(spec),
             session = sid, order = reg$seq, ext = reg$current_ext)
  assign(id, rec, envir = reg$recs)
  registry_index_push(reg$by_kind, spec$kind, id)
  registry_index_push(reg$by_key, paste(spec$kind, key, sep = "\r"), id)
  if (identical(spec$kind, "hook")) registry_index_push(reg$hooks, spec[["event"]] %||% key, id)
  registry_touch(reg)
  registry_collision(rec, reg)
  id
}

#' Remove one record (contract 7.2)
#' @noRd
registry_remove = function(id) {
  reg = registry_env()
  rec = get0(id, envir = reg$recs, inherits = FALSE)
  if (is.null(rec)) return(invisible(FALSE))
  rm(list = id, envir = reg$recs)
  registry_index_drop(reg$by_kind, rec$kind, id)
  registry_index_drop(reg$by_key, paste(rec$kind, rec$name, sep = "\r"), id)
  if (identical(rec$kind, "hook")) {
    registry_index_drop(reg$hooks, rec$spec[["event"]] %||% rec$name, id)
  }
  if (identical(rec$kind, "kind")) kind_undefine(rec$spec[["name"]], id)
  registry_touch(reg)
  invisible(TRUE)
}

#' Enabled records of (kind, key) visible to a session, winner first
#' @noRd
registry_candidates = function(kind, key, sid, reg = registry_env()) {
  ids = get0(paste(kind, key, sep = "\r"), envir = reg$by_key, inherits = FALSE)
  recs = registry_recs(reg, ids)
  recs = recs[vapply(recs, function(r) registry_visible(r, sid) && !registry_rec_filtered(r, reg),
                     NA)]
  registry_sort(recs)
}

#' The winning spec for (kind, name) or NULL; a lazy winner is activated first (contract 7.2)
#' @noRd
registry_get = function(kind, name, session = NULL) {
  check_string(kind, "kind")
  check_string(name, "name")
  sid = ext_session_id(session)
  reg = registry_env()
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  for (attempt in seq_len(10L)) {
    recs = registry_candidates(kind, name, sid, reg)
    if (!length(recs)) return(NULL)
    win = recs[[1]]
    if (!identical(win$state, "lazy")) return(win$spec)
    ext_activate_record(win)
  }
  NULL
}

#' Specs of a kind: every record of an `all` kind, ordered; the winner per name otherwise. Lazy
#' records are activated first, except `tool` placeholders, whose manifest declarations feed the
#' frozen prompt's catalogs before activation (contract 10.8)
#' @noRd
registry_all = function(kind, session = NULL) {
  check_string(kind, "kind")
  sid = ext_session_id(session)
  reg = registry_env()
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  k = kind_get(kind)
  pick = function() {
    recs = registry_recs(reg, get0(kind, envir = reg$by_kind, inherits = FALSE))
    recs[vapply(recs, function(r) registry_visible(r, sid) && !registry_rec_filtered(r, reg),
                NA)]
  }
  recs = pick()
  if (!identical(kind, "tool")) {
    lazy = recs[vapply(recs, function(r) identical(r$state, "lazy"), NA)]
    if (length(lazy)) {
      for (r in lazy) ext_activate_record(r)
      recs = pick()
      recs = recs[!vapply(recs, function(r) identical(r$state, "lazy"), NA)]
    }
  }
  if (identical(k$resolve, "all")) {
    recs = registry_sort(recs)
    of = k$order_field
    if (!is.null(of) && length(recs) > 1L) {
      o = vapply(recs, function(r) as.numeric(r$spec[[of]] %||% 500), 0)
      recs = recs[order(o, seq_along(recs))]
    }
  } else {
    recs = registry_sort(recs)
    keys = vapply(recs, function(r) r$name, "")
    recs = recs[!duplicated(keys)]
    recs = recs[order(vapply(recs, function(r) r$name, ""), method = "radix")]
  }
  specs = lapply(recs, function(r) r$spec)
  names(specs) = vapply(recs, function(r) r$name, "")
  specs
}

#' Names with an enabled record, lazy placeholders included (contract 7.2)
#' @noRd
registry_names = function(kind, session = NULL) {
  check_string(kind, "kind")
  sid = ext_session_id(session)
  reg = registry_env()
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  recs = registry_recs(reg, get0(kind, envir = reg$by_kind, inherits = FALSE))
  recs = recs[vapply(recs, function(r) registry_visible(r, sid) && !registry_rec_filtered(r, reg),
                     NA)]
  unique(vapply(recs, function(r) r$name, ""))
}

#' The registry generation (bumped by gptr_reload())
#' @noRd
registry_generation = function() registry_env()$generation

#' Append a redacted diagnostic row (contract 7.2); keeps the last 1,000 rows
#' @noRd
registry_diagnostic = function(source, event, class, message) {
  reg = registry_env()
  row = list(time = Sys.time(), source = as.character(source)[1],
             event = as.character(event)[1], class = as.character(class)[1],
             message = redact_hook(paste(as.character(message), collapse = " "), "persist"))
  rows = reg$diag$rows
  rows[[length(rows) + 1L]] = row
  if (length(rows) > 1000L) rows = rows[seq.int(length(rows) - 999L, length(rows))]
  reg$diag$rows = rows
  invisible(NULL)
}

#' Forget an extension record: its API objects turn stale, its factory (and every frame the
#' factory closes over) is released, and a per-load `gptr$state` goes with it (rule R10). Plugin
#' and built-in state, keyed by source, lives for the process (contract 10.5)
#' @noRd
ext_forget = function(info, reg = registry_env()) {
  info$unloaded = TRUE
  info$factory = NULL
  info$stage = list()
  for (env in list(reg$exts, reg$states)) {
    if (exists(info$id, envir = env, inherits = FALSE)) rm(list = info$id, envir = env)
  }
  invisible(NULL)
}

#' Drop a session's records and forget its extensions (at its session_shutdown; IC-69)
#' @noRd
registry_session_drop = function(sid) {
  if (is.null(sid)) return(invisible(NULL))
  check_string(sid, "session")
  reg = registry_env()
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  for (id in ls(reg$recs)) {
    rec = get0(id, envir = reg$recs, inherits = FALSE)
    if (!is.null(rec) && identical(rec$session, sid)) registry_remove(id)
  }
  for (eid in ls(reg$exts)) {
    info = get0(eid, envir = reg$exts, inherits = FALSE)
    if (!is.null(info) && identical(info$session, sid)) {
      info$status = "unloaded"
      ext_forget(info, reg)
    }
  }
  invisible(NULL)
}

# ---- control exports (IC-53 point 3) ------------------------------------------------------------

#' Refuse a gptr configuration export called from model code during a run (IC-53)
#'
#' A tool is executing when ev_dispatch() has seen its tool_execution_start and not yet its
#' tool_execution_end (or its run's agent_end). Inside a tool, the call passes only with a
#' one-shot grant recorded by ext_control_grant() after an ask_human approval; an unused grant
#' ends with the top-level call it was granted in (ev_track(), Task 8).
#' @noRd
ext_control_guard = function(what) {
  reg = registry_env()
  if (!length(reg$executing)) return(invisible(TRUE))
  runs = unique(unname(reg$executing))
  for (i in seq_along(reg$grants)) {
    g = reg$grants[[i]]
    if (identical(g$what, what) && g$run %in% runs) {
      reg$grants = reg$grants[-i]
      return(invisible(TRUE))
    }
  }
  gptr_abort(paste0(what, "() changes gptr's configuration and cannot be called from model code ",
                    "while a run executes a tool, unless the user approved that call."),
             "permission", action = what, tool = "r", risk = 4L,
             how_to_allow = paste0("run ", what, "() yourself at the R console"), session = NULL)
}

#' Record a one-shot approval of `what` (an export name) for a run (called after ask_human)
#' @noRd
ext_control_grant = function(run, what) {
  check_string(run, "run")
  check_string(what, "what")
  reg = registry_env()
  reg$grants[[length(reg$grants) + 1L]] = list(run = run, what = what)
  invisible(TRUE)
}

# ---- exported registration and listing ----------------------------------------------------------

#' The unregister closure returned by gptr_register(). Removing a record reconfigures gptr as much
#' as adding one, and users keep this closure in the environment model code evaluates in
#' (`off = gptr_register(gptr_policy(...))`), so it passes the same IC-53 guard
#' @noRd
registry_unregister_fn = function(id) {
  force(id)
  reg = registry_env()
  function() {
    ext_control_guard("gptr_register")
    if (!identical(registry_env(), reg)) return(invisible(FALSE))
    invisible(registry_remove(id))
  }
}

#' Register a capability spec
#'
#' Registers a spec made by [gptr_spec()] or one of the spec constructors at top level: rank 3,
#' source `"user"`, for the lifetime of the R process. Sessions frozen before the call are not
#' changed; the next session sees the record. A user record overrides a built-in record of the same
#' kind and name only (the built-in's other records keep working).
#'
#' Called from model code while a run executes a tool, `gptr_register()` and the function it
#' returns signal `gptr_error_permission` unless the user approved that call.
#'
#' @param spec A spec (class `gptr_spec`).
#' @return A function that removes the record again, invisibly.
#' @examples
#' off = gptr_register(gptr_command("hello", function(args, ctx) "hi"))
#' off()
#' @export
gptr_register = function(spec) {
  check_class(spec, "gptr_spec", "spec")
  ext_control_guard("gptr_register")
  id = registry_add(spec, source = "user", rank = 3L)
  invisible(registry_unregister_fn(id))
}

#' State of a record for listings: lazy, disabled, overridden or active
#' @noRd
registry_rec_state = function(rec, reg) {
  if (identical(rec$state, "lazy")) return("lazy")
  if (registry_rec_filtered(rec, reg)) return("disabled")
  k = kind_get(rec$kind)
  if (identical(k$resolve, "first")) {
    win = registry_candidates(rec$kind, rec$name, rec$session, reg)
    if (length(win) && !identical(win[[1]]$id, rec$id)) return("overridden")
  }
  "active"
}

#' List the extension registry
#'
#' One row per process-level record (session-scoped records are not listed): its kind, name,
#' source (`builtin:<name>`, `plugin:<name>`, `user`, `project`), rank, state (`lazy`, `active`,
#' `overridden`, `disabled`), the estimated tokens its declaration costs, and whether the kind is
#' experimental. With `diagnostics = TRUE`, the redacted diagnostics log instead.
#'
#' @param kind `NULL` for every kind, or a character vector of kind names.
#' @param diagnostics `TRUE` to return the diagnostics log.
#' @return A `gptr_registry` data frame (columns `kind`, `name`, `source`, `rank`, `state`,
#'   `tokens`, `experimental`), or a `gptr_diagnostics` data frame (columns `time`, `source`,
#'   `event`, `class`, `message`).
#' @examples
#' gptr_registry("tool")
#' gptr_registry(diagnostics = TRUE)
#' @export
gptr_registry = function(kind = NULL, diagnostics = FALSE) {
  check_strings(kind, "kind", null = TRUE)
  check_flag(diagnostics, "diagnostics")
  reg = registry_env()
  if (diagnostics) return(registry_diag_df(reg))
  registry_enter(reg)
  on.exit(registry_leave(reg), add = TRUE)
  key = list(reg$version, registry_protected_builtins())
  if (is.null(kind) && identical(reg$listing_key, key)) return(reg$listing)
  kinds = kind %||% kind_names()
  rows = list()
  for (k in kinds) {
    def = kind_get(k)
    recs = registry_recs(reg, get0(k, envir = reg$by_kind, inherits = FALSE))
    recs = recs[vapply(recs, function(r) is.null(r$session), NA)]
    for (r in recs) {
      rows[[length(rows) + 1L]] = list(kind = k, name = r$name, source = r$source,
                                       rank = r$rank, state = registry_rec_state(r, reg),
                                       tokens = r$tokens, experimental = isTRUE(def$experimental))
    }
  }
  col = function(f, type) if (length(rows)) vapply(rows, function(r) r[[f]], type) else type[0]
  df = data.frame(kind = col("kind", ""), name = col("name", ""), source = col("source", ""),
                  rank = col("rank", 0L), state = col("state", ""), tokens = col("tokens", 0),
                  experimental = col("experimental", NA), stringsAsFactors = FALSE)
  out = structure(df, class = c("gptr_registry", "data.frame"))
  if (is.null(kind)) {
    reg$listing = out
    reg$listing_key = key
  }
  out
}

#' The diagnostics log as a data frame
#' @noRd
registry_diag_df = function(reg) {
  rows = reg$diag$rows
  col = function(f) if (length(rows)) vapply(rows, function(r) r[[f]], "") else character()
  time = if (length(rows)) do.call(c, lapply(rows, function(r) r$time)) else Sys.time()[0]
  df = data.frame(time = time, source = col("source"), event = col("event"),
                  class = col("class"), message = col("message"), stringsAsFactors = FALSE)
  structure(df, class = c("gptr_diagnostics", "data.frame"))
}

#' Print a registry listing
#' @export
#' @noRd
print.gptr_registry = function(x, ...) {
  cat("<gptr_registry> ", nrow(x), " record(s)\n", sep = "")
  if (nrow(x)) print(structure(x, class = "data.frame"), row.names = FALSE)
  invisible(x)
}

#' Print the diagnostics log
#' @export
#' @noRd
print.gptr_diagnostics = function(x, ...) {
  cat("<gptr_diagnostics> ", nrow(x), " row(s)\n", sep = "")
  if (nrow(x)) print(structure(x, class = "data.frame"), row.names = FALSE)
  invisible(x)
}

# ---- filter state read at resolution time (contract 10.1; IC-53) --------------------------------

#' Built-ins that no filter may disable: the permission kernel, secrets, and every built-in
#' declared with replaceable = FALSE (IC-53, contract 7.2 ext_declare_builtin)
#' @noRd
registry_protected_builtins = function() {
  b = the$builtins %||% list()
  fixed = vapply(b, function(x) isFALSE(x$replaceable), NA)
  unique(c("permissions", "plan", "secrets", names(b)[fixed]))
}

#' Records of these sources are immune to every filter (IC-53)
#' @noRd
registry_source_protected = function(source) {
  source %in% c("builtin:permissions", "builtin:plan", "builtin:secrets")
}

#' Is a record disabled by the effective filters (by default the registry's own)?
#' @noRd
registry_rec_filtered = function(rec, reg = registry_env(), eff = reg$eff) {
  if (!length(eff)) return(FALSE)
  src = rec$source
  if (registry_source_protected(src)) return(FALSE)
  keys = paste0(rec$kind, ":", rec$name)
  if (startsWith(src, "plugin:")) keys = c(keys, src)
  if (startsWith(src, "builtin:") && !(substring(src, 9L) %in% registry_protected_builtins())) {
    keys = c(keys, src)
  }
  hit = eff[names(eff) %in% keys]
  if (!length(hit)) return(FALSE)
  kept_from_project = identical(src, "user") || startsWith(src, "builtin:")
  if (rec$kind %in% c("policy", "hook") && kept_from_project) hit = hit[hit != "project"]
  length(hit) > 0L
}

# ---- setting filters (contract 7.2 registry_filters_set, 10.1; IC-53) ---------------------------

#' The form of a filter string: a sign, a prefix (builtin, plugin or a kind) and a name
#' @noRd
registry_filter_rx = "\\A[+-][a-z][a-z0-9_]*:[^[:space:]]+\\z"

#' The effective filters: names are filter keys, values the scope that set them. Scopes apply in
#' the order user, project, session; "+key" removes a key set by an earlier scope
#' @noRd
registry_filters_effective = function(filters) {
  eff = character()
  for (scope in c("user", "project", "session")) {
    for (f in filters[[scope]]) {
      key = substring(f, 2L)
      if (!startsWith(f, "-")) {
        eff = eff[names(eff) != key]
      } else if (!(key %in% names(eff)) || identical(eff[[key]], "project")) {
        eff[key] = scope
      }
    }
  }
  eff
}

#' Is a whole source (builtin:<name>, plugin:<name>) disabled by a filter?
#' @noRd
registry_source_filtered = function(source, reg = registry_env()) {
  if (registry_source_protected(source)) return(FALSE)
  if (startsWith(source, "builtin:") && substring(source, 9L) %in% registry_protected_builtins()) {
    return(FALSE)
  }
  source %in% names(reg$eff)
}

#' Does a filter key match an enabled policy or hook record?
#' @noRd
registry_filter_hits_policy = function(key, reg) {
  for (k in c("policy", "hook")) {
    for (r in registry_recs(reg, get0(k, envir = reg$by_kind, inherits = FALSE))) {
      if (registry_source_protected(r$source) || registry_rec_filtered(r, reg)) next
      if (identical(key, paste0(r$kind, ":", r$name)) || identical(key, r$source)) return(TRUE)
    }
  }
  FALSE
}

#' Would the effective filters `eff` disable a policy or hook record that is enabled now?
#' @noRd
registry_drops_guard = function(reg, eff) {
  for (k in c("policy", "hook")) {
    for (r in registry_recs(reg, get0(k, envir = reg$by_kind, inherits = FALSE))) {
      if (!registry_rec_filtered(r, reg) && registry_rec_filtered(r, reg, eff)) return(TRUE)
    }
  }
  FALSE
}

#' Why a filter is refused, or NULL (IC-53)
#' @noRd
registry_filter_refusal = function(f, reg) {
  if (!startsWith(f, "-")) return(NULL)
  key = substring(f, 2L)
  protected = c(paste0("builtin:", registry_protected_builtins()), "policy:critical_guard",
                "policy:secret_guard")
  if (key %in% protected) {
    return("the permission kernel and non-replaceable built-ins cannot be disabled by filters")
  }
  if (length(reg$runs) && registry_filter_hits_policy(key, reg)) {
    return("filters that remove policy or hook records are refused while a run is active")
  }
  NULL
}

#' Set the filters of one scope (contract 7.2; IC-53). Returns the effective filter keys
#' invisibly, with attribute "refused" naming the refused filters
#' @noRd
registry_filters_set = function(filters, scope = c("session", "user", "project")) {
  check_strings(filters, "filters")
  scope = check_choice(scope, c("session", "user", "project"), "scope")
  reg = registry_env()
  ok_form = grepl(registry_filter_rx, filters, perl = TRUE)
  if (!all(ok_form)) {
    gptr_abort(paste0("Invalid filter; use -builtin:<name>, -plugin:<name> or -<kind>:<name>, ",
                      "and a leading + to undo one."),
               "invalid_argument", arg = "filters",
               expected = "filters of the form -builtin:<name>, -plugin:<name>, -<kind>:<name>")
  }
  # A kind that a lazy plugin defines on activation does not exist yet when the settings layer
  # applies the user's filters: keep the filter (it applies once the kind exists) and note it
  prefix = sub("^[+-]([a-z][a-z0-9_]*):.*$", "\\1", filters, perl = TRUE)
  for (f in filters[!(prefix %in% c("builtin", "plugin", kind_names()))]) {
    registry_diagnostic(paste0("filters:", scope), "filter", "filter_unknown_kind",
                        paste0(f, " names a kind that is not registered (yet)"))
  }
  keep = character()
  refused = character()
  for (f in filters) {
    why = registry_filter_refusal(f, reg)
    if (is.null(why)) {
      keep = c(keep, f)
    } else {
      refused = c(refused, f)
      registry_diagnostic(paste0("filters:", scope), "filter", "filter_refused",
                          paste0(f, " refused: ", why))
    }
  }
  if (identical(scope, "project")) {
    for (f in keep[startsWith(keep, "-")]) {
      if (registry_filter_hits_policy(substring(f, 2L), reg)) {
        registry_diagnostic("filters:project", "filter", "filter_limited",
                            paste0(f, " does not apply to user or built-in policy and hook ",
                                   "records"))
      }
    }
  }
  if (length(reg$runs)) {
    old = reg$filters[[scope]]
    dropped = setdiff(old[startsWith(old, "+")], keep)
    retained = character()
    for (f in dropped) {
      trial = reg$filters
      trial[[scope]] = c(keep, setdiff(dropped, f))
      if (registry_drops_guard(reg, registry_filters_effective(trial))) {
        retained = c(retained, f)
        registry_diagnostic(paste0("filters:", scope), "filter", "filter_refused",
                            paste0("dropping ", f, " refused: it keeps a policy or hook record ",
                                   "enabled while a run is active"))
      }
    }
    keep = c(keep, retained)
    refused = c(refused, retained)
  }
  reg$filters[[scope]] = keep
  reg$eff = registry_filters_effective(reg$filters)
  registry_touch(reg)
  if (any(startsWith(keep, "+builtin:")) && length(the$builtins)) ext_load_builtins()
  out = names(reg$eff) %||% character()
  attr(out, "refused") = refused
  invisible(out)
}

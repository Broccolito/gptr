# gptr-config.R -- settings files and layers, gptr_config(), gptr_init(), gptr_trust(), the egress
# acknowledgement, replay_mode() and replay_guard() (plan P08; contract sections 6.2, 7.8,
# 11.1-11.3, 11.8, 11.16; IC-45, IC-52, IC-53, IC-71, IC-74). Layer L6: it calls L0-L3 functions,
# the kernel SDK and services only.

# ------------------------------------------------------------------ P08 state in `the`

#' P08's process state (`the$gateway`, see the plan's contract ambiguities): parsed settings
#' files, trust decisions taken in this process (with the fingerprint they were taken for),
#' trust fingerprints, the gateway_defer() depth, the pending run options of sessions built with
#' `.run = FALSE`, the call records held for them and the ids of the rank-0 records each session's
#' calls registered (all three keyed by session id; released by builtin:gateway's agent_end and
#' session_shutdown hooks, Task 9)
#' @noRd
gateway_state = function() {
  st = the$gateway
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$files = new.env(parent = emptyenv())
    st$trust = new.env(parent = emptyenv())
    st$fingerprints = new.env(parent = emptyenv())
    st$pending = new.env(parent = emptyenv())
    st$held = new.env(parent = emptyenv())
    st$specs = new.env(parent = emptyenv())
    st$defer = 0L
    the$gateway = st
  }
  st
}

# ------------------------------------------------------------------ core settings (contract 11.2)

#' The core settings of contract section 11.2 as plain records
#' @noRd
settings_core = function() {
  modes = c("plan", "manual", "edits", "auto")
  rec = function(name, default, type, description, choices = NULL, tighten = NULL,
                 scope = "both") {
    list(name = name, default = default, type = type, description = description,
         choices = choices, tighten = tighten, scope = scope)
  }
  list(
    rec("version", 1L, "int", "Settings file format version."),
    rec("model", NULL, "ident", "Default model reference (null: the first available route)."),
    rec("small_model", NULL, "ident", "Small model (null: the small sibling of model)."),
    rec("system1", NULL, "ident", "System 1 model (null: typesafe/jev-latest when a key exists)."),
    rec("mode", "manual", "choice", "Permission mode.", choices = modes, tighten = modes),
    rec("preset", "standard", "chr", "Tool and prompt preset."),
    rec("tools", json_obj(), "object", "Tool enable and disable lists and per-model presets."),
    rec("permissions", json_obj(), "object", "Permission rules: allow, ask, deny."),
    rec("context", "summary", "choice", "Automatic context sent with prompts.",
        choices = c("none", "names", "summary"), tighten = c("none", "names", "summary")),
    rec("record", "ask", "choice", "May gptr write recorded blocks into documents.",
        choices = c("off", "ask", "auto"), tighten = c("off", "ask", "auto")),
    rec("replay", "auto", "choice", "Document replay mode.",
        choices = c("auto", "replay", "live", "record")),
    rec("transcript", "ask", "choice", "Console transcript target.",
        choices = c("ask", "file", "active-document", "off")),
    rec("plugins", character(), "chrs", "Plugins enabled for every session."),
    rec("filters", character(), "chrs", "Registry filters such as -builtin:mcp."),
    rec("skills", list(budget = 1500L), "object", "Skill paths and catalog budget."),
    rec("mcp", list(exposure = "r", budget = 1500L,
                    import = c("claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi")),
        "object", "MCP exposure, catalog budget and imported configurations."),
    rec("subagents", list(max_depth = 1L, max_active = 8L, max_workers = NULL, max_cli = 4L,
                          max_tasks = 8L), "object", "Sub-agent limits."),
    rec("output_tokens", NULL, "int_or_null", "Maximum output tokens per request."),
    rec("plot", list(width = 768L, height = 512L, res = 120L), "object",
        "Size of plots sent to the model."),
    rec("budget", list(tokens = 2000000, cost = 5, turns = NULL), "object",
        "Budget per top-level call; null disables a limit."),
    rec("cache", list(ttl = "gap"), "object", "Prompt-cache tail TTL policy."),
    rec("compactor", "checkpoint", "chr", "Compactor used at the threshold."),
    rec("compact_at", 200000, "num_or_null", "Compaction soft cap in tokens."),
    rec("checkpoint", "on", "choice", "Checkpoints for undo.", choices = c("on", "files", "off")),
    rec("doc", list(outputs = TRUE, output_lines = 12L), "object", "Recorded output lines."),
    rec("cache_commit", list(s1 = TRUE, s2 = FALSE), "object", "Which caches are committed."),
    rec("ui", NULL, "chr_or_null", "UI backend name."),
    rec("frontend", NULL, "chr_or_null", "Console front end name."),
    rec("store", "jsonl", "chr", "Session store."),
    rec("evaluator", "r", "chr", "R evaluator."),
    rec("providers", json_obj(), "providers",
        "Provider overrides: base_url, models, headers, enabled, local_only."),
    rec("egress", json_obj(), "object", "Providers acknowledged for automatic context.",
        scope = "user"))
}

#' A validator for one core setting (the `validate` field of its `setting` spec)
#' @noRd
setting_validator = function(name, type, choices = NULL) {
  force(name)
  force(type)
  force(choices)
  function(value) {
    switch(type,
      int = as.integer(check_number(value, name, min = 0, int = TRUE)),
      int_or_null = if (is.null(value)) NULL else
        as.integer(check_number(value, name, min = 0, int = TRUE)),
      num_or_null = if (is.null(value)) NULL else check_number(value, name, min = 0),
      chr = check_string(value, name),
      chr_or_null = check_string(value, name, null = TRUE),
      ident = check_string(value, name, null = TRUE),
      choice = check_choice(value, choices, name),
      chrs = as.character(check_strings(value, name)),
      object = settings_check_object(value, name),
      providers = settings_check_providers(value, name),
      value)
  }
}

#' Checks that a setting value is a JSON object (a named list, possibly empty)
#' @noRd
settings_check_object = function(value, name) {
  ok = is.list(value) && !is.object(value) &&
    (length(value) == 0L || (!is.null(names(value)) && all(nzchar(names(value)))))
  if (!ok) {
    gptr_abort(paste0("The setting `", name, "` takes a named list (a JSON object)."),
               "invalid_argument", arg = name, expected = "a named list")
  }
  value
}

#' Checks the `providers` setting: an object of provider objects in which `local_only`, when
#' given, is TRUE or FALSE (07-local-ollama.md section 5: `providers$ollama$local_only` is a
#' scalar non-NA logical; a missing value means TRUE, the stricter policy)
#' @noRd
settings_check_providers = function(value, name) {
  settings_check_object(value, name)
  for (id in names(value)) {
    arg = paste0(name, ".", id)
    entry = settings_check_object(value[[id]], arg)
    check_flag(entry[["local_only"]], paste0(arg, ".local_only"), null = TRUE)
  }
  value
}

#' The `setting` specs of the core keys, registered by builtin:gateway (IC-24)
#' @noRd
gateway_setting_specs = function() {
  lapply(settings_core(), function(x) {
    gptr_spec("setting", x$name, default = x$default, description = x$description,
              scope = x$scope, validate = setting_validator(x$name, x$type, x$choices),
              tighten = x$tighten)
  })
}

#' The spec of a setting: the registered record, else the core table entry, else NULL
#' @noRd
settings_spec = function(key) {
  sp = registry_get("setting", key)
  if (!is.null(sp)) return(sp)
  for (x in settings_core()) {
    if (identical(x$name, key)) {
      return(list(name = x$name, default = x$default, scope = x$scope, tighten = x$tighten,
                  validate = setting_validator(x$name, x$type, x$choices)))
    }
  }
  NULL
}

#' Every known setting name (core keys plus registered `setting` specs)
#' @noRd
settings_keys = function() {
  core = vapply(settings_core(), function(x) x$name, "")
  unique(c(core, registry_names("setting")))
}

# ------------------------------------------------------------------ settings files

#' Path of a scope's settings file. `user_project` is the user-level project file of IC-52
#' (`R_user_dir("gptr", "config")/projects/<16 hex>.json`), which gptr_permissions(scope =
#' "project") writes (P11)
#' @noRd
settings_path = function(scope, create = FALSE) {
  switch(scope,
    user = file.path(gptr_user_dir("config", create = create), "settings.json"),
    project = {
      ws = workspace_dir()
      if (is.null(ws)) {
        gptr_abort(c("No gptr workspace (.gptr/) exists in this project.",
                     "Create one with gptr_init(path)."), "workspace", path = project_root())
      }
      file.path(ws, "settings.json")
    },
    user_project = file.path(gptr_user_dir("config", create = create), "projects",
                             paste0(project_hash(project_root()), ".json")),
    gptr_abort(paste0("Unknown settings scope `", scope, "`."), "invalid_argument",
               arg = "scope", expected = "session, project, user or user_project"))
}

#' First 16 hex of sha256 of the path key of a project root (IC-52)
#' @noRd
project_hash = function(root) substr(hash_sha256(path_key(root)), 1L, 16L)

#' Unnamed JSON arrays of scalars become atomic vectors; objects stay named lists
#' @noRd
json_simplify = function(x) {
  if (!is.list(x) || !length(x)) return(x)
  if (is.null(names(x))) {
    scalar = vapply(x, function(e) is.atomic(e) && length(e) == 1L, NA)
    if (all(scalar) && length(unique(vapply(x, typeof, ""))) == 1L) {
      return(unlist(x, use.names = FALSE))
    }
  }
  lapply(x, json_simplify)
}

#' Reads a JSON settings file through a cache keyed by path, mtime and size
#' @noRd
settings_file_read = function(path, fresh = FALSE) {
  if (!file.exists(path)) return(list())
  st = gateway_state()
  info = file.info(path, extra_cols = FALSE)
  stamp = paste(format(as.numeric(info$mtime), digits = 15), info$size)
  hit = if (isTRUE(fresh)) NULL else get0(path, envir = st$files, inherits = FALSE)
  if (!is.null(hit) && identical(hit$stamp, stamp)) return(hit$value)
  value = settings_parse(path)
  assign(path, list(stamp = stamp, value = value), envir = st$files)
  value
}

#' Parses one settings file for the layered reads; a malformed file is a diagnostic and reads as
#' empty
#' @noRd
settings_parse = function(path) json_simplify(settings_decode(path))

#' Decodes one settings file into its unsimplified JSON object (`json_decode()`), which
#' json_encode() writes back with the same JSON types. A blank file is the empty object. Text that
#' is not a JSON object is, when `strict` (writers), `gptr_error_workspace` so that a
#' read-modify-write never replaces a file it could not read; otherwise a diagnostic and empty
#' @noRd
settings_decode = function(path, strict = FALSE) {
  txt = read_utf8(path)$text
  if (!nzchar(trimws(txt))) return(list())
  value = tryCatch(json_decode(txt), error = function(e) e)
  bad = if (inherits(value, "error")) {
    paste0("could not parse ", path, ": ", conditionMessage(value))
  } else if (!is.list(value) || is.null(names(value))) {
    paste0(path, " is not a JSON object")
  }
  if (is.null(bad)) return(value)
  if (isTRUE(strict)) {
    gptr_abort(c(paste0("The settings file ", path, " is not a JSON object, so gptr will not ",
                        "rewrite it."),
                 "Fix the file or remove it, then try again."), "workspace", path = path)
  }
  registry_diagnostic("builtin:gateway", "settings", "parse_error", bad)
  list()
}

#' Reads a settings file for a read-modify-write under its lock: the unsimplified object of
#' settings_decode(strict = TRUE), never the cache; a missing file is empty
#' @noRd
settings_file_load = function(path) {
  if (!file.exists(path)) return(list())
  settings_decode(path, strict = TRUE)
}

#' Keeps array-valued settings arrays at length 1 when written
#' @noRd
settings_arrays = function(x) {
  for (k in intersect(c("plugins", "filters"), names(x))) {
    if (!is.null(x[[k]])) x[[k]] = I(as.character(unlist(x[[k]])))
  }
  nested = list(permissions = c("allow", "ask", "deny"), skills = "paths",
                tools = c("enable", "disable"), mcp = "import")
  for (k in intersect(names(nested), names(x))) {
    if (!is.list(x[[k]])) next
    for (f in intersect(nested[[k]], names(x[[k]]))) {
      if (!is.null(x[[k]][[f]])) x[[k]][[f]] = I(as.character(unlist(x[[k]][[f]])))
    }
  }
  x
}

#' Writes a settings file atomically (UTF-8, LF, final newline) and drops its cache entry
#' @noRd
settings_file_write = function(path, value) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  text = if (length(value)) json_encode(settings_arrays(value), pretty = TRUE) else "{}"
  write_atomic(path, text)
  st = gateway_state()
  if (exists(path, envir = st$files, inherits = FALSE)) rm(list = path, envir = st$files)
  invisible(path)
}

#' Merges a patch at top level; a NULL value removes the key
#' @noRd
settings_merge_top = function(cur, patch) {
  for (k in names(patch)) {
    if (is.null(patch[[k]])) cur[[k]] = NULL else cur[k] = list(patch[[k]])
  }
  cur
}

# ------------------------------------------------------------------ short file locks (IC-71)

#' Takes a short `mkdir` lock next to `path` (pid + creation time; 50 x 100 ms retries)
#' @noRd
file_lock = function(path) {
  lock = paste0(path, ".lock")
  dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(50L)) {
    if (dir.create(lock, showWarnings = FALSE)) {
      write_atomic(file.path(lock, "pid"), lock_stamp())
      return(lock)
    }
    if (lock_stale(lock)) unlink(lock, recursive = TRUE) else Sys.sleep(0.1)
  }
  gptr_abort(paste0("The file ", path, " is locked by another R process; try again."),
             "timeout", seconds = 5, what = "lock")
}

#' Releases a lock taken by file_lock()
#' @noRd
file_unlock = function(lock) invisible(unlink(lock, recursive = TRUE))

#' "<pid> <process creation time>" of this process
#' @noRd
lock_stamp = function() {
  ct = tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle())), error = function(e) NA_real_)
  paste(Sys.getpid(), format(ct, digits = 15))
}

#' A lock is stale when its owner is dead (pid and creation time, P04's pid_alive()) or it has
#' had no pid file for 30 s. A lock directory or pid file that disappears while it is examined
#' belongs to an owner releasing the lock: not stale, the caller retries (breaking it then could
#' remove a lock another writer has just taken).
#' @noRd
lock_stale = function(lock) {
  if (!dir.exists(lock)) return(FALSE)
  pf = file.path(lock, "pid")
  if (!file.exists(pf)) {
    age = as.numeric(difftime(Sys.time(), file.info(lock)$mtime, units = "secs"))
    return(!is.na(age) && age > 30)
  }
  txt = tryCatch(read_utf8(pf)$text, error = function(e) NULL)
  if (is.null(txt)) return(FALSE)
  parts = strsplit(trimws(txt), " ", fixed = TRUE)[[1L]]
  pid = suppressWarnings(as.integer(parts[1L]))
  ct = suppressWarnings(as.numeric(parts[2L]))
  if (is.na(pid)) return(TRUE)
  !isTRUE(tryCatch(pid_alive(pid, create_time = if (is.na(ct)) NULL else ct),
                   error = function(e) FALSE))
}

# ------------------------------------------------------------------ settings I/O (contract 7.8)

#' The named list stored in one scope: `session` (this R process, `the$settings_session`),
#' `project` (.gptr/settings.json), `user`, `user_project` (IC-52). Read by P11 and P15.
#' @noRd
settings_read = function(scope) {
  scope = check_choice(scope, c("session", "project", "user", "user_project"), "scope")
  if (identical(scope, "session")) return(the$settings_session %||% list())
  settings_file_read(settings_path(scope, create = FALSE))
}

#' Merges `patch` at top level into a scope: an atomic file write under a short lock, or the
#' process layer; NULL values remove keys (contract 7.8). The file is merged in its unsimplified
#' JSON form, so the keys the patch does not name keep their JSON types (contract 11: unknown
#' keys are preserved on rewrite), and a file that is not a JSON object is left alone
#' (`gptr_error_workspace`, settings_file_load()). Returns the merged value as settings_read()
#' simplifies it.
#' @noRd
settings_write = function(scope, patch) {
  scope = check_choice(scope, c("session", "project", "user", "user_project"), "scope")
  check_list(patch, "patch", named = TRUE)
  if (identical(scope, "session")) {
    cur = settings_merge_top(the$settings_session %||% list(), patch)
    the$settings_session = cur
    return(invisible(cur))
  }
  path = settings_path(scope, create = TRUE)
  lock = file_lock(path)
  on.exit(file_unlock(lock), add = TRUE)
  cur = settings_merge_top(settings_file_load(path), patch)
  if (identical(scope, "user_project")) {
    cur$version = cur$version %||% 1L
    cur$root = cur$root %||% project_root()
  }
  settings_file_write(path, cur)
  invisible(json_simplify(cur))
}

# ------------------------------------------------------------------ control-category check (IC-53)

#' Refuses a configuration change made from model code during a run, unless the dispatcher
#' approved exactly this call through an ask_human: a one-shot token, the function name appended
#' to `run$signal$control` by P06's perm_grant_control() (P11's gate), consumed here. P06's
#' session_control_check() (gptr_fork(), gptr_resume()) and P11's perm_control_guard() read the
#' same slot.
#' @noRd
control_check = function(what) {
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  sig = run$signal
  ok = if (is.environment(sig)) sig$control %||% character() else character()
  i = match(what, ok)
  if (!is.na(i)) {
    sig$control = ok[-i]
    return(invisible(TRUE))
  }
  gptr_abort(c(paste0(what, "() changes gptr's configuration and was called from model code ",
                      "during a run."),
               "Only you can make this change: run it outside the run, or approve it when asked."),
             "permission", action = what, tool = run$tool_call[["name"]] %||% "r", risk = 4L,
             how_to_allow = "call it yourself outside gptr(), or approve the r call when asked",
             session = run$session)
}

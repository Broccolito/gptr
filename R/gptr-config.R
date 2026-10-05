# gptr-config.R -- settings files and layers, gptr_config(), gptr_init(), gptr_trust(), the egress
# acknowledgement, replay_mode() and replay_guard() (plan P08; contract sections 6.2, 7.8,
# 11.1-11.3, 11.8, 11.16; IC-45, IC-52, IC-53, IC-71, IC-74). Layer L6: it calls L0-L3 functions,
# the kernel SDK and services only.

# ------------------------------------------------------------------ P08 state in `the`

#' P08's process state (`the$gateway`, see the plan's contract ambiguities): parsed settings
#' files, trust decisions taken in this process (with the fingerprint they were taken for),
#' trust fingerprints, the answers given in this process about project base URLs, the
#' gateway_defer() depth, the pending run options of sessions built with `.run = FALSE`, the call
#' records held for them and the ids of the rank-0 records each session's calls registered (all
#' three keyed by session id; released by builtin:gateway's agent_end and session_shutdown hooks,
#' Task 9)
#' @noRd
gateway_state = function() {
  st = the$gateway
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$files = new.env(parent = emptyenv())
    st$trust = new.env(parent = emptyenv())
    st$fingerprints = new.env(parent = emptyenv())
    st$base_urls = new.env(parent = emptyenv())
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

#' Core keys that a registered `setting` spec cannot redefine (IC-74, 07-local-ollama.md section
#' 5: extensions cannot relax `local_only`; contract 11.2: `egress` is read from the user file
#' only). `providers` holds the protected `local_only` control and the origins provider
#' credentials go to, `egress` the user's acknowledgements. Their spec is always the core table
#' entry, and a dotted key below them always resolves inside them (settings_resolve()).
#' @noRd
settings_protected = function(key) key %in% c("providers", "egress")

#' The core table entry of a key as a spec record, or NULL
#' @noRd
settings_core_spec = function(key) {
  for (x in settings_core()) {
    if (identical(x$name, key)) {
      return(list(name = x$name, default = x$default, scope = x$scope, tighten = x$tighten,
                  validate = setting_validator(x$name, x$type, x$choices)))
    }
  }
  NULL
}

#' The spec of a setting: the core table entry of a protected key (settings_protected()), else the
#' registered record, else the core table entry, else NULL
#' @noRd
settings_spec = function(key) {
  if (settings_protected(key)) return(settings_core_spec(key))
  sp = registry_get("setting", key)
  if (!is.null(sp)) return(sp)
  settings_core_spec(key)
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

#' Writes a settings file atomically (UTF-8, LF, final newline) and drops its cache entry.
#' Returns the sha256 of the bytes written, invisibly (settings_write() checks its own write).
#' @noRd
settings_file_write = function(path, value) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  text = if (length(value)) json_encode(settings_arrays(value), pretty = TRUE) else "{}"
  bytes = charToRaw(paste0(paste(as_utf8(text), collapse = "\n"), "\n"))
  write_atomic(path, bytes)
  st = gateway_state()
  if (exists(path, envir = st$files, inherits = FALSE)) rm(list = path, envir = st$files)
  invisible(hash_sha256(bytes))
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
#' (`gptr_error_workspace`, settings_file_load()). A write to the settings of a trusted project
#' keeps the trust that held just before it (read under the lock): a recorded trust gets the new
#' fingerprint in trust.json, a decision of this process gets it in memory (gptr's own writes
#' re-fingerprint, IC-52; an in-process decision is never turned into a recorded one, and a trust
#' a foreign change had already voided is not restored). Only gptr's own change is carried over:
#' when another gated file changed beside the write, or settings.json no longer holds the bytes
#' gptr wrote, the trust lapses and the human is asked again (trust_own_write()). Returns the
#' merged value as settings_read() simplifies it.
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
  root = project_root()
  lock = file_lock(path)
  on.exit(file_unlock(lock), add = TRUE)
  was = if (identical(scope, "project")) trust_holds(root) else list(record = FALSE, live = FALSE)
  cur = settings_merge_top(settings_file_load(path), patch)
  if (identical(scope, "user_project")) {
    cur$version = cur$version %||% 1L
    cur$root = cur$root %||% root
  }
  wrote = settings_file_write(path, cur)
  if (isTRUE(was$record) || isTRUE(was$live)) {
    now = trust_fingerprint(root)
    if (trust_own_write(was$fp, now, path_rel(path, root = root), wrote)) {
      if (isTRUE(was$record)) trust_store(root, TRUE, now)
      if (isTRUE(was$live)) trust_mark(root, TRUE, now)
    }
  }
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

# ------------------------------------------------------------- trust (contract 6.2, 11.8; IC-52)

#' Path of `trust.json` in the user config directory
#' @noRd
trust_file = function(create = FALSE) {
  file.path(gptr_user_dir("config", create = create), "trust.json")
}

#' The trust store for reading: list(version, projects = named list keyed by path_key(root)).
#' A file that is not a JSON object, or whose `projects` is not an object, trusts nothing.
#' @noRd
trust_read = function(fresh = FALSE) {
  x = settings_file_read(trust_file(), fresh = fresh)
  p = x[["projects"]]
  if (!is.list(p) || (length(p) && is.null(names(p)))) x$projects = list()
  x
}

#' The trust store for a read-modify-write under its lock: the unsimplified object of
#' settings_file_load(); a file whose `projects` is not an object is never rewritten
#' (`gptr_error_workspace`), as settings_file_load() refuses a file that is not an object
#' @noRd
trust_load = function(path) {
  x = settings_file_load(path)
  p = x[["projects"]]
  if (!is.null(p) && !(is.list(p) && (!length(p) || !is.null(names(p))))) {
    gptr_abort(c(paste0("The trust store ", path, " has no `projects` object, so gptr will not ",
                        "rewrite it."),
                 "Fix the file or remove it, then try again."), "workspace", path = path)
  }
  x
}

#' The recorded trust entry of a project root, or NULL
#' @noRd
trust_record = function(root) {
  rec = trust_read()$projects[[path_key(root)]]
  if (is.list(rec)) rec else NULL
}

#' Existing trust-gated files of a project (IC-52): .gptr/settings.json, mcp.json, SYSTEM.md,
#' APPEND_SYSTEM.md, the files under extensions/, plugins/ and agents/, and the .env files that
#' P03's automatic discovery reads (dotenv_project_files(): .gptr/.env and .env)
#' @noRd
trust_gated_paths = function(root) {
  ws = file.path(root, ".gptr")
  files = file.path(ws, c("settings.json", "mcp.json", "SYSTEM.md", "APPEND_SYSTEM.md"))
  found = c(files[file.exists(files) & !dir.exists(files)], dotenv_project_files(root))
  for (d in file.path(ws, c("extensions", "plugins", "agents"))) {
    if (dir.exists(d)) {
      found = c(found, list.files(d, recursive = TRUE, full.names = TRUE, all.files = TRUE))
    }
  }
  unique(found)
}

#' TRUE when the project holds anything the trust question is about (IC-52): trust-gated files,
#' AGENTS.md, CLAUDE.md, .gptr/skills/ or .gptr/agents/
#' @noRd
trust_resources_present = function(root) {
  length(trust_gated_paths(root)) > 0L ||
    any(file.exists(file.path(root, c("AGENTS.md", "CLAUDE.md")))) ||
    any(dir.exists(file.path(root, ".gptr", c("skills", "agents"))))
}

#' sha256 of one gated file's bytes; a file that cannot be read (gptr cannot load it either)
#' hashes as "unreadable", so its fingerprint changes once it can be read
#' @noRd
trust_file_hash = function(path) {
  tryCatch(hash_sha256(readBin(path, "raw", n = max(1, file.size(path)))),
           warning = function(w) "unreadable", error = function(e) "unreadable")
}

#' Trust fingerprint (IC-52): sha256 of the canonical JSON object of the gated files' root-relative
#' paths and content hashes (keys in radix order, so no path can be confused with a hash). Cached
#' by path, mtime, ctime and size: ctime moves on every write and on every mtime reset, so a
#' same-size rewrite that restores the old mtime is not served from the cache. Returns
#' list(fp = chr(1), files = chr of file hashes named by relative path, in radix order).
#' @noRd
trust_fingerprint = function(root) {
  paths = trust_gated_paths(root)
  info = file.info(paths, extra_cols = FALSE)
  stamp = paste(paths, format(as.numeric(info$mtime), digits = 15),
                format(as.numeric(info$ctime), digits = 15), info$size, collapse = "|")
  st = gateway_state()
  key = path_key(root)
  hit = get0(key, envir = st$fingerprints, inherits = FALSE)
  if (!is.null(hit) && identical(hit$stamp, stamp)) return(hit$value)
  rel = path_rel(paths, root = root)
  hashes = vapply(paths, trust_file_hash, "", USE.NAMES = FALSE)
  names(hashes) = rel
  hashes = hashes[order(rel, method = "radix")]
  fp = hash_sha256(canonical_json(if (length(hashes)) as.list(hashes) else json_obj()))
  value = list(fp = fp, files = hashes)
  assign(key, list(stamp = stamp, value = value), envir = st$fingerprints)
  value
}

#' Records a trust decision with a fingerprint (atomic, under a short lock): by default the
#' current one, or `fp` (a trust_fingerprint() value), the state a question was asked about. The
#' per-file hashes are kept too, so a later mismatch can list the changed files; the other
#' projects and the entry's other fields (`base_url_confirmed`) are kept.
#' @noRd
trust_store = function(root, trusted, fp = NULL) {
  path = trust_file(create = TRUE)
  fp = fp %||% trust_fingerprint(root)
  lock = file_lock(path)
  on.exit(file_unlock(lock), add = TRUE)
  x = trust_load(path)
  key = path_key(root)
  rec = x[["projects"]][[key]]
  if (!is.list(rec) || (length(rec) && is.null(names(rec)))) rec = list()
  rec$trusted = isTRUE(trusted)
  rec$date = format(Sys.Date())
  rec$fingerprint = fp$fp
  rec$files = if (length(fp$files)) as.list(fp$files) else json_obj()
  x$version = x[["version"]] %||% 1L
  x$projects[[key]] = rec
  settings_file_write(path, x)
  st = gateway_state()
  if (exists(key, envir = st$trust, inherits = FALSE)) rm(list = key, envir = st$trust)
  invisible(rec)
}

#' Remembers a trust decision taken in this process (a `project_trust` handler or the interactive
#' question) together with the fingerprint it was taken for (`fp`, a trust_fingerprint() value;
#' default the current one): it holds only while the gated files are unchanged (IC-52: "Control
#' files modified during the process are not loaded again without confirmation")
#' @noRd
trust_mark = function(root, decision, fp = NULL) {
  fp = fp %||% trust_fingerprint(root)
  assign(path_key(root), list(decision = isTRUE(decision), fp = fp$fp),
         envir = gateway_state()$trust)
  invisible(decision)
}

#' Which trust holds for a project root now: `record` (trust.json says trusted and the
#' fingerprint matches) and `live` (a decision of this process whose fingerprint matches), with
#' `fp`, the trust_fingerprint() value they were checked against (NULL when neither was trusted)
#' @noRd
trust_holds = function(root) {
  key = path_key(root)
  hit = get0(key, envir = gateway_state()$trust, inherits = FALSE)
  rec = trust_record(root)
  live = is.list(hit) && isTRUE(hit$decision)
  recorded = !is.null(rec) && isTRUE(rec[["trusted"]])
  if (!live && !recorded) return(list(record = FALSE, live = FALSE, fp = NULL))
  fp = trust_fingerprint(root)
  list(record = recorded && identical(rec[["fingerprint"]], fp$fp),
       live = live && identical(hit$fp, fp$fp), fp = fp)
}

#' TRUE when the only change from fingerprint `before` to `after` (trust_fingerprint() values) is
#' gptr's own write of the gated file `rel`, which must hold exactly the bytes whose sha256 is
#' `hash`: every other gated file is unchanged, none appeared or went away (IC-52: gptr's own
#' writes re-fingerprint; any other change needs the human's confirmation)
#' @noRd
trust_own_write = function(before, after, rel, hash) {
  if (is.null(before) || is.null(after)) return(FALSE)
  others = function(x) {
    x = x[names(x) != rel]
    paste(names(x), x, sep = "\t")
  }
  identical(unname(after$files[rel]), hash) &&
    identical(others(before$files), others(after$files))
}

#' TRUE only when the project is recorded as trusted, or a `project_trust` handler or the user
#' accepted it in this process, and the trust fingerprint still matches (the `trust.get`
#' service; IC-33, IC-52)
#' @noRd
trust_get = function(path = getwd()) {
  h = trust_holds(project_root(path))
  h$record || h$live
}

#' The decision of a `project_trust` handler: TRUE ("yes"), FALSE ("no") or NA (no handler, or an
#' answer that is not "yes" or "no", which is a diagnostic and has no opinion)
#' @noRd
trust_answer = function(res) {
  if (!is.list(res) || !length(res)) return(NA)
  d = res[["decision"]]
  if (is.character(d) && length(d) == 1L && !is.na(d) && d %in% c("yes", "no")) {
    return(identical(d, "yes"))
  }
  registry_diagnostic("builtin:gateway", "project_trust", "malformed_decision",
                      "a project_trust handler answered without decision = \"yes\" or \"no\"")
  NA
}

#' Decides trust for a project root once per process and fingerprint: the recorded decision, else
#' the first decision of `project_trust` handlers, else the interactive question, else untrusted
#' with one notice per fingerprint. A changed gated file voids an earlier in-process decision and
#' a recorded trust (IC-52); a recorded "no" stands until gptr_trust() changes it.
#' @noRd
trust_resolve = function(root) {
  h = trust_holds(root)
  if (h$record || h$live) return(TRUE)
  key = path_key(root)
  fp = trust_fingerprint(root)
  done = get0(key, envir = gateway_state()$trust, inherits = FALSE)
  if (is.list(done) && identical(done$fp, fp$fp)) return(isTRUE(done$decision))
  if (!trust_resources_present(root)) return(FALSE)
  rec = trust_record(root)
  if (!is.null(rec) && !isTRUE(rec[["trusted"]])) {
    trust_mark(root, FALSE, fp)
    return(FALSE)
  }
  old = unlist(rec[["files"]])
  if (!is.character(old) || is.null(names(old))) old = character()
  now = fp$files
  changed = names(now)[is.na(old[names(now)]) | old[names(now)] != now]
  changed = sort(unique(c(changed, setdiff(names(old), names(now)))), method = "radix")
  since = if (!is.null(rec) && length(changed)) paste(changed, collapse = ", ") else NULL
  res = ev_dispatch("project_trust", ev_new("project_trust", cwd = root, changed = changed))
  decision = trust_answer(res)
  if (!is.na(decision)) {
    if (isTRUE(res[["remember"]])) trust_store(root, decision, fp)
  } else if (gptr_can_prompt()) {
    what = if (is.null(since)) "" else paste0(" Changed since you last trusted it: ", since, ".")
    decision = isTRUE(gptr_confirm(paste0("Trust this project (its settings, extensions and MCP ",
                                          "servers)?", what)))
    trust_store(root, decision, fp)
  } else {
    why = if (is.null(since)) "" else paste0(" (changed since you trusted it: ", since, ")")
    gptr_inform(paste0("Project resources in ", root, " were not loaded because the project is ",
                       "not trusted", why, ". Use gptr_trust() to trust it."), "notice",
                .once = paste0("trust:", key, ":", fp$fp))
    decision = FALSE
  }
  trust_mark(root, decision, fp)
  decision
}

#' Record or read whether a project is trusted
#'
#' Trust decides whether gptr applies or runs what a project directory contains: project
#' settings beyond tightening, `.gptr/extensions/` and project plugins, project MCP servers,
#' `SYSTEM.md` and `APPEND_SYSTEM.md`, project `.env` discovery, provider base-URL overrides, the
#' tool and model fields of project agent files, and the authority of project instructions. The
#' decision is kept in `tools::R_user_dir("gptr", "config")/trust.json` with a fingerprint of the
#' trust-gated files; when they change, the project counts as untrusted again until you confirm.
#' Called from model code during a run, recording a decision is refused.
#'
#' @param path A directory inside the project; its project root is used.
#' @param trust `NULL` to read the decision, `TRUE` or `FALSE` to record one.
#' @return With `trust = NULL`, the recorded decision: `TRUE`, `FALSE` or `NA` (undecided).
#'   Otherwise the previous decision, invisibly.
#' @examples
#' d = tempfile("proj")
#' dir.create(d)
#' gptr_trust(d)
#' unlink(d, recursive = TRUE)
#' @export
gptr_trust = function(path = ".", trust = NULL) {
  check_string(path, "path")
  check_flag(trust, "trust", null = TRUE)
  root = project_root(path)
  rec = trust_record(root)
  prev = if (is.null(rec)) NA else isTRUE(rec[["trusted"]])
  if (is.null(trust)) return(prev)
  control_check("gptr_trust")
  trust_store(root, trust)
  invisible(prev)
}

on_load(ext_service_set("trust.get", trust_get, provided_by = "P08", builtin = "gateway"))

# ------------------------------------------------------------------ settings layers (contract 11.2)

#' Looks a key up in one layer: a flat key first (plugin keys such as "panel.size"), else a dotted
#' path into nested objects ("subagents.max_depth"). A flat key present with a JSON null is found:
#' an explicit null is a value (`compact_at: null` disables the cap, contract 11.2).
#' @noRd
settings_lookup = function(layer, key) {
  if (!is.list(layer) || !length(layer)) return(list(found = FALSE, value = NULL))
  if (key %in% names(layer)) return(list(found = TRUE, value = layer[[key]]))
  parts = strsplit(key, ".", fixed = TRUE)[[1L]]
  if (length(parts) < 2L) return(list(found = FALSE, value = NULL))
  v = settings_dig(layer, parts)
  list(found = !is.null(v), value = v)
}

#' Walks a dotted path into nested named lists; NULL when a step is missing
#' @noRd
settings_dig = function(x, parts) {
  for (p in parts) {
    if (!is.list(x) || !p %in% names(x)) return(NULL)
    x = x[[p]]
  }
  x
}

#' Wraps a value in objects along a path: settings_nest(c("a", "b"), 1) is list(a = list(b = 1))
#' @noRd
settings_nest = function(path, value) {
  for (p in rev(path)) value = stats::setNames(list(value), p)
  value
}

#' Combines a lower and a higher layer: objects merge recursively, anything else is replaced
#' @noRd
settings_combine = function(lower, higher) {
  if (is.list(lower) && !is.object(lower) && is.list(higher) && !is.object(higher) &&
      !is.null(names(higher))) {
    return(utils::modifyList(lower, higher))
  }
  higher
}

#' What one layer may contribute to a top-level key. In `providers` (IC-74, 07-local-ollama.md
#' sections 2.1 and 5) `local_only` stays TRUE unless a human layer, the user settings file or
#' the session layer, sets it to FALSE: there a value that is not TRUE or FALSE counts as TRUE,
#' and every `local_only` other than TRUE is dropped from what the defaults, a project file or
#' options() contribute, so they can tighten it and never relax it. A provider entry that held
#' nothing else is dropped with it.
#' @noRd
settings_guard = function(key, value, human) {
  if (!identical(key, "providers") || !is.list(value)) return(value)
  emptied = logical(length(value))
  for (i in seq_along(value)) {
    e = value[[i]]
    if (!is.list(e) || !("local_only" %in% names(e))) next
    v = e[["local_only"]]
    if (isTRUE(v) || (human && identical(v, FALSE))) next
    e[["local_only"]] = if (human) TRUE else NULL
    emptied[i] = !length(e)
    value[i] = list(e)
  }
  if (any(emptied)) value = value[!emptied]
  value
}

#' TRUE when a dotted path is present in nested named lists (a present NULL counts)
#' @noRd
settings_reaches = function(x, parts) {
  for (p in parts) {
    if (!is.list(x) || is.null(names(x)) || !p %in% names(x)) return(FALSE)
    x = x[[p]]
  }
  TRUE
}

#' Applies one layer's contribution `add` to the state `st` (list(value, source)) of the key
#' `key`, through settings_guard(). A contribution the guard empties is no contribution. The layer
#' becomes the source when, for a dotted key (`path` below `key`), its contribution reaches the
#' key or replaces the whole object.
#' @noRd
settings_apply = function(st, key, add, layer, human, path = character()) {
  g = settings_guard(key, add, human)
  if (is.list(add) && length(add) && is.list(g) && !length(g)) return(st)
  st$value = settings_combine(st$value, g)
  named = is.list(g) && !is.object(g) && !is.null(names(g))
  if (!length(path) || !named || settings_reaches(g, path)) st$source = layer
  st
}

#' Applies the option or session entries of the dotted names from `key` down to `key.<path>` (less
#' specific first; IC-71: `gptr.subagents.<key>` are the same knobs as the object's keys) to the
#' state `st` through settings_apply()
#' @noRd
settings_dotted = function(st, key, path, layer) {
  ses = the$settings_session %||% list()
  for (j in seq_along(path)) {
    name = paste(c(key, path[seq_len(j)]), collapse = ".")
    v = if (identical(layer, "option")) getOption(paste0("gptr.", name)) else ses[[name]]
    if (is.null(v)) next
    st = settings_apply(st, key, settings_nest(path[seq_len(j)], v), layer,
                        human = identical(layer, "session"), path = path)
  }
  st
}

#' Union of permission rule lists (only the lists named in `lists` are taken from `add`)
#' @noRd
settings_perm_union = function(base, add, lists) {
  out = if (is.list(base)) base else list()
  if (!is.list(add)) return(out)
  for (k in lists) {
    extra = as.character(unlist(add[[k]]))
    if (length(extra)) out[[k]] = unique(c(as.character(unlist(out[[k]])), extra))
  }
  out
}

#' The value a project settings file contributes (IC-52): tighten-type keys only tighten;
#' permissions add deny and ask rules (allow too when trusted); providers follow
#' settings_project_providers(); other keys apply only in a trusted project
#' @noRd
settings_project_value = function(key, spec, current, new, trusted, root) {
  if (identical(key, "permissions")) {
    lists = if (trusted) c("allow", "ask", "deny") else c("ask", "deny")
    return(settings_perm_union(current, new, lists))
  }
  if (identical(key, "providers")) {
    return(settings_project_providers(current, new, trusted, root))
  }
  tighten = spec$tighten
  if (!is.null(tighten)) {
    if (!is.character(new) || length(new) != 1L || !(new %in% tighten)) return(current)
    now = match(if (is.character(current)) current[1L] else tighten[length(tighten)], tighten)
    if (is.na(now) || match(new, tighten) <= now) return(new)
    return(current)
  }
  if (!trusted) return(current)
  settings_combine(current, new)
}

#' The `providers` a project settings file contributes (contract 11.2, architecture 6.5, IC-74):
#' an untrusted project only tightens `local_only`; a trusted one adds its entries, but its
#' `local_only` only tightens and its `base_url` applies only once the user confirmed that URL
#' for this project (settings_base_url_ok())
#' @noRd
settings_project_providers = function(current, new, trusted, root) {
  if (!is.list(new) || is.null(names(new))) return(current)
  new = settings_guard("providers", new, human = FALSE)
  if (!trusted) {
    keep = vapply(new, function(e) is.list(e) && isTRUE(e[["local_only"]]), NA)
    if (!any(keep)) return(current)
    return(settings_combine(current, lapply(new[keep], function(e) list(local_only = TRUE))))
  }
  for (i in seq_along(new)) {
    e = new[[i]]
    if (!is.list(e) || !("base_url" %in% names(e))) next
    if (!settings_base_url_ok(root, names(new)[i], e[["base_url"]])) {
      e[["base_url"]] = NULL
      new[i] = list(e)
    }
  }
  settings_combine(current, new)
}

#' TRUE when a trusted project's `providers.<id>.base_url` may be used: the user confirmed that
#' URL for this project once (contract 11.2; architecture 6.5: a project base URL decides where
#' the provider's credentials go). A confirmation is kept in the project's trust.json entry
#' (`base_url_confirmed`) when the trust is recorded, else for this process; a refusal holds for
#' this process. Without someone to ask, the URL is not used and a notice says so.
#' @noRd
settings_base_url_ok = function(root, id, url) {
  if (!is.character(url) || length(url) != 1L || is.na(url) || !nzchar(url) || !nzchar(id)) {
    return(FALSE)
  }
  rec = trust_record(root)
  done = rec[["base_url_confirmed"]]
  if (is.list(done) && identical(done[[id]], url)) return(TRUE)
  st = gateway_state()
  memo = paste(path_key(root), id, url, sep = "\n")
  hit = get0(memo, envir = st$base_urls, inherits = FALSE)
  if (is.logical(hit)) return(hit)
  shown = redact(url)
  if (!gptr_can_prompt()) {
    gptr_inform(paste0("The base URL ", shown, " that the settings of ", root, " give for ",
                       "provider ", id, " was not used: a project base URL needs your one-time ",
                       "confirmation in an interactive session."), "notice",
                .once = paste0("base_url:", memo))
    return(FALSE)
  }
  ok = isTRUE(gptr_confirm(paste0("The settings of the project ", root, " send provider ", id,
                                  " requests, with its credentials, to ", shown,
                                  ". Use this base URL?")))
  if (ok && isTRUE(rec[["trusted"]])) trust_store_base_url(root, id, url)
  assign(memo, ok, envir = st$base_urls)
  ok
}

#' Records a confirmed project base URL in the project's trusted entry of trust.json (atomic,
#' under the short lock; the entry's other fields and the other projects are kept)
#' @noRd
trust_store_base_url = function(root, id, url) {
  path = trust_file(create = TRUE)
  lock = file_lock(path)
  on.exit(file_unlock(lock), add = TRUE)
  x = trust_load(path)
  key = path_key(root)
  rec = x[["projects"]][[key]]
  if (!is.list(rec) || !isTRUE(rec[["trusted"]])) return(invisible(FALSE))
  done = rec[["base_url_confirmed"]]
  if (!is.list(done) || (length(done) && is.null(names(done)))) done = list()
  done[[id]] = url
  rec$base_url_confirmed = done
  x$projects[[key]] = rec
  settings_file_write(path, x)
  invisible(TRUE)
}

#' Normalises a resolved value to its spec's type (JSON arrays of names become character vectors)
#' @noRd
settings_normalise = function(spec, value) {
  if (is.character(spec$default) && is.list(value) && is.null(names(value))) {
    return(as.character(unlist(value)))
  }
  value
}

#' The legacy `.gptr/settings.local.json` of a trusted project: only its permissions.deny and
#' permissions.ask entries count; other keys are ignored with one notice (IC-52)
#' @noRd
settings_local_permissions = function(ws, value) {
  path = file.path(ws, "settings.local.json")
  local = settings_file_read(path)
  if (!is.list(local) || !length(local)) return(value)
  perms = local[["permissions"]]
  if (!is.list(perms)) perms = list()
  ignored = c(intersect(names(local), c("record", "transcript")),
              if (length(unlist(perms[["allow"]]))) "permissions.allow")
  if (length(ignored)) {
    gptr_inform(paste0("Ignored in ", path, ": ", paste(ignored, collapse = ", "),
                       " (only deny and ask rules are read from this file)."), "notice",
                .once = paste0("settings.local:", path_key(path)))
  }
  settings_perm_union(value, perms, c("ask", "deny"))
}

#' The value at a dotted path below a key's value (the value itself for an empty path)
#' @noRd
settings_at = function(x, path) if (length(path)) settings_dig(x, path) else x

#' A top-level key through every layer, lowest to highest (contract 11.2): defaults < user file <
#' project file (trust rules) < user-level project file (permissions) < options() < session
#' layer. With `path`, the key `<key>.<path>` resolves inside the object: the option layer is
#' options(gptr.<key>) then the options of the dotted names down to the key, and the session
#' layer likewise (settings_dotted()), so a session object is above a dotted option. A key
#' without a `setting` spec takes its documented option default (P01's gptr_option_defaults), as
#' setting_get() does without this service. A `scope = "user"` setting (`egress`) is read from
#' the user file only. settings_guard() decides what each layer, the defaults included, may
#' contribute; the source is the highest layer that set or changed the value at the key.
#' @noRd
settings_layered = function(key, path = character()) {
  spec = settings_spec(key)
  st = list(value = if (is.null(spec)) gptr_option_defaults[[key]] else spec$default,
            source = "default")
  st$value = settings_guard(key, st$value, human = FALSE)
  done = function(st) {
    list(value = settings_at(settings_normalise(spec, st$value), path), source = st$source)
  }
  u = settings_lookup(settings_file_read(settings_path("user")), key)
  if (u$found) st = settings_apply(st, key, u$value, "user", human = TRUE, path = path)
  if (identical(spec$scope, "user")) return(done(st))
  ws = workspace_dir()
  if (!is.null(ws)) {
    root = project_root()
    p = settings_lookup(settings_file_read(file.path(ws, "settings.json")), key)
    perms = identical(key, "permissions")
    trusted = (p$found || perms) && isTRUE(trust_get(root))
    if (p$found) {
      nv = settings_project_value(key, spec, st$value, p$value, trusted, root)
      if (!identical(settings_at(nv, path), settings_at(st$value, path))) st$source = "project"
      st$value = nv
    }
    if (perms && trusted) {
      nv = settings_local_permissions(ws, st$value)
      if (!identical(nv, st$value)) st = list(value = nv, source = "project")
    }
  }
  if (identical(key, "permissions")) {
    up = settings_lookup(settings_file_read(settings_path("user_project")), key)
    if (up$found) {
      st = list(value = settings_perm_union(st$value, up$value, c("allow", "ask", "deny")),
                source = "user_project")
    }
  }
  opt = getOption(paste0("gptr.", key))
  if (!is.null(opt)) st = settings_apply(st, key, opt, "option", human = FALSE, path = path)
  st = settings_dotted(st, key, path, "option")
  ses = settings_lookup(the$settings_session %||% list(), key)
  if (ses$found) st = settings_apply(st, key, ses$value, "session", human = TRUE, path = path)
  done(settings_dotted(st, key, path, "session"))
}

#' A key and the layer it came from (settings_layered()). A dotted key resolves inside its
#' top-level object when that object is protected (settings_protected()), or is a setting and the
#' dotted key is not registered itself.
#' @noRd
settings_resolve = function(key) {
  parts = strsplit(key, ".", fixed = TRUE)[[1L]]
  if (length(parts) < 2L || !all(nzchar(parts))) return(settings_layered(key))
  inside = settings_protected(parts[1L]) ||
    (is.null(settings_spec(key)) && !is.null(settings_spec(parts[1L])))
  if (!inside) return(settings_layered(key))
  settings_layered(parts[1L], parts[-1L])
}

#' The effective value of a setting through the layers of contract 11.2: the `settings.get`
#' service behind P01's setting_get(). `session` is accepted for the service signature; settings
#' are process-wide in 1.0.
#' @noRd
settings_get = function(key, session = NULL) {
  check_string(key, "key")
  settings_resolve(key)$value
}

#' The protected local-only control of a provider (IC-74, 07-local-ollama.md sections 2.1 and 5):
#' FALSE only when the user settings file or the session layer sets `providers.<id>.local_only`
#' to FALSE and no layer above tightens it; the defaults, project files, options() and registered
#' `setting` specs can only tighten it, and an unset or malformed value is TRUE. Read from the
#' core `providers` object (never through a registered spec of the dotted name). The value of a
#' run's protected safety record (`ollama_local_only`).
#' @noRd
settings_local_only = function(provider = "ollama") {
  check_string(provider, "provider")
  if (!grepl("^[a-z0-9][a-z0-9-]*\\z", provider, perl = TRUE)) {
    gptr_abort("`provider` must be a provider id such as \"ollama\".", "invalid_argument",
               arg = "provider", expected = "a provider id (^[a-z0-9][a-z0-9-]*$)")
  }
  !identical(settings_layered("providers", c(provider, "local_only"))$value, FALSE)
}

#' The effective settings with the layer of each key (class `gptr_config`, contract 5.11)
#' @noRd
settings_effective = function() {
  keys = settings_keys()
  values = vector("list", length(keys))
  sources = character(length(keys))
  for (i in seq_along(keys)) {
    r = settings_resolve(keys[i])
    if (!is.null(r$value)) values[[i]] = r$value
    sources[i] = r$source
  }
  names(values) = keys
  names(sources) = keys
  structure(values, sources = sources, class = "gptr_config")
}

#' One-line rendering of a setting value, redacted (a provider header may hold a secret) and cut
#' at 60 characters
#' @noRd
settings_format_value = function(v) {
  txt = if (is.null(v)) {
    "null"
  } else if (is.character(v) && length(v) == 1L) {
    v
  } else if (is.atomic(v) && length(v) == 1L) {
    format(v, scientific = FALSE, trim = TRUE)
  } else {
    tryCatch(json_encode(v), error = function(e) paste0("<", class(v)[1L], ">"))
  }
  txt = redact(paste(txt, collapse = " "))
  if (nchar(txt) > 60L) paste0(substr(txt, 1L, 57L), "...") else txt
}

#' Print the effective settings: value and layer per key (contract 5.11)
#' @export
#' @noRd
print.gptr_config = function(x, ...) {
  src = attr(x, "sources")
  keys = names(x)
  width = max(c(nchar(keys), 1L))
  lines = character(length(keys))
  for (i in seq_along(keys)) {
    layer = unname(src[keys[i]])
    if (is.na(layer)) layer = "default"
    lines[i] = paste0(formatC(keys[i], width = -width), "  ", settings_format_value(x[[i]]),
                      "  [", layer, "]")
  }
  cat(lines, sep = "\n")
  invisible(x)
}

on_load(ext_service_set("settings.get", settings_get, provided_by = "P08", builtin = "gateway"))

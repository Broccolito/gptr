# gptr-config.R -- settings files and layers, gptr_config(), gptr_init(), gptr_trust(), the egress
# acknowledgement, replay_mode() and replay_guard() (plan P08, layer L6; contract 6.2, 7.8,
# 11.1-11.3, 11.8, 11.16; IC-45, IC-52, IC-53, IC-71, IC-74).

# ------------------------------------------------------------------ P08 state in `the`

#' P08's process state `the$gateway`: the settings file cache, trust decisions and fingerprints,
#' base-URL answers, the defer depth, per-session pending run options, held call records and
#' rank-0 spec ids, and `filters_applied` (gateway_filters_sync())
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
    rec("mode", "manual", "choice", "Permission mode.", choices = session_modes,
        tighten = session_modes),
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
    rec("type_ahead", "steer", "choice",
        paste("What Enter does with a message typed in a terminal console while the agent works",
              "(Tab does the other); in other consoles, what a typed line does."),
        choices = c("steer", "follow_up")),
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
      choice = gateway_choice(value, choices, name),
      chrs = as.character(check_strings(value, name)),
      object = settings_check_object(value, name),
      providers = settings_check_providers(value, name),
      value)
  }
}

#' TRUE for a JSON object: a plain list that is named or empty
#' @noRd
settings_is_object = function(x) is.list(x) && !is.object(x) && (!length(x) || !is.null(names(x)))

#' Checks that a setting value is a JSON object with non-empty names
#' @noRd
settings_check_object = function(value, name) {
  if (!settings_is_object(value) || !all(nzchar(names(value)))) {
    gptr_abort(paste0("The setting `", name, "` takes a named list (a JSON object)."),
               "invalid_argument", arg = name, expected = "a named list")
  }
  value
}

#' Checks the `providers` setting: an object of provider objects whose `local_only`, when given,
#' is TRUE or FALSE (07 section 5)
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

#' Core keys a registered `setting` spec cannot redefine (IC-74, 07 section 5; contract 11.2):
#' `providers` (the local-only control, credential origins) and `egress`; a dotted key below them
#' resolves inside them
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

#' Path of a scope's settings file; `user_project` is IC-52's user-level project file, which
#' gptr_permissions(scope = "project") writes
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
    # the first 16 hex of sha256 of the project root's path key (IC-52)
    user_project = file.path(gptr_user_dir("config", create = create), "projects",
                             paste0(substr(hash_sha256(path_key(project_root())), 1L, 16L),
                                    ".json")),
    gptr_abort(paste0("Unknown settings scope `", scope, "`."), "invalid_argument",
               arg = "scope", expected = "session, project, user or user_project"))
}

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

#' Windows ctime is creation time: verify contents before accepting a metadata cache hit
#' @noRd
settings_content_hash = function(paths) {
  if (.Platform$OS.type != "windows") return(NULL)
  vapply(paths, trust_file_hash, "", USE.NAMES = FALSE)
}

#' Settings cache stamp and age; an unavailable content hash never permits a hit or insertion
#' @noRd
settings_file_stamp = function(path, info = path_info(path)) {
  time = as.numeric(c(info$mtime, info$ctime))
  hashes = settings_content_hash(path)
  stamp = paste(c(format(time, digits = 15), info$size), collapse = " ")
  if (!is.null(hashes)) stamp = paste(stamp, paste(hashes, collapse = "|"))
  list(stamp = stamp, time = time, hashes = hashes,
       readable = is.null(hashes) || all(grepl("^[0-9a-f]{64}$", hashes)))
}

#' Reads a JSON settings file through a metadata cache, with a Windows content digest. A file
#' changed within the last 2 s is not cached (git's racy-clean rule). Windows insertions also
#' verify the stamp after decoding; a changed post-decode stamp is not cached. A malformed
#' file is a diagnostic and reads as empty.
#' @noRd
settings_file_read = function(path) {
  if (!file.exists(path)) return(list())
  st = gateway_state()
  before = settings_file_stamp(path)
  hit = get0(path, envir = st$files, inherits = FALSE)
  if (before$readable && !is.null(hit) && identical(hit$stamp, before$stamp)) return(hit$value)
  if (!is.null(hit)) rm(list = path, envir = st$files)
  value = json_simplify(settings_decode(path))
  after = if (is.null(before$hashes)) before else settings_file_stamp(path)
  if (after$readable && identical(before$stamp, after$stamp) &&
      all(is.finite(after$time)) && as.numeric(Sys.time()) - max(after$time) > 2) {
    assign(path, list(stamp = after$stamp, value = value), envir = st$files)
  }
  value
}

#' Decodes one settings file into its unsimplified JSON object (blank: empty). Not an object:
#' `gptr_error_workspace` when `strict` (a writer never replaces a file it could not read), else
#' a diagnostic and empty
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

#' Read-modify-write of a settings file under its short lock (IC-71): `fun` turns the unsimplified
#' object (settings_decode(strict = TRUE), never the cache; missing: empty) into the one to write,
#' or NULL to leave the file. Returns list(value, hash), the hash of the bytes written, invisibly.
#' @noRd
settings_file_update = function(path, fun) {
  lock_with(path, function() {
    value = fun(if (file.exists(path)) settings_decode(path, strict = TRUE) else list())
    if (is.null(value)) return(invisible(NULL))
    invisible(list(value = value, hash = settings_file_write(path, value)))
  })
}

#' Merges a patch at top level; a NULL value removes the key
#' @noRd
settings_merge_top = function(cur, patch) {
  for (k in names(patch)) {
    if (is.null(patch[[k]])) cur[[k]] = NULL else cur[k] = list(patch[[k]])
  }
  cur
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

#' Merges `patch` at top level into a scope (NULL removes a key; contract 7.8): the process layer,
#' or the unsimplified file under a short lock, so other keys keep their JSON types. A project
#' write carries the trust held before it over only for gptr's own change (trust_carry(); IC-52).
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
  was = list(record = FALSE, live = FALSE)
  up = settings_file_update(path, function(cur) {
    if (identical(scope, "project")) was <<- trust_holds(root)
    cur = settings_merge_top(cur, patch)
    if (identical(scope, "user_project")) {
      cur$version = cur$version %||% 1L
      cur$root = cur$root %||% root
    }
    cur
  })
  trust_carry(root, was, path, up$hash)
  invisible(json_simplify(up$value))
}

# ------------------------------------------------------------- trust (contract 6.2, 11.8; IC-52)

#' Path of `trust.json` in the user config directory
#' @noRd
trust_file = function(create = FALSE) {
  file.path(gptr_user_dir("config", create = create), "trust.json")
}

#' The trust store `x`: list(version, projects keyed by path_key(root)). A file that is not a JSON
#' object, or whose `projects` is not an object, trusts nothing; `strict` (a writer's object under
#' the lock) refuses such a `projects` with `gptr_error_workspace`, so it is never rewritten.
#' @noRd
trust_read = function(x = settings_file_read(trust_file()), strict = FALSE) {
  p = x[["projects"]]
  if (settings_is_object(p)) return(x)
  if (strict && !is.null(p)) {
    path = trust_file()
    gptr_abort(c(paste0("The trust store ", path, " has no `projects` object, so gptr will not ",
                        "rewrite it."),
                 "Fix the file or remove it, then try again."), "workspace", path = path)
  }
  x$projects = list()
  x
}

#' The recorded trust entry of a project root, or NULL
#' @noRd
trust_record = function(root) {
  rec = trust_read()$projects[[path_key(root)]]
  if (is.list(rec)) rec else NULL
}

#' Existing trust-gated files of a project (IC-52), including the .env files P03 discovers
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
#' an instruction file (AGENTS.md, AGENTS.override.md, CLAUDE.md, CLAUDE.local.md,
#' .gptr/vignette.Rmd), or a skill, prompt-template or agent directory gptr reads (.gptr/skills,
#' .gptr/prompts, .gptr/agents, .agents/skills, .claude/skills, .claude/agents, .codex/agents,
#' .pi/agents, a relative `skills.paths` entry)
#' @noRd
trust_resources_present = function(root) {
  files = c("AGENTS.md", "AGENTS.override.md", "CLAUDE.md", "CLAUDE.local.md", ".gptr/vignette.Rmd")
  dirs = c(".gptr/skills", ".gptr/prompts", ".gptr/agents", ".agents/skills", ".claude/skills",
           ".claude/agents", ".codex/agents", ".pi/agents")
  length(trust_gated_paths(root)) > 0L || any(file.exists(file.path(root, files))) ||
    any(dir.exists(c(file.path(root, dirs), trust_skill_paths(root))))
}

#' The relative `skills.paths` entries skill discovery reads (skill_setting_paths()), joined to
#' `root`. Reading a setting resolves no trust, so trust_resources_present() cannot recurse; a
#' project settings file is itself trust-gated.
#' @noRd
trust_skill_paths = function(root) {
  p = as.character(unlist(settings_layered("skills", "paths")$value, use.names = FALSE))
  p = p[!is.na(p) & !is_abs_path(p) & p != "~" & !grepl("^~[/\\\\]", p)]
  file.path(rep(root, length(p)), p)
}

#' sha256 of one gated file's bytes; a file that cannot be read (gptr cannot load it either)
#' hashes as "unreadable", so its fingerprint changes once it can be read
#' @noRd
trust_file_hash = function(path) {
  hash = tryCatch(unname(cli::hash_file_sha256(path)),
                  warning = function(w) "unreadable", error = function(e) "unreadable")
  if (length(hash) == 1L && !is.na(hash) && grepl("^[0-9a-f]{64}$", hash)) hash else "unreadable"
}

#' Trust fingerprint (IC-52): list(fp, files), fp the sha256 of the canonical JSON of the gated
#' files' relative paths and hashes. Cached by path, mtime, ctime and size; Windows additionally
#' verifies content hashes because its ctime does not change on an in-place rewrite.
#' @noRd
trust_fingerprint = function(root) {
  paths = trust_gated_paths(root)
  info = path_info(paths)
  stamp = paste(paths, format(as.numeric(info$mtime), digits = 15),
                format(as.numeric(info$ctime), digits = 15), info$size, collapse = "|")
  hashes = settings_content_hash(paths)
  if (!is.null(hashes)) stamp = paste(stamp, paste(hashes, collapse = "|"), sep = "|")
  st = gateway_state()
  key = path_key(root)
  hit = get0(key, envir = st$fingerprints, inherits = FALSE)
  if (!is.null(hit) && identical(hit$stamp, stamp)) return(hit$value)
  rel = path_rel(paths, root = root)
  if (is.null(hashes)) hashes = vapply(paths, trust_file_hash, "", USE.NAMES = FALSE)
  names(hashes) = rel
  hashes = hashes[order(rel, method = "radix")]
  fp = hash_sha256(canonical_json(if (length(hashes)) as.list(hashes) else json_obj()))
  value = list(fp = fp, files = hashes)
  assign(key, list(stamp = stamp, value = value), envir = st$fingerprints)
  value
}

#' Records a trust decision with fingerprint `fp` (default the current one) and per-file hashes,
#' atomically under a short lock, keeping the other projects and the entry's other fields
#' @noRd
trust_store = function(root, trusted, fp = NULL) {
  fp = fp %||% trust_fingerprint(root)
  key = path_key(root)
  up = settings_file_update(trust_file(create = TRUE), function(x) {
    x = trust_read(x, strict = TRUE)
    rec = x[["projects"]][[key]]
    if (!settings_is_object(rec)) rec = list()
    rec$trusted = isTRUE(trusted)
    rec$date = with_calendar_preserved(format(Sys.Date()))
    rec$fingerprint = fp$fp
    rec$files = if (length(fp$files)) as.list(fp$files) else json_obj()
    x$version = x[["version"]] %||% 1L
    x$projects[[key]] = rec
    x
  })
  st = gateway_state()
  if (exists(key, envir = st$trust, inherits = FALSE)) rm(list = key, envir = st$trust)
  invisible(up$value[["projects"]][[key]])
}

#' Remembers a trust decision taken in this process with the fingerprint it was taken for; it
#' holds only while the gated files are unchanged (IC-52)
#' @noRd
trust_mark = function(root, decision, fp = NULL) {
  fp = fp %||% trust_fingerprint(root)
  assign(path_key(root), list(decision = isTRUE(decision), fp = fp$fp),
         envir = gateway_state()$trust)
  invisible(decision)
}

#' Which trust holds for a project root now: `record` (trust.json) and `live` (this process), each
#' only with a matching fingerprint, plus `fp`, the fingerprint checked (NULL when neither)
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

#' TRUE when the only change from fingerprint `before` to `after` is gptr's own write of gated file
#' `rel` with sha256 `hash` (IC-52: gptr's own writes re-fingerprint)
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

#' Moves the trust held before gptr's own write of gated file `path` (`was`, trust_holds()) to the
#' new fingerprint, recorded or in-process as it was, when nothing else changed (IC-52). Returns
#' TRUE when it carried a trust over, invisibly.
#' @noRd
trust_carry = function(root, was, path, hash) {
  if (!isTRUE(was$record) && !isTRUE(was$live)) return(invisible(FALSE))
  now = trust_fingerprint(root)
  if (!trust_own_write(was$fp, now, path_rel(path, root = root), hash)) return(invisible(FALSE))
  if (isTRUE(was$record)) trust_store(root, TRUE, now)
  if (isTRUE(was$live)) trust_mark(root, TRUE, now)
  invisible(TRUE)
}

#' TRUE when a recorded or in-process trust holds with a matching fingerprint (the `trust.get`
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
#' `project_trust` handlers, else the question, else untrusted with a notice (IC-52); a recorded
#' "no" stands until gptr_trust() changes it
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
    decision = isTRUE(gptr_confirm(paste0("Trust this project (its settings, skills, prompt ",
                                          "templates, agent files, extensions and MCP servers)?",
                                          what)))
    trust_store(root, decision, fp)
  } else {
    why = if (is.null(since)) "" else paste0(" (changed since you trusted it: ", since, ")")
    gptr_inform(paste0("Project resources in ", root, " were not loaded because the project is ",
                       "not trusted", why, ". Use gptr_trust(\".\", trust = TRUE) to trust it."),
                "notice",
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
#' `SYSTEM.md` and `APPEND_SYSTEM.md`, project `.env` discovery, provider base-URL overrides,
#' project skills (`.gptr/skills/`, `.agents/skills/`, `.claude/skills/` and relative
#' `skills.paths` entries), prompt templates (`.gptr/prompts/`), the tool and model fields of
#' project agent files, and the authority of project instructions. The
#' decision is kept in `tools::R_user_dir("gptr", "config")/trust.json` with a fingerprint of the
#' trust-gated files; when they change, the project counts as untrusted again until you confirm.
#' Called from model code during a run, recording a decision is refused.
#'
#' @param path A directory inside the project; its project root is used.
#' @param trust `NULL` to read the decision, `TRUE` or `FALSE` to record one.
#' @return With `trust = NULL`, the recorded decision: `TRUE`, `FALSE` or `NA` (undecided, also
#'   when a trust-gated file changed since the project was trusted). Otherwise the previous
#'   recorded decision, invisibly.
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
  # trust that lapsed with a changed gated file is asked again, like an undecided project
  if (is.null(trust)) return(if (isTRUE(prev) && !trust_holds(root)$record) NA else prev)
  session_control_check("gptr_trust")
  trust_store(root, trust)
  invisible(prev)
}

on_load(ext_service_set("trust.get", trust_get, provided_by = "P08", builtin = "gateway"))

# ------------------------------------------------------------------ settings layers (contract 11.2)

#' Looks a key up in one layer: a flat key first, else a dotted path into nested objects; a key
#' present with a JSON null is found (an explicit null is a value, contract 11.2)
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

#' Combines a lower and a higher layer: objects merge recursively, anything else (an array
#' included) is replaced, and a NULL in the higher layer removes the key
#' @noRd
settings_combine = function(lower, higher) {
  obj = function(x) is.list(x) && !is.object(x) && !is.null(names(x))
  if (!obj(lower) || !obj(higher)) return(higher)
  for (k in names(higher)[nzchar(names(higher))]) {
    v = higher[[k]]
    lower[k] = list(if (k %in% names(lower)) settings_combine(lower[[k]], v) else v)
    if (is.null(v)) lower[[k]] = NULL
  }
  lower
}

#' What one layer may contribute to a top-level key: in `providers`, `local_only` FALSE comes only
#' from a human layer (user file, session; another value there is TRUE); other layers keep only
#' TRUE, and an emptied provider entry is dropped (IC-74, 07 sections 2.1 and 5)
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

#' Applies one layer's contribution `add` (none once settings_guard() empties it) to `st`
#' (list(value, source)); the layer becomes the source of the top-level key
#' @noRd
settings_apply = function(st, key, add, layer, human) {
  g = settings_guard(key, add, human)
  if (is.list(add) && length(add) && is.list(g) && !length(g)) return(st)
  list(value = settings_combine(st$value, g), source = layer)
}

#' Applies the option or session entries of the dotted names from `key` down to `key.<path>`, less
#' specific first (IC-71), through settings_apply()
#' @noRd
settings_dotted = function(st, key, path, layer) {
  ses = the$settings_session %||% list()
  for (j in seq_along(path)) {
    name = paste(c(key, path[seq_len(j)]), collapse = ".")
    v = if (identical(layer, "option")) getOption(paste0("gptr.", name)) else ses[[name]]
    if (is.null(v)) next
    st = settings_apply(st, key, settings_nest(path[seq_len(j)], v), layer,
                        human = identical(layer, "session"))
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

#' The value a project settings file contributes (IC-52): tighten-type keys only tighten, except
#' that a trusted project sets `mode` to anything but yolo (D-250); permissions add deny and ask
#' rules (allow too when trusted); providers follow settings_project_providers(); other keys apply
#' only in a trusted project
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
  if (trusted && identical(key, "mode")) {
    ok = is.character(new) && length(new) == 1L && new %in% setdiff(tighten, "yolo")
    return(if (ok) new else current)
  }
  if (!is.null(tighten)) {
    if (!is.character(new) || length(new) != 1L || !(new %in% tighten)) return(current)
    now = match(if (is.character(current)) current[1L] else NA, tighten)
    if (is.na(now)) now = match(spec$default, tighten)
    if (match(new, tighten) <= now) return(new)
    return(current)
  }
  if (!trusted) return(current)
  settings_combine(current, new)
}

#' The `providers` a project file contributes (contract 11.2, IC-74): untrusted, only a tighter
#' `local_only`; trusted, its entries, with a `base_url` only once the user confirmed it
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

#' TRUE when a trusted project's `providers.<id>.base_url` may be used (it decides where the
#' credentials go, architecture 6.5): confirmed once, kept in trust.json when the trust is
#' recorded, else for this process; without someone to ask, not used
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
  key = path_key(root)
  settings_file_update(trust_file(create = TRUE), function(x) {
    x = trust_read(x, strict = TRUE)
    rec = x[["projects"]][[key]]
    if (!is.list(rec) || !isTRUE(rec[["trusted"]])) return(NULL)
    done = rec[["base_url_confirmed"]]
    if (!settings_is_object(done)) done = list()
    done[[id]] = url
    rec$base_url_confirmed = done
    x$projects[[key]] = rec
    x
  })
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

#' A top-level key through every layer, lowest to highest (contract 11.2); the source is the
#' highest layer that set or changed the top-level key. With `path`, `<key>.<path>` resolves inside
#' the object (a session object above a dotted option); a `scope = "user"` setting reads the user
#' file only.
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
  if (u$found) st = settings_apply(st, key, u$value, "user", human = TRUE)
  if (identical(spec$scope, "user")) return(done(st))
  ws = workspace_dir()
  if (!is.null(ws)) {
    root = project_root()
    p = settings_lookup(settings_file_read(file.path(ws, "settings.json")), key)
    perms = identical(key, "permissions")
    trusted = (p$found || perms) && isTRUE(trust_get(root))
    if (p$found) {
      nv = settings_project_value(key, spec, st$value, p$value, trusted, root)
      if (!identical(nv, st$value)) st = list(value = nv, source = "project")
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
  if (!is.null(opt)) st = settings_apply(st, key, opt, "option", human = FALSE)
  st = settings_dotted(st, key, path, "option")
  ses = settings_lookup(the$settings_session %||% list(), key)
  if (ses$found) st = settings_apply(st, key, ses$value, "session", human = TRUE)
  done(settings_dotted(st, key, path, "session"))
}

#' A key and the layer it came from; a dotted key resolves inside a protected top-level object, or
#' inside a setting when the dotted key is not registered itself
#' @noRd
settings_resolve = function(key) {
  parts = strsplit(key, ".", fixed = TRUE)[[1L]]
  if (length(parts) < 2L || !all(nzchar(parts))) return(settings_layered(key))
  inside = settings_protected(parts[1L]) ||
    (is.null(settings_spec(key)) && !is.null(settings_spec(parts[1L])))
  if (!inside) return(settings_layered(key))
  settings_layered(parts[1L], parts[-1L])
}

#' The effective value of a setting (the `settings.get` service behind setting_get()); `session`
#' is accepted for the signature, settings being process-wide
#' @noRd
settings_get = function(key, session = NULL) {
  check_string(key, "key")
  settings_resolve(key)$value
}

#' The protected local-only control of a provider (IC-74, 07 sections 2.1 and 5): FALSE only when
#' a human layer sets it FALSE and nothing above tightens it; read from the core `providers`
#' object. The `ollama_local_only` of a run's safety record.
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

# ------------------------------------------------------------- replay (contract 7.8; IC-30, IC-45)

#' The four replay modes
#' @noRd
replay_modes = function() c("auto", "replay", "live", "record")

#' The replay mode: `arg` > gptr.replay > GPTR_REPLAY > settings > "auto"; "replay" is forced when
#' R CMD check runs outside testthat (examples), unless `arg` is given (IC-45)
#' @noRd
replay_mode = function(arg = NULL) {
  if (!is.null(arg)) {
    mode = check_choice(arg, replay_modes(), "replay")
    return(mode)
  }
  if (check_running() && !identical(Sys.getenv("TESTTHAT"), "true")) return("replay")
  opt = getOption("gptr.replay")
  if (!is.null(opt)) {
    mode = check_choice(opt, replay_modes(), "gptr.replay")
    return(mode)
  }
  env = Sys.getenv("GPTR_REPLAY", "")
  if (nzchar(env)) {
    mode = check_choice(env, replay_modes(), "GPTR_REPLAY")
    return(mode)
  }
  set = settings_get("replay")
  if (is.character(set) && length(set) == 1L && !is.na(set) && set %in% replay_modes()) {
    return(set)
  }
  "auto"
}

#' The provider id of a model record, a provider spec or a reference (resolved without discovery,
#' IC-74); an unknown reference names the provider before its first `/`, or itself
#' @noRd
replay_provider_id = function(model) {
  if (inherits(model, "gptr_provider")) return(model[["id"]] %||% model[["name"]])
  pid = if (is.list(model)) model[["provider"]]
  if (is.character(pid) && length(pid) == 1L && !is.na(pid) && nzchar(pid)) return(pid)
  if (is.character(model) && length(model) == 1L && !is.na(model) && nzchar(model)) {
    m = model_resolve(model, strict = FALSE)
    if (!is.null(m)) return(m[["provider"]])
    slash = regexpr("/", model, fixed = TRUE)
    return(if (slash > 1L) substr(model, 1L, slash - 1L) else model)
  }
  gptr_abort("replay_guard() needs a model record, a provider spec or a model reference.",
             "invalid_argument", arg = "model", expected = "a model record or reference")
}

#' In replay `mode` (a call's `replay =` overrides the process mode, contract 3.1), refuses a
#' request to a provider whose record is not `offline = TRUE` (a local server is not); never
#' contacts a provider (07 sections 2.1 and 4)
#' @noRd
replay_guard = function(model, what = "model call", mode = replay_mode()) {
  check_string(what, "what")
  if (!identical(mode, "replay")) return(invisible(TRUE))
  pid = replay_provider_id(model)
  rec = if (inherits(model, "gptr_provider")) model else provider_get(pid)
  if (isTRUE(rec[["offline"]])) return(invisible(TRUE))
  gptr_abort(c(paste0("Replay mode: gptr may not make a ", what, " to ", pid,
                      " because nothing is recorded for it."),
               "Unset GPTR_REPLAY or pass replay = \"auto\" to call the model."),
             "not_recorded", document = NA_character_, prompt = NA_character_)
}

# ------------------------------------------- egress (03 section 6.10; IC-29, IC-43, IC-53, IC-74)

#' Does IC-74's local-only policy govern this provider's routes (as catalog_ollama_route())? Ollama,
#' or a provider of native Ollama decision models
#' @noRd
egress_ollama = function(p) {
  catalog_ollama_provider(p) || identical(p[["api"]], "ollama-system-one")
}

#' The safety record an egress decision reads by default: that of the run on this call stack (an
#' empty record, failing closed, when it holds none), NULL outside a run (07 section 5)
#' @noRd
egress_safety = function() {
  run = run_current()
  if (is.null(run)) return(NULL)
  run[["opts"]][["safety"]] %||% list()
}

#' Is local-only Ollama inference enforced for the next request? Yes unless the protected control
#' (settings_local_only()) or the run's frozen `safety` record relaxes it: an exemption needs both
#' @noRd
egress_local_only = function(safety = egress_safety()) {
  settings_local_only("ollama") && catalog_local_only(safety)
}

#' Where automatic context sent to provider record `p` goes: `exempt`, the effective `origin` and,
#' for a local provider not exempt, `why`. Offline is exempt; local only with a loopback endpoint
#' and, for Ollama, local-only enforced under `safety` (IC-74, D-020)
#' @noRd
egress_state = function(p, safety = egress_safety()) {
  if (!is.list(p)) return(list(exempt = FALSE, origin = NULL, why = NULL))
  ep = catalog_endpoint(p)
  out = list(exempt = FALSE, origin = ep[["origin"]], why = NULL)
  if (isTRUE(p[["offline"]])) {
    out$exempt = TRUE
  } else if (isTRUE(p[["local"]])) {
    out$why = if (is.null(ep)) {
      "It names no HTTP endpoint that shows it runs on this machine."
    } else if (!isTRUE(ep[["loopback"]])) {
      "Its endpoint is not a loopback address, so requests leave this machine."
    } else if (egress_ollama(p) && !egress_local_only(safety)) {
      paste0("Ollama's local-only inference is turned off, so a request through this server ",
             "may reach a cloud model.")
    }
    out$exempt = is.null(out$why)
  }
  out
}

#' Can the egress question be asked: someone can answer (IC-43) and the run's `safety` record says
#' `can_prompt = TRUE`; fails closed like P06's gate (IC-53 item 6)
#' @noRd
egress_can_ask = function(safety = egress_safety()) {
  if (!is.null(safety)) {
    ok = if (is.environment(safety)) {
      get0("can_prompt", envir = safety, inherits = FALSE)
    } else if (is.list(safety)) {
      safety[["can_prompt"]]
    }
    if (!isTRUE(ok)) return(FALSE)
  }
  gptr_can_prompt()
}

#' The question shown before the first automatic context or System 1 input goes to a provider
#' (gptr_confirm() appends the ` [y/N] ` hint itself); it names the effective endpoint when there
#' is one, and the model `asker` of a sub-agent that model code starts
#' @noRd
egress_question = function(id, origin = NULL, asker = NULL) {
  to = if (is.null(origin)) id else paste0(id, " (", origin, ")")
  lead = if (is.null(asker)) {
    paste0("gptr sends your prompts to ", to)
  } else {
    paste0("The agent's code starts a sub-agent on ", asker, ", which sends its prompt to ", to)
  }
  paste0(lead, " together with automatic context: the workspace listing (object names, classes ",
         "and sizes), the objects you added, changed or removed and the R expressions you ran ",
         "since the previous prompt (with the output of !code lines in peter()'s console), a ",
         "description of the R environment, project instructions and descriptions of the objects ",
         "you attach, and the inputs of System 1 questions (each vector element or data frame ",
         "row). Allow this for ", id, " from now on?")
}

#' Records `egress.<id> = "ack"` in the user settings file by one read-modify-write under its
#' short lock (IC-71); returns the file path, invisibly
#' @noRd
egress_record = function(id) {
  path = settings_path("user", create = TRUE)
  settings_file_update(path, function(cur) {
    acks = cur[["egress"]]
    if (!settings_is_object(acks)) acks = list()
    acks[[id]] = "ack"
    cur[["egress"]] = acks
    cur
  })
  invisible(path)
}

#' `invisible(TRUE)` when automatic context may go to `provider_id` (acknowledged, offline or a
#' local endpoint), judged on `provider`, the record the request uses (IC-29, IC-74; D-099,
#' D-114); else asks once when `safety` allows (IC-53) and records the answer, or
#' gptr_error_egress (13 C-34). Inside a run the question names `asker`, the model of the session
#' that model code starts.
#' @noRd
egress_check = function(provider_id, provider = provider_get(provider_id),
                        safety = egress_safety(), asker = NULL) {
  check_string(provider_id, "provider_id")
  pid = provider[["id"]] %||% provider[["name"]] %||% provider_id
  # the id is pasted into the hint the user is told to run, so it must be a plain provider id
  if (!rlang::is_string(pid) || !grepl("^[a-z0-9][a-z0-9-]*\\z", pid, perl = TRUE)) {
    gptr_abort("`provider_id` must be a provider id such as \"anthropic\".", "invalid_argument",
               arg = "provider_id", expected = "a provider id (^[a-z0-9][a-z0-9-]*$)")
  }
  st = egress_state(provider, safety)
  if (isTRUE(st$exempt)) return(invisible(TRUE))
  acks = settings_get("egress")
  if (is.list(acks) && identical(acks[[pid]], "ack")) return(invisible(TRUE))
  # gptr_config() merges top-level keys only, so the hint keeps the acknowledgements already given
  how = paste0("gptr_config(egress = utils::modifyList(gptr_config()$egress, list(`", pid,
               "` = \"ack\")), .scope = \"user\")")
  if (is.null(run_current())) asker = NULL
  if (egress_can_ask(safety) && isTRUE(gptr_confirm(egress_question(pid, st$origin, asker)))) {
    path = egress_record(pid)
    gptr_inform(paste0("Recorded that automatic context may go to ", pid, " (", path, ")."),
                "egress_ack")
    return(invisible(TRUE))
  }
  where = if (is.null(st$origin)) "" else paste0(" at ", st$origin)
  gptr_abort(c(paste0("gptr has not been told that it may send session context to ", pid, where,
                      "."),
               st$why,
               paste0("Acknowledge it once with ", how, ", or, except for a System 1 question, ",
                      "pass .opts = list(context = \"none\").")),
             "egress", provider = pid, how_to_ack = how)
}

# ------------------------------------------------------------------ gptr_config() (contract 6.2)

#' Settings keys that take bare identifiers
#' @noRd
settings_ident_keys = function() c("model", "small_model", "system1", "mode", "preset")

#' Resolves an identifier-valued setting to one name; the key is resolve_identifier()'s `arg`, so a
#' refusal names the setting
#' @noRd
settings_ident = function(expr, key, envir) {
  v = resolve_identifier(expr, key, envir)
  if (is.null(v)) return(NULL)
  if (!is.character(v) || length(v) != 1L) {
    gptr_abort(paste0("`", key, "` takes one name, as in gptr_config(", key, " = sonnet); ",
                      "register provider specs with gptr_register() and name them."),
               c("invalid_identifier", "invalid_argument"), arg = key,
               .data = list(class = class(v)[1L]))
  }
  v
}

#' Refuses a key gptr_config() may not set in `scope` and returns its spec: a dotted name below a
#' protected setting (IC-74, contract 11.2), or a `scope = "user"` setting outside user scope
#' @noRd
settings_config_key = function(key, scope) {
  top = strsplit(key, ".", fixed = TRUE)[[1L]][1L]
  if (!identical(top, key) && settings_protected(top)) {
    gptr_abort(paste0("`", key, "` is part of the protected setting `", top, "`, which is set ",
                      "as a whole object: gptr_config(", top, " = list(...), .scope = \"user\")."),
               "invalid_argument", arg = key, expected = paste0("the whole `", top, "` object"))
  }
  spec = settings_spec(key)
  if (identical(spec$scope, "user") && !identical(scope, "user")) {
    gptr_abort(paste0("`", key, "` can only be set at user scope: gptr_config(", key,
                      " = ..., .scope = \"user\")."), "invalid_argument", arg = ".scope",
               expected = "\"user\"")
  }
  spec
}

#' The provider ids whose `local_only` a validated `providers` object sets to FALSE
#' @noRd
settings_relaxed_ids = function(value) {
  if (!settings_is_object(value)) return(character())
  out = character()
  for (id in names(value)) {
    e = value[[id]]
    if (is.list(e) && identical(e[["local_only"]], FALSE)) out = c(out, id)
  }
  out
}

#' Checks a validated value before anything is written: `filters` in registry_filters_set()'s form
#' (04 10.1), no project `mode = yolo` (IC-78, D-250) and no project
#' `providers.<id>.local_only = FALSE` (IC-74, 07 section 5)
#' @noRd
settings_config_value = function(key, value, scope) {
  if (identical(key, "filters") && length(value) &&
      !all(grepl(registry_filter_rx, as.character(unlist(value)), perl = TRUE))) {
    gptr_abort(paste0("Invalid filter; use -builtin:<name>, -plugin:<name> or -<kind>:<name>, ",
                      "and a leading + to undo one."), "invalid_argument", arg = "filters",
               expected = "filters of the form -builtin:<name>, -plugin:<name>, -<kind>:<name>")
  }
  if (identical(key, "mode") && identical(value, "yolo") && identical(scope, "project")) {
    gptr_abort(c(paste0("A project cannot select mode yolo; only your user settings or this R ",
                        "session can."),
                 "Use gptr_config(mode = yolo, .scope = \"user\") or .scope = \"session\"."),
               "invalid_argument", arg = ".scope", expected = "\"user\" or \"session\"")
  }
  ids = if (identical(key, "providers") && identical(scope, "project")) {
    settings_relaxed_ids(value)
  } else {
    character()
  }
  if (length(ids)) {
    gptr_abort(c(paste0("A project cannot turn off local-only inference (", ids[1L],
                        ": local_only = FALSE); only your user settings or this R session can."),
                 paste0("Use gptr_config(providers = list(", ids[1L],
                        " = list(local_only = FALSE)), .scope = \"user\") or .scope = ",
                        "\"session\".")),
               "invalid_argument", arg = ".scope", expected = "\"user\" or \"session\"")
  }
  invisible(value)
}

#' Warns when keys just written to an untrusted project's file cannot apply there (IC-52): those
#' whose untrusted contribution (settings_project_value()) is not what trust would apply. Trusted,
#' `providers` applies as written, a `base_url` once confirmed (not asked here); of `permissions`
#' only the allow rules are dropped.
#' @noRd
settings_untrusted_warn = function(patch) {
  root = project_root()
  if (isTRUE(trust_get(root))) return(invisible())
  lost = character()
  for (k in names(patch)) {
    v = patch[[k]]
    if (is.null(v)) next
    if (identical(k, "permissions")) {
      if (length(unlist(v[["allow"]]))) lost = c(lost, "permissions.allow")
      next
    }
    sp = settings_spec(k)
    full = if (identical(k, "providers")) v else settings_project_value(k, sp, NULL, v, TRUE, root)
    if (!identical(settings_project_value(k, sp, NULL, v, FALSE, root), full)) lost = c(lost, k)
  }
  if (!length(lost)) return(invisible())
  gptr_warn(paste0("Saved to ", settings_path("project"), " but not applied while this project ",
                   "is not trusted: ", paste0("`", lost, "`", collapse = ", "), ". Trust it with ",
                   "gptr_trust(", encodeString(root, quote = "\""), ", trust = TRUE), or for this ",
                   "R session only pass .scope = \"session\"."),
            "untrusted_setting", keys = lost, path = root,
            .once = paste0("untrusted_setting:", path_key(root), ":", paste(lost, collapse = ",")))
}

#' Warns when a saved model setting names no model this session resolves; it is kept, since a
#' provider registered later or a catalog refresh can make it valid (04 6.1.3). Routers and the
#' `emulate:` prefix of `system1` are not models. Advisory: another error never fails the write.
#' @noRd
settings_model_warn = function(patch, scope) {
  for (k in intersect(names(patch), c("model", "small_model", "system1"))) {
    v = patch[[k]]
    if (is.null(v)) next
    ref = if (identical(k, "system1")) sub("^emulate:", "", v) else v
    if (!is.null(registry_get("router", ref))) next
    tryCatch(model_canonical(ref, strict = TRUE), gptr_error_unknown_model = function(e) {
      gptr_warn(paste0("`", k, "` = ", encodeString(v, quote = "\""), " was saved to the ", scope,
                       " settings, but gptr does not know that model in this session: ",
                       conditionMessage(e), " Undo with gptr_config(", k, " = NULL, .scope = \"",
                       scope, "\")."), "unknown_model_setting", key = k, ref = v)
    }, gptr_error = function(e) NULL)
  }
}

#' Show or change gptr's settings
#'
#' With no arguments, returns the effective settings with the layer each value came from:
#' package defaults < user `settings.json` < project `.gptr/settings.json` (an untrusted project
#' only tightens `mode`, `context`, `record`, permission rules and local-only inference; a trusted
#' one also sets `mode`, while `context` and `record` still only tighten) < the user-level project
#' file < `options(gptr.*)` < this R session. With named arguments, sets those keys in one scope.
#'
#' `model`, `small_model`, `system1`, `mode` and `preset` take bare names (`mode = plan`); `NULL`
#' removes a key from the scope. `egress` (the providers you allow automatic context to go to) is
#' accepted only at user scope. `mode = yolo` and turning off local-only Ollama inference
#' (`providers = list(ollama = list(local_only = FALSE))`) are accepted only at user or session
#' scope; a project can only keep local-only inference on. Called from model code during a run, it
#' is refused.
#'
#' The `"session"` scope means this R process, not one conversation. User settings live at
#' `tools::R_user_dir("gptr", "config")/settings.json`; project settings live in `.gptr/`.
#' A no-argument call always reads effective values, even when `.scope` is supplied. Inspect
#' `attr(gptr_config(), "sources")` to see their origins. Named lists merge with lower layers;
#' protected objects such as `providers` must be set as a whole named list.
#'
#' @section Choosing controls:
#' Use settings for defaults such as `model`, `mode`, `context`, `budget`, `record`, `replay`
#' and registered extension selections. Use [gptr_options] for transport timeouts, output caps,
#' undo retention and concurrency. Arguments to [peter()] choose values for one call, within
#' inherited safety restrictions. `vignette("configuration", package = "gptr")` groups all
#' core settings and options and explains trust and scope.
#'
#' @param ... Named settings, e.g. `mode = manual`, `model = sonnet`, `budget = list(cost = 2)`.
#' @param .scope `NULL` (the project when a `.gptr/` workspace exists, else this session), or
#'   `"session"`, `"project"` or `"user"`.
#' @return Without arguments, a `gptr_config` list. Otherwise the previous values in that scope,
#'   invisibly (a named list; `NULL` where the key was unset).
#' @examples
#' old = gptr_config(mode = plan, .scope = "session")
#' gptr_config()$mode
#' gptr_config(mode = old$mode, .scope = "session")
#' @seealso [gptr_init()], [gptr_trust()], [gptr_permissions()] and [gptr_options].
#' @export
gptr_config = function(..., .scope = NULL) {
  scope = if (is.null(.scope)) {
    if (is.null(workspace_dir())) "session" else "project"
  } else {
    gateway_choice(.scope, c("session", "project", "user"), ".scope")
  }
  n = ...length()
  if (n == 0L) return(settings_effective())
  session_control_check("gptr_config")
  keys = ...names()
  if (is.null(keys) || anyNA(keys) || any(!nzchar(keys)) || anyDuplicated(keys)) {
    gptr_abort(paste("Every setting passed to gptr_config() needs a unique name,",
                     "as in gptr_config(mode = manual)."),
               "invalid_argument", arg = "...", expected = "uniquely named settings")
  }
  exprs = as.list(substitute(list(...)))[-1L]
  caller = parent.frame()
  known = settings_keys()
  patch = list()
  i = 1L
  while (i <= n) {
    k = keys[i]
    if (!k %in% known) {
      gptr_abort(paste0("`", k, "` is not a registered setting."), "invalid_argument", arg = k,
                 expected = "a registered setting (see gptr_config())")
    }
    spec = settings_config_key(k, scope)
    v = if (k %in% settings_ident_keys()) settings_ident(exprs[[i]], k, caller) else ...elt(i)
    if (!is.null(v) && is.function(spec$validate)) v = spec$validate(v)
    settings_config_value(k, v, scope)
    patch[k] = list(v)
    i = i + 1L
  }
  # previous values without a closure: this frame holds `...` (rule R3)
  cur = settings_read(scope)
  prev = vector("list", n)
  names(prev) = keys
  i = 1L
  while (i <= n) {
    if (!is.null(cur[[keys[i]]])) prev[keys[i]] = list(cur[[keys[i]]])
    i = i + 1L
  }
  settings_write(scope, patch)
  # 04 10.1: a filter path (P02 refuses per IC-53); files go through gateway_filters_sync()
  if ("filters" %in% keys) {
    if (identical(scope, "session")) {
      registry_filters_set(as.character(unlist(settings_read(scope)[["filters"]])), scope = scope)
    } else {
      gateway_filters_sync()
    }
  }
  if (identical(scope, "project")) settings_untrusted_warn(patch)
  settings_model_warn(patch, scope)
  invisible(prev)
}

#' Applies the `filters` of the user settings file and of a trusted project's file to P02's
#' registry (04 10.1), each scope only when its list changed since last applied; a rejected list
#' is a diagnostic and a one-time notice, never an error
#' @noRd
gateway_filters_sync = function() {
  st = gateway_state()
  applied = st$filters_applied %||% list()
  for (scope in c("user", "project")) {
    f = character()
    if (identical(scope, "user")) {
      f = as.character(unlist(settings_file_read(settings_path("user"))[["filters"]]))
    } else {
      ws = workspace_dir()
      if (!is.null(ws) && isTRUE(trust_get(project_root()))) {
        f = as.character(unlist(settings_file_read(file.path(ws, "settings.json"))[["filters"]]))
      }
    }
    if (identical(f, applied[[scope]] %||% character())) next
    applied[[scope]] = f
    tryCatch(registry_filters_set(f, scope = scope), error = function(e) {
      why = conditionMessage(e)
      registry_diagnostic("builtin:gateway", "settings", "filters_invalid",
                          paste0("the ", scope, " settings filters were not applied: ", why))
      gptr_inform(paste0("The filters of the ", scope, " settings file were not applied: ", why),
                  "notice", .once = paste0("filters_invalid:", scope, ":",
                                           paste(f, collapse = ",")))
    })
  }
  st$filters_applied = applied
  invisible(applied)
}

# ------------------------------------------------------------- gptr_init() (contract 6.2, 11.16)

#' The installed path of a file in inst/templates (empty string when missing)
#' @noRd
template_file = function(name) system.file("templates", name, package = "gptr")

#' Copies a template unless the target exists, with LF endings and a final newline (contract 11);
#' returns the sha256 of the bytes written (NULL when the target existed), invisibly
#' @noRd
template_copy = function(name, dest) {
  if (file.exists(dest)) return(invisible(NULL))
  src = template_file(name)
  if (!nzchar(src)) {
    gptr_abort(paste0("The template ", name, " is missing from the installed package."),
               "internal", detail = paste("inst/templates", name))
  }
  lines = as_utf8(readLines(src, warn = FALSE, encoding = "UTF-8"))
  bytes = if (length(lines)) charToRaw(paste0(paste(lines, collapse = "\n"), "\n")) else raw(0)
  write_atomic(dest, bytes)
  invisible(hash_sha256(bytes))
}

#' Writes .gptr/settings.json from its template unless it exists, under its short lock (IC-71),
#' keeping the trust that held before (trust_carry(); IC-52)
#' @noRd
init_settings = function(root, dest) {
  lock_with(dest, function() {
    was = trust_holds(root)
    hash = template_copy("settings.json", dest)
    if (!is.null(hash)) trust_carry(root, was, dest, hash)
    invisible(!is.null(hash))
  })
}

#' Offers `^\.gptr$` for .Rbuildignore in a package source; never writes it silently (13 2.3)
#' @noRd
init_rbuildignore = function(dir) {
  desc = file.path(dir, "DESCRIPTION")
  if (!file.exists(desc)) return(invisible(FALSE))
  if (!any(grepl("^Package:", readLines(desc, warn = FALSE, encoding = "UTF-8")))) {
    return(invisible(FALSE))
  }
  rb = file.path(dir, ".Rbuildignore")
  lines = if (file.exists(rb)) readLines(rb, warn = FALSE, encoding = "UTF-8") else character()
  line = "^\\.gptr$"
  if (line %in% trimws(lines)) return(invisible(FALSE))
  # gptr_confirm() appends the " [y/N] " hint
  ask = paste0("Add ", line, " to .Rbuildignore?")
  if (gptr_can_prompt() && isTRUE(gptr_confirm(ask))) {
    write_atomic(rb, c(lines, line))
    return(invisible(TRUE))
  }
  gptr_inform(paste0("This is a package source: add the line ", line, " to ", rb,
                     " so that R CMD build skips the workspace."), "notice")
  invisible(FALSE)
}

#' Create the project workspace `.gptr/`
#'
#' Creates `.gptr/` with `settings.json`, `skills/`, `agents/`, `prompts/`, and (by default) the
#' project-instructions file `vignette.Rmd` and `.gitignore`. Existing files are never
#' overwritten, so calling it again is safe. There is no default path: without `path` gptr asks
#' `Create .gptr/ in <project>? [y/N]` when you can answer, and signals an error otherwise.
#' Creating the workspace is consent to write there; it is not trust: gptr then asks separately
#' whether to trust the project, unless it is trusted already (see [gptr_trust()]). In a package
#' source it offers the `^\.gptr$` line for `.Rbuildignore` and never writes it silently.
#'
#' @param path The project directory (it must exist).
#' @param instructions Write `vignette.Rmd` from the template when it is absent.
#' @param gitignore Write `.gptr/.gitignore` from the template when it is absent.
#' @return The absolute path of `.gptr/`, invisibly (`NULL` when you declined).
#' @examples
#' d = tempfile("proj")
#' dir.create(d)
#' gptr_init(d)
#' list.files(file.path(d, ".gptr"), all.files = TRUE)
#' unlink(d, recursive = TRUE)
#' @export
gptr_init = function(path, instructions = TRUE, gitignore = TRUE) {
  check_flag(instructions, "instructions")
  check_flag(gitignore, "gitignore")
  session_control_check("gptr_init")
  if (missing(path)) {
    root = project_root()
    if (!gptr_can_prompt()) {
      gptr_abort(c("gptr_init() needs `path` when nobody can answer a question.",
                   "gptr only writes to directories that you name: gptr_init(\"<project dir>\")."),
                 "noninteractive", what = "gptr_init", questions = character())
    }
    if (!isTRUE(gptr_confirm(paste0("Create .gptr/ in ", root, "?")))) {
      return(invisible(NULL))
    }
    proj = root
  } else {
    proj = check_string(path, "path")
  }
  if (!dir.exists(proj)) {
    gptr_abort(paste0("The directory ", proj, " does not exist."), "invalid_argument",
               arg = "path", expected = "an existing directory")
  }
  proj = path_norm(proj)
  ws = file.path(proj, ".gptr")
  if (file.exists(ws) && !dir.exists(ws)) {
    gptr_abort(paste0(ws, " exists and is not a directory."), "workspace", path = ws)
  }
  if (!dir.exists(ws) && !dir.create(ws, showWarnings = FALSE)) {
    gptr_abort(paste0("Could not create ", ws, "."), "workspace", path = ws)
  }
  for (sub in c("skills", "agents", "prompts")) {
    dir.create(file.path(ws, sub), showWarnings = FALSE)
  }
  init_settings(proj, file.path(ws, "settings.json"))
  if (instructions) template_copy("vignette.Rmd", file.path(ws, "vignette.Rmd"))
  if (gitignore) template_copy("gitignore", file.path(ws, ".gitignore"))
  init_rbuildignore(proj)
  # `proj` itself: project_root() may return an IC-63 override, not the directory initialised
  held = trust_holds(proj)
  if (gptr_can_prompt() && !held$record && !held$live) {
    answer = isTRUE(gptr_confirm(paste0("Trust this project (its settings, skills, prompt ",
                                        "templates, agent files, extensions and MCP servers)?")))
    trust_store(proj, answer)
  }
  invisible(path_norm(ws))
}

#' Security considerations
#'
#' gptr runs a language model agent inside your R session. The agent reads files, writes files,
#' evaluates R code written by the model in the environment you give it and starts processes on
#' your behalf. This page describes what gptr does to keep those actions under your control and
#' where its protections end. [gptr_egress] describes what is sent to model providers.
#'
#' @section Everything happens because you asked:
#' When the package is loaded, it only stops the child processes that an earlier gptr session
#' left running after it was killed or crashed, and removes their records in
#' `tools::R_user_dir("gptr", "cache")`. A model is contacted only when you call [peter()] (or a
#' function that you give a prompt), and model-written code is evaluated only in the
#' environment you pass as `envir` (by default the frame that called [peter()]); gptr never
#' assigns into the global environment by itself. Files are written only into paths you pass to
#' a gptr function (for example `to` in [gptr_export()] or `paths` in [gptr_scrub()] with
#' `dry_run = FALSE`), inside the project's `.gptr/` directory once it exists (see
#' [gptr_init()]), inside `tools::R_user_dir("gptr")`, inside the session temporary directory,
#' into files you bound with [gptr_doc()] or confirmed, and by tool calls that the permission
#' mode allowed.
#'
#' @section Permission modes:
#' Every tool call passes a permission gate. The default mode is `manual`: actions that the
#' static classifier labels read-only run without asking; every other action it recognizes,
#' including a change to a file or an object, asks first with a one-line prompt. The classifier
#' is advisory, not a security boundary (see below). `edits` also allows file edits inside the
#' project and still asks before R code that is not known to be read-only; `auto`
#' asks only for level-4 actions (for example deleting the project directory or a file outside the
#' project, where a system temporary directory such as `/tmp` counts as outside, moving R's working
#' directory out of the project, or changing gptr's own configuration) and for reads of registered
#' secrets; `yolo`, which only you can select (a project setting or model code in another mode
#' cannot), also runs gptr's own configuration functions, writes to R startup files such as
#' `~/.Rprofile` (which can change gptr's options in the next R process) and secret reads without
#' asking, and still asks before deleting protected files, files outside the project or the
#' project itself, moving the working directory out of the project, `rm(list = ls())`,
#' `options(gptr.*)` and sending a secret over the network; `plan` changes nothing. In every mode
#' `r` code that calls `q()`, `readline()` or another function that would end, pause or hang your R
#' session is refused without a question. In `auto` and `yolo` mode a `system()` or `system2()`
#' call (on Windows also `shell()` or `shell.exec()`) whose command the code computes is refused
#' (see below). When nobody can answer a question (Rscript, knitr, a scheduled job) the run stops
#' with status `blocked` and a `gptr_error_permission` condition that says how to allow the action,
#' unless you set `options(gptr.noninteractive_ask = "deny")`. Model code cannot switch the gate
#' off or loosen it during a run: the safety options are copied when the run starts. Only the option
#' `gptr.unsafe_no_permissions`, set by you outside a run, removes the gate, and it is meant for
#' disposable sandboxes.
#'
#' Changing gptr's own configuration includes model code that sets or unsets an environment
#' variable gptr reads as configuration: a key or base-URL variable of a provider gptr has
#' registered (such as `AWS_REGION`, which places Bedrock's endpoint), or one that moves its
#' configuration folder or your home directory, such as `HOME`; [gptr_options] lists them. The
#' classifier reads such a change in `Sys.setenv()`, `Sys.unsetenv()`, `withr::local_envvar()` and
#' `withr::with_envvar()`, where a name it cannot read counts as one, in `readRenviron()` and
#' `dotenv::load_dot_env()`, and in an `os.environ` write in the code of `peter$py()` or
#' `peter$knit("python", code)` that names one in a string or an upper-case word, or whose name (a
#' subscript, or the first argument of `putenv()`, `unsetenv()` or `pop()`) is not a plain string
#' literal. It does not read code in a file R runs (`source()`, `sys.source()`,
#' `eval(parse(file = ))`); `Sys.setenv()` reached by a computed name, through a list or an
#' environment, or handed to another function (`get("Sys.setenv")`, `baseenv()$Sys.setenv`,
#' `with(list(f = Sys.setenv), ...)`, `assign("f", Sys.setenv)`, `identity(Sys.setenv)`); a Python
#' write that reaches `os.environ` by another name (`e = os.environ`, `getattr(os, "environ")`) or
#' through `ctypes`, or that passes `os.environ.update()` a mapping the code computes or keyword
#' names not all in upper case (on Windows `os.environ.update(home = d)` sets `HOME`); or Python run
#' through 'reticulate': such code is level 3 or lower, which `auto` runs without asking.
#'
#' @section What the gate cannot do:
#' The risk levels come from a static classifier ([gptr_risk()]). It is advisory and it is not a
#' security boundary: R code can compute function names, call compiled code or load packages
#' whose effects the classifier cannot see, and R has no sandbox for code that runs inside your
#' session. The classifier reads code as written and does not run it, so code that builds a call,
#' a name, a path or a command at run time, or reaches a function by another name, is read only
#' as far as the classifier can see; each form this page names as not read is of that kind. Deny
#' and ask `sh:` rules see a command computed at run time only in a `peter$sh()` or
#' `peter$bg()` call, which checks the command when it runs. So in `auto` and `yolo` mode a
#' `system()`, `system2()`, `shell()` or `shell.exec()` call whose command (for `system2()` also its
#' arguments and `env`) is not a string the classifier can read, such as
#' `cmd = paste("rm", "-rf", "build"); system(cmd)`, is refused, and the model is told to run the
#' command with `peter$sh()`; `manual` and `edits` ask. An allow rule such as `r(fn:system)` lets
#' such calls run, unchecked by `sh:` rules. Neither the rules nor the refusal read what a shell
#' reads when it runs: its standard input (`system("sh", input = cmd)`,
#' `peter$sh("sh", input = cmd)`), variables it expands (`sh -c "$X"`, `eval $X`) or a script file.
#' The refusal covers only calls the classifier resolves to these functions: a function reached by
#' a computed name or through a list or an environment (`get("system")(cmd)`,
#' `baseenv()$system(cmd)`) or handed to a function of your own (`g(system)`), `eval(parse())`, a
#' sourced file, package code and other command runners such as `pipe()` or `processx::run()`
#' still run a computed command unchecked. A literal command is read when it is given to
#' `system()`, `system2()`, `peter$sh()`, `processx::run()` (also as `callr::run()`),
#' `sys::exec_wait()`, `sys::exec_internal()` or `sys::exec_background()`, not when it is given to
#' `processx::process$new()`, which is level 3.
#'
#' Paths are placed in the project: a relative path in R code is read in the project directory, and
#' a command in the directory it runs in (after a `cd` or `env -C`, or the `wd` of `peter$sh()` or
#' `processx::run()`), the code a shell or Python runs there (`sh -c`, `cmd /c`, `pwsh -Command`,
#' `python3 -c`) included; running a command in a directory outside the project reads that
#' directory, so `manual` asks. `setwd()`, `withr::local_dir()`, `withr::with_dir()` and
#' `xfun::in_dir()` to a directory outside the project and R's session temporary directory, or to
#' one the code computes, are level 4, because a relative path would then name a file outside the
#' project, and so are `file.symlink()`, `file.link()` and `Sys.junction()` of a path outside the
#' project, as `ln` of one is. `getwd()` and the directory `setwd()` returns are read as the one the
#' code has moved R to, starting from R's working directory when the classifier reads the code, so
#' at the top level of the code `owd = setwd("data"); ...; setwd(owd)` stays in the project. A
#' drive-relative path such as `D:data` counts as outside on every OS. The classifier does not
#' follow the working directory changed in other ways (such as `usethis::local_project()`,
#' `get("setwd")` or the `wd` of `callr::r()`), nor read the code another interpreter runs
#' (`Rscript -e`, `perl -e`, `node -e`), a path the shell computes (`rm "$f"` in a loop, `xargs rm`)
#' or code handed to `sh -c` or `bash -c` as one word whose spaces are escaped with a backslash or
#' written `$IFS` (`sh -c rm\ -f\ file`): such a command is level 3, which `auto` and `yolo` run
#' without a question whatever it deletes. The `wd` of `processx::run()` is read when the call, or a
#' name the code assigns, holds it as a string; a `wd` the code computes is read as the project
#' directory.
#'
#' In `auto` and `yolo` mode a model can delete or overwrite files and objects. Use them only in
#' projects you can restore (version control, backups, [gptr_rewind()] for recent turns), and run
#' untrusted prompts or untrusted projects in a disposable container or virtual machine.
#'
#' @section Sub-agents, workers and child processes:
#' Inline sub-agents run in your session and see its objects. The worker backend runs a
#' sub-agent in a separate R process that starts from gptr's reduced child environment (it does
#' not read your `~/.Renviron`), but that process runs under your user account with your file
#' permissions: the worker backend is not an isolation boundary. Its permission requests are
#' sent to your session and classified again there. On the `codex` route Codex's own shell runs
#' commands in every mode without passing gptr's gate, rules or secret guard: in `plan`, `manual`
#' and `edits` its sandbox is read-only, so it can still read any file your account can read, and
#' in `auto` and `yolo` it also changes and deletes files inside the project within its sandbox.
#' MCP servers, the `claude` and `codex` command-line tools, shell
#' commands started with `peter$sh()` and Shiny artifacts are ordinary processes of your account
#' as well; artifacts start without any registered secret and listen
#' on the loopback interface, and each launch gets an access token in its address (on Windows
#' only when 'openssl' is installed; otherwise gptr says that the artifact has no token).
#'
#' @section Untrusted content:
#' Model replies, tool results, file contents, MCP results and project instruction files
#' (`AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`) are treated as data. Text from these sources
#' is never used as a formatting template, so braces in a reply cannot run R code. A project you
#' cloned is untrusted until you trust it with `gptr_trust(trust = TRUE)` (see [gptr_trust()]),
#' or answer yes when [gptr_init()] asks: until then its settings can only tighten
#' permissions, its extensions, plugins and MCP servers do not run, and its instruction files
#' are shown to the model as information rather than commands. When trusted files change after a
#' pull, gptr asks again.
#'
#' @section Secrets:
#' Keys are held in a private vault and appear in sessions, logs and errors only as markers such
#' as `[secret:ANTHROPIC_API_KEY]`. Values are redacted before anything is written or sent: the
#' session files, documents, caches, spill files, wire logs and the output of child processes.
#' gptr never reads the credential files of other tools. Reading a registered secret from model
#' code asks even in `auto` mode. A key registered after it already appeared in a file (for
#' example pasted into a prompt) can be removed from the files with [gptr_scrub()]; run
#' `gptr_scrub(error = TRUE)` before committing to fail when any registered secret remains.
#'
#' @section Data at rest and protected health information (PHI):
#' gptr keeps what it needs to resume and replay work. Review what you commit when the data are
#' personal or clinical:
#' - `.gptr/sessions/` (full conversations, including printed results) is excluded from git by
#'   the `.gptr/.gitignore` that [gptr_init()] writes.
#' - `.gptr/cache/s1/` holds System 1 answers and is committed by default so that a script
#'   replays without model calls. It stores a salted hash of each input and a hash of each
#'   question, never their text, but the answers themselves (a label and its probability)
#'   remain, and the salt is committed with the cache, so anyone with the repository can test
#'   guesses of short inputs. For PHI, stop committing it with
#'   `gptr_config(cache_commit = list(s1 = FALSE, s2 = FALSE), .scope = "project")` (gptr then
#'   keeps a `.gitignore` in `cache/s1/`), or clear it with `gptr_cache("clear", "s1")` before
#'   committing.
#' - `.gptr/cache/s2/` (answer text for replay), `.gptr/transcripts/` (console transcripts),
#'   `.gptr/checkpoints/` (pre-images of objects and files) and the data snapshots of artifacts
#'   (`.gptr/artifacts/<id>/v<n>/data/`) are excluded from git by default.
#' - `.gptr/plans/` (plans proposed in `plan` mode) and the `app.R` of each artifact are
#'   committed by default; they can quote data values the model saw.
#' - Documents you record into keep the model's code and up to `gptr.doc_output_lines` lines of
#'   printed output per step, which can contain data values. A console turn's block also keeps,
#'   as `#< ` lines, what its prompt was sent with, whatever that option says: the head of each
#'   `@file` (up to 40 lines) and the `!` code notes with their printed output. Review them before
#'   sharing.
#'
#' @section Local servers:
#' [gptr_mcp_serve()] exposes the live session to other agents over HTTP on `127.0.0.1` only,
#' with a random bearer token and an `Origin` check, and every call passes the permission gate.
#' Any local process that learns the token can call the served tools while the server runs; stop
#' it with `gptr_mcp_serve(stop = TRUE)` when you are done.
#'
#' @seealso [gptr_egress], [gptr_options], [gptr_permissions()], [gptr_trust()],
#'   [gptr_scrub()], [gptr_risk()].
#' @name gptr_security
NULL

#' Data egress: what gptr sends to model providers
#'
#' gptr sends data to a model provider only when you run a prompt with that provider's model, or
#' when model code that the permission mode allowed starts a sub-agent with that model. The package
#' itself collects nothing: there is no telemetry, no usage reporting and no network
#' access when the package loads. This page lists what a request contains so that you can decide
#' what may leave your machine.
#'
#' R tools compute on objects already in memory; a large dataset does not need to be uploaded
#' in full for a conversational agent to analyze it. Descriptions and tool results can still
#' contain data values. Native typed decision inputs use the separate encoding described below.
#'
#' @section What a request contains:
#' - Your prompt and the conversation so far.
#' - With summary context, a budgeted description of each attached object (its class,
#'   dimensions, column names and types and a few values); a small object can appear in full.
#' - Automatic context: a short listing of the objects in the evaluation environment (names,
#'   classes and sizes); the objects you added, changed or removed and the top-level R
#'   expressions you ran since the previous prompt (with the output of `!code` lines in the
#'   [peter()] console); the R version, platform and available packages; and the project
#'   instruction files (`AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`).
#' - Tool results: the printed output of R code the model ran, the parts of files it read, and
#'   images of plots it made. In `manual` mode every action that is not known to be read-only
#'   needs your approval before its result can be sent.
#'
#' A System 1 question (a classifier model such as Jev) sends the inputs themselves: each
#' element of a vector (text up to 100,000 characters), each row of a data frame as a record, a
#' description of larger objects, and for a piped session its last answer (at most
#' `gptr.s1_state_max` characters). Do not ask System 1 questions about data that may not leave
#' your machine.
#'
#' Registered secrets are replaced by markers before anything is sent.
#'
#' @section Limiting automatic context:
#' `.opts = list(context = "names")` sends workspace object names, the workspace changes and
#' attached-object headers, and `.opts = list(context = "none")` suppresses the workspace
#' listing, the workspace changes and attached-object descriptions.
#' Prompts, tool results and native typed decision inputs have their own paths. Attach only the
#' objects the task needs. The `plan` mode permits actions classified as read-only so you can
#' inspect a proposed workflow before allowing changes to your workspace.
#'
#' @section Acknowledgment:
#' The first time you use a provider (or a command-line route such as `claude_code` or `codex`)
#' in an interactive session, gptr shows what is sent and records your
#' acknowledgment in your user settings. A non-interactive run with a provider that was never
#' acknowledged stops with a `gptr_error_egress` condition. Record the acknowledgment once with
#' `gptr_config(egress = list(anthropic = "ack"), .scope = "user")` (this replaces the stored
#' list, so name every provider you use), or, except for System 1 questions, run with
#' `.opts = list(context = "none")`. Offline
#' providers such as [gptr_fake_provider()] and local providers on a loopback address need no
#' acknowledgment. An Ollama server can forward requests to cloud models, so Ollama is exempt only
#' while its local-only inference is on (the default; see `providers` in [gptr_config()]).
#'
#' @section Other network use:
#' gptr contacts nothing else on its own. The model catalog is refreshed only by
#' `gptr_models(refresh = TRUE)`, reachability checks run only with
#' `gptr_providers(check = TRUE)`, and MCP servers, sub-agents and command-line tools are
#' contacted only when a session uses them. The `claude` and `codex` command-line routes send
#' the conversation through those vendors' tools under their own terms.
#'
#' @seealso [gptr_security], [gptr_options], [gptr_providers()], [gptr_config()].
#' @name gptr_egress
NULL

# The cli-codex adapter (P20): one `codex exec --json --ignore-user-config ... -` per turn with the
# prompt on stdin, gptr's live R session through the stdio relay inst/gptr/mcp_relay.R (IC-79),
# the sandbox mapping with control-file hashing, the turn counter and the per-exec wall clock
# (architecture 8.3; contract 8.5, IC-65). L1: L0 helpers, the shared helpers of cli-common.R,
# P05's usage_new(), the injected opts and declared services only (IC-33). Adapted from the
# verified exec driver of report 08 section 5.1 (prompt on stdin through a looping writer, JSONL
# events of section 3.9) with the fixes of its verification log (items 14, 16, 54).
# Under a coaching role (`the$coach_role`, 08 section 3.7) every exec is confined: ephemeral,
# read-only, Codex's own tools switched off, gptr's hook in front of every tool, never resumed,
# and checked before its reply is kept.

#' A TOML basic string
#' @noRd
pcli_toml = function(x) paste0("\"", gsub("([\\\\\"])", "\\\\\\1", x), "\"")

#' The `-c` overrides that make gptr's stdio relay Codex's `gptr` MCP server (IC-65, IC-79):
#' `Rscript --vanilla <mcp_relay.R> <mailbox> <seconds>`, the paths as TOML basic strings; the
#' relay waits for an answer no longer than the turn's wall clock
#' @noRd
pcli_codex_mcp_args = function(dir) {
  relay = system.file("gptr", "mcp_relay.R", package = "gptr", mustWork = TRUE)
  argv = pcli_toml(c("--vanilla", relay, dir, as.character(pcli_turn_seconds())))
  c("-c", paste0("mcp_servers.gptr.command=", pcli_toml(rscript_path())),
    "-c", paste0("mcp_servers.gptr.args=[", paste(argv, collapse = ","), "]"),
    "-c", "mcp_servers.gptr.default_tools_approval_mode=\"approve\"",
    "-c", "mcp_servers.gptr.required=true",
    "-c", "mcp_servers.gptr.startup_timeout_sec=60",
    "-c", "mcp_servers.gptr.tool_timeout_sec=3600")
}

#' The Codex features a confined exec switches off (08 3.7)
#' @noRd
pcli_codex_off = c("shell_tool", "unified_exec_tty", "view_image", "multi_agent", "apps",
                   "plugins", "tool_suggest", "image_generation", "memories", "goals",
                   "sleep_tool", "skill_search", "browser_use", "computer_use")

#' The switches of a confined exec, also given to `codex features list` by the preflight: the
#' features above off, no web search, user questions, sub-agents or skills, none of Codex's extra
#' instructions, and no prompt history written
#' @noRd
pcli_codex_confine = c(
  rbind("--disable", pcli_codex_off),
  rbind("-c", c("web_search=\"disabled\"", "tools.experimental_request_user_input.enabled=false",
                "agents.enabled=false", "skills.bundled.enabled=false",
                "skills.include_instructions=false", "cloud.skills.enabled=false",
                "include_permissions_instructions=false", "include_environment_context=false",
                "include_apps_instructions=false", "history.persistence=\"none\"")))

#' The codex argv of IC-65: a new exec, or `exec resume` (which rejects -s and -C, so the sandbox
#' travels as `-c sandbox_mode=`); `relay` is the exec's private folder, the relay's mailbox
#'
#' Under a coaching `role` the exec is confined (08 3.7): ephemeral and read-only, Codex's own
#' tools off, gptr's hook for SessionStart and PreToolUse, and the person's credentials store.
#' A run keeps gptr's relay; a coach has none and gets the strict reply `schema` file.
#' @noRd
pcli_codex_args = function(model_id, wd, sandbox, relay, resume = NULL, role = NULL,
                           schema = NULL) {
  mcp = if (!identical(role, "coach")) pcli_codex_mcp_args(relay)
  if (!is.null(resume)) {
    return(c("exec", "resume", resume, "--json", "--ignore-user-config", "--skip-git-repo-check",
             "-m", model_id, mcp, "-c", paste0("sandbox_mode=", sandbox), "-"))
  }
  if (is.null(role)) {
    return(c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m", model_id,
             "-C", wd, mcp, "--sandbox", sandbox, "-"))
  }
  c("exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules",
    "--skip-git-repo-check", "-m", model_id, "-C", wd, mcp, "--sandbox", "read-only",
    pcli_codex_confine, pcli_codex_hooks(role, relay), pcli_codex_auth_store(),
    if (!is.null(schema)) c("--output-schema", schema), "-")
}

#' gptr's hook (inst/gptr/codex_hook.R) for SessionStart, which writes the start line, and
#' PreToolUse, which allows only gptr's tools in a run and nothing for a coach; its log is in the
#' exec's private folder. The command runs through Codex's shell (`$SHELL -c`; PowerShell or
#' cmd.exe on Windows, where a line with quotes does not run as written, so there it has none:
#' short paths), and the hook denies on stdout with status 0, which no shell changes; the bypass
#' flag runs it without Codex's persisted hook trust (08 3.7).
#' @noRd
pcli_codex_hooks = function(role, dir) {
  hook = system.file("gptr", "codex_hook.R", package = "gptr", mustWork = TRUE)
  paths = c(rscript_path(), hook, dir, dirname(system.file(package = "jsonlite")))
  win = pcli_is_windows()
  if (win) {
    paths = pcli_cmd_paths(paths) %||%
      gptr_abort(paste0("gptr cannot coach on Codex here: Codex runs gptr's hook through ",
                        "PowerShell or cmd.exe, and a path it needs (R, an R library or the ",
                        "session's temporary folder) holds a space or a sign they read and has ",
                        "no short (8.3) name. Move it to a path without them, or set TMPDIR to ",
                        "one."),
                 "model_refused", reason = "cli_preflight", cli = "codex")
  }
  argv = c(paths[[1L]], "--vanilla", paths[[2L]], role, file.path(paths[[3L]], "hook.log"),
           paths[[4L]])
  cmd = paste(if (win) argv else shQuote(argv, "sh"), collapse = " ")
  value = paste0("=[{hooks=[{type=\"command\",command=", pcli_toml(cmd), ",timeout=30}]}]")
  c("-c", paste0("hooks.SessionStart", value), "-c", paste0("hooks.PreToolUse", value),
    "--dangerously-bypass-hook-trust")
}

#' Windows paths that an unquoted PowerShell or cmd.exe line keeps whole: their short (8.3)
#' names with backslashes, or NULL when one still holds anything but letters, digits and `_.:\~-`
#' @noRd
pcli_cmd_paths = function(paths) {
  short = chartr("/", "\\", utils::shortPathName(paths))
  if (all(grepl("^[A-Za-z0-9_.:\\\\~-]+$", short))) short
}

#' The Codex home of the CLI's child environment: its CODEX_HOME, else ~/.codex
#' @noRd
pcli_codex_home = function() {
  home = child_env("cli-codex")["CODEX_HOME"]
  if (is.na(home) || !nzchar(home)) file.path(user_home(), ".codex") else unname(home)
}

#' `-c cli_auth_credentials_store=` from the person's `$CODEX_HOME/config.toml`, which
#' --ignore-user-config skips although a login kept in the OS keyring needs it (08 3.7). Only a
#' top-level line holding one of Codex's four values is read; anything else passes nothing.
#' @noRd
pcli_codex_auth_store = function() {
  f = file.path(pcli_codex_home(), "config.toml")
  text = if (file.exists(f)) tryCatch(read_utf8(f)$text, error = function(e) "") else ""
  lines = strsplit(text, "\n", fixed = TRUE)[[1L]]
  top = lines[cumsum(grepl("^[[:space:]]*\\[", lines)) == 0L]
  m = regmatches(top, regexec(paste0("^[[:space:]]*cli_auth_credentials_store[[:space:]]*=",
                                     "[[:space:]]*[\"']([a-z]+)[\"'][[:space:]]*(#.*)?$"), top))
  v = vapply(m, function(x) if (length(x)) x[[2L]] else NA_character_, "")
  v = v[v %in% c("file", "keyring", "auto", "ephemeral")]
  if (length(v)) c("-c", paste0("cli_auth_credentials_store=", pcli_toml(v[[1L]])))
}

#' The Codex part of the coaching preflight (08 3.7), after pcli_coach_preflight()'s version
#' floor: no `$CODEX_HOME/hooks.json` (the bypass flag would run its hooks too), and `codex
#' features list` with the confined switches, which makes no model call, reporting each
#' switched-off feature off and `hooks` on (an unknown feature name makes it fail, so a renamed
#' switch fails closed)
#' @return TRUE, invisibly; signals `gptr_error_model_refused` (reason `cli_preflight`).
#' @noRd
pcli_codex_preflight = function(path) {
  refuse = function(why) {
    gptr_abort(paste0("gptr cannot coach on this Codex CLI: ", why), "model_refused",
               reason = "cli_preflight", cli = "codex")
  }
  hooks = file.path(pcli_codex_home(), "hooks.json")
  if (file.exists(hooks)) {
    refuse(paste0(hooks, " exists, and the flag that runs gptr's hook would run its hooks ",
                  "too. Move the file aside to coach on Codex."))
  }
  res = pcli_run(path, c("features", "list", pcli_codex_confine))
  why = pcli_run_failure(res)
  if (!is.null(why)) refuse(paste0("`codex features list` ", why, " with gptr's switches."))
  lines = trimws(strsplit(res$stdout %||% "", "\n", fixed = TRUE)[[1L]])
  rows = strsplit(lines[nzchar(lines)], "[[:space:]]+")
  state = stats::setNames(vapply(rows, function(r) r[[length(r)]], ""),
                          vapply(rows, function(r) r[[1L]], ""))
  want = c(stats::setNames(rep("false", length(pcli_codex_off)), pcli_codex_off), hooks = "true")
  got = state[names(want)]
  wrong = names(want)[is.na(got) | got != want]
  if (length(wrong)) {
    refuse(paste0("with gptr's switches, `codex features list` shows ",
                  paste(wrong, collapse = ", "), " in the wrong state (each switched-off ",
                  "feature must read false, and the hook feature true)."))
  }
  invisible(TRUE)
}

#' A JSON Schema in OpenAI's strict form for `--output-schema` (08 3.7): every object lists all
#' its keys as required and allows no others, and a key that was optional becomes nullable.
#' Subschemas under any other keyword are converted too; gptr still validates the reply itself.
#' @noRd
pcli_codex_strict = function(x) {
  if (!is.list(x)) return(x)
  if (is.null(names(x))) return(lapply(x, pcli_codex_strict))
  for (k in setdiff(names(x), c("properties", "required", "enum", "const", "default",
                                "examples"))) {
    x[[k]] = pcli_codex_strict(x[[k]])
  }
  if (!("object" %in% unlist(x[["type"]]) || is.list(x[["properties"]]))) return(x)
  props = x[["properties"]]
  if (!length(props)) props = json_obj()
  req = as.character(unlist(x[["required"]]))
  for (k in names(props)) {
    p = pcli_codex_strict(props[[k]])
    props[[k]] = if (k %in% req) p else pcli_codex_nullable(p)
  }
  x$properties = props
  x$required = I(names(props))
  x$additionalProperties = FALSE
  x
}

#' A subschema that also admits null: "null" joins its type (and null its enum), else anyOf
#' @noRd
pcli_codex_nullable = function(x) {
  if (!is.list(x) || is.null(x[["type"]])) return(list(anyOf = list(x, list(type = "null"))))
  x$type = I(unique(c(as.character(unlist(x[["type"]])), "null")))
  if (!is.null(x[["enum"]])) x$enum = c(as.list(x[["enum"]]), list(NULL))
  x
}

#' Is Codex's native Windows sandbox ready? `codex sandbox windows` runs a no-op command in it
#' (08 6.2)
#'
#' An answer (an exit status) is cached per command and modification time next to the
#' capability probe, which pcli_version_forget() drops with it (gptr_providers(check = TRUE)).
#' So is a run that timed out, as not ready: build() runs the probe synchronously, and asking
#' again would hold every auto-mode exec for the 60 s timeout. A run that could not start or
#' ended without an exit status counts as not ready for this exec only and is not cached
#' (D-095, D-106).
#' @noRd
pcli_codex_windows_ready = function(path) {
  key = paste("windows-sandbox", pcli_cache_key(path))
  cache = pcli_cache$probe %||% list()
  hit = cache[[key]]
  if (!is.null(hit)) return(hit)
  res = tryCatch(pcli_run(path, c("sandbox", "windows", "cmd.exe", "/d", "/c", "exit", "0"),
                         timeout = 60), error = function(e) NULL)
  if (!is.list(res)) return(FALSE)
  status = suppressWarnings(as.integer(res$status))
  answered = length(status) == 1L && !is.na(status)
  if (!answered && !isTRUE(res$timed_out)) return(FALSE)
  hit = answered && !isTRUE(res$timed_out) && identical(status, 0L)
  cache[[key]] = hit
  pcli_cache$probe = cache
  hit
}

#' The sandbox of a permission mode: plan, manual and edits -> read-only (file changes go through
#' gptr's gated write/edit over MCP), auto and yolo -> workspace-write; on native Windows read-only
#' with a warning while the sandbox is not ready (IC-65)
#' @noRd
pcli_codex_sandbox = function(mode, path) {
  if (!mode %in% c("auto", "yolo")) return("read-only")
  if (pcli_is_windows() && !pcli_codex_windows_ready(path)) {
    gptr_warn(paste0("Codex's Windows sandbox is not ready, so the codex route runs read-only. ",
                     "Set the sandbox up with the Codex CLI to let Codex edit files itself."),
              "cli_sandbox", .once = "cli_sandbox_windows")
    return("read-only")
  }
  "workspace-write"
}

#' The stdin prompt: gptr's frozen instructions and the history on a fresh thread; on a resumed
#' thread the turns it has not seen (another model may have answered them, pcli_unseen()); the
#' new input always
#' @noRd
pcli_codex_prompt = function(context, fresh, provider = NULL) {
  parts = pcli_split(context[["messages"]] %||% list())
  input = pcli_input_text(parts$input)
  if (!fresh) return(paste0(pcli_history_text(pcli_unseen(parts$prior, provider)), input))
  sys = pcli_system_text(context)
  pre = if (nzchar(sys)) paste0("<gptr_instructions>\n", sys, "\n</gptr_instructions>\n\n") else ""
  paste0(pre, pcli_history_text(parts$prior), input)
}

#' Direct Windows directory entries, with readable-parent proof for fixed control names
#'
#' A missing directory is absent only when its readable parent does not list the entry.
#' R silently skips unreadable directories; both dot entries distinguish them from an empty
#' readable directory. Warnings are settled after the listing closes its native handle.
#' @noRd
pcli_control_entries = function(dir) {
  refuse = function() {
    gptr_abort("Could not inspect a control-file directory.", "io", operation = "list", path = dir)
  }
  dir = gsub("\\", "/", dir, fixed = TRUE)
  missing = NULL
  while (!dir.exists(dir)) {
    missing = basename(dir)
    parent = dirname(dir)
    if (identical(parent, dir) || !grepl("^([A-Za-z]:/|//)", parent)) refuse()
    dir = parent
  }
  seen = new.env(parent = emptyenv())
  seen$warning = FALSE
  entries = withCallingHandlers(tryCatch(list.files(dir, all.files = TRUE, no.. = FALSE),
    error = function(e) NULL), warning = function(w) {
      seen$warning = TRUE
      invokeRestart("muffleWarning")
    })
  if (seen$warning || !is.character(entries) || anyNA(entries) ||
      !all(c(".", "..") %in% entries)) refuse()
  if (!is.null(missing)) {
    if (tolower(missing) %in% tolower(entries)) refuse()
    return(character())
  }
  entries[!(entries %in% c(".", ".."))]
}

#' A Windows reparse marker when neither content nor followed-target metadata is observable
#'
#' The native query uses only the absolute system executable and the stripped helper profile.
#' Native reparse data is at most 16 KiB; reject undecidable or oversized decoded output and
#' retain only its SHA-256. proc_run owns the child and its redirected output files.
#' @noRd
pcli_control_reparse = function(path) {
  refuse = function() {
    gptr_abort("Could not inspect a Windows control-file reparse point.", "io",
               operation = "read", path = path)
  }
  root = gsub("\\", "/", Sys.getenv("SystemRoot", unset = ""), fixed = TRUE)
  root = sub("/+$", "", root)
  if (!grepl("^[A-Za-z]:/", root) || grepl("[[:cntrl:]]|(^|/)[.][.]?(/|$)", root) ||
      !dir.exists(root)) refuse()
  command = file.path(root, "System32", "fsutil.exe")
  if (!file.exists(command) || dir.exists(command)) refuse()
  res = tryCatch(proc_run(command, c("reparsepoint", "query", path), timeout = 5,
                          env = child_env("helper")), error = function(e) NULL)
  if (!is.list(res) || !identical(res$status, 0L) || !identical(res$timed_out, FALSE) ||
      !rlang::is_string(res$stdout) || !nzchar(res$stdout) ||
      nchar(res$stdout, type = "bytes") > 128L * 1024L ||
      !grepl("0x[[:xdigit:]]{8}\\b", res$stdout, perl = TRUE)) refuse()
  paste0("unreadable:reparse:", hash_sha256(res$stdout))
}

#' gptr's control files inside a project (IC-54), hashed around a workspace-write exec
#'
#' The listed directories' entries and the fixed files that exist, including symbolic links
#' whose target is gone (the listing keeps those inside the directories too, D-106).
#' @noRd
pcli_control_paths = function(root) {
  g = file.path(root, ".gptr")
  windows = is_windows()
  entries = if (windows) pcli_control_entries(g) else NULL
  settings = if (windows) {
    file.path(g, entries[grepl("^settings.*[.]json$", entries)])
  } else {
    list.files(g, pattern = "^settings.*[.]json$", full.names = TRUE)
  }
  fixed = c(settings, file.path(g, c("mcp.json", "SYSTEM.md", "APPEND_SYSTEM.md")),
            file.path(root, c(".Rprofile", "Rprofile.site", "Renviron.site")),
            file.path(root, ".git", "config"))
  listed = rep(FALSE, length(fixed))
  if (windows) {
    parents = unique(dirname(fixed))
    direct = lapply(parents, function(dir) {
      if (identical(dir, g)) entries else pcli_control_entries(dir)
    })
    listed = vapply(fixed, function(path) {
      tolower(basename(path)) %in% tolower(direct[[match(dirname(path), parents)]])
    }, logical(1))
  }
  dirs = c(file.path(g, c("extensions", "plugins", "agents")), file.path(root, ".git", "hooks"))
  dirs = dirs[dir.exists(dirs)]
  inside = unlist(lapply(dirs, list.files, recursive = TRUE, full.names = TRUE,
                         all.files = TRUE, no.. = TRUE), use.names = FALSE)
  link = nzchar(pcli_control_link(fixed))
  paths = unique(c(fixed[!dir.exists(fixed) & (file.exists(fixed) | link | listed)], inside))
  sort(path_norm(paths), method = "radix")
}

#' The targets of symbolic links ("" for anything else, and on a platform without them)
#' @noRd
pcli_control_link = function(paths) {
  out = tryCatch(Sys.readlink(paths), error = function(e) rep("", length(paths)))
  out[is.na(out)] = ""
  out
}

#' The content hash of one control file; one gptr cannot read gets a marker instead, so that
#' a change to the entry still shows: `link:<target>` for a gone link target, otherwise
#' `unreadable:<size> <modification time>` (D-106). When Windows exposes neither a target nor
#' finite followed-target metadata, query the native reparse data and retain only its digest.
#' An undecidable native query fails closed instead of treating two unknown entries as equal.
#' @noRd
pcli_control_digest = function(path) {
  tryCatch(as.character(hash_file(path)), error = function(e) {
    target = pcli_control_link(path)
    if (nzchar(target)) return(paste0("link:", target))
    info = tryCatch(path_info(path), error = function(e2) NULL)
    if (is_windows() && (is.null(info) || nrow(info) != 1L ||
        !is.finite(as.numeric(info$mtime)))) return(pcli_control_reparse(path))
    if (is.null(info) || nrow(info) != 1L) return("unreadable")
    paste0("unreadable:", info$size, " ", format(as.numeric(info$mtime), digits = 15))
  })
}

#' Content hashes of the control files, named by path
#' @noRd
pcli_control_hash = function(root = project_root()) {
  p = pcli_control_paths(root)
  if (!length(p)) return(stats::setNames(character(), character()))
  stats::setNames(vapply(p, pcli_control_digest, "", USE.NAMES = FALSE), p)
}

#' Control files added, removed or changed between two hash sets
#' @noRd
pcli_control_changed = function(before, after) {
  both = intersect(names(before), names(after))
  changed = c(setdiff(names(after), names(before)), setdiff(names(before), names(after)),
              both[before[both] != after[both]])
  sort(unique(changed), method = "radix")
}

#' The turn cap of an exec: the run's remaining turns, else gptr.max_turns (IC-65: Codex has no
#' turn-cap flag)
#'
#' Always a whole number of at least 1: a remaining budget that is not finite counts as none (as
#' for the claude flags, D-101), a value above the integer range is the largest integer, and a
#' gptr.max_turns that is not a positive number gives the default 50 (D-106).
#' @noRd
pcli_codex_cap = function(par) {
  whole = function(x) as.integer(max(1, min(floor(x), .Machine$integer.max)))
  turns = pcli_scalar_num(par[["turns"]])
  if (!is.null(turns)) return(whole(turns))
  max_turns = gptr_opt("max_turns")
  if (is.numeric(max_turns) && length(max_turns) == 1L && !is.na(max_turns) && max_turns > 0) {
    return(whole(max_turns))
  }
  50L
}

#' build(): one codex exec per turn, the prompt on stdin, then stdin closed (contract 8.1, 8.5)
#'
#' Each exec gets a fresh private mailbox for its relay (`codex_relay`, IC-79). A workspace-write
#' exec hashes the control files of the project root (`codex_control`, and the root as
#' `codex_root`); the session's earlier exec, if it ended unchecked, is checked first
#' (pcli_codex_settle()). P05's transport writes the prompt with write_all() and then closes
#' stdin. A fresh thread's prompt carries the instructions and the earlier conversation, so it
#' is not bounded: on Windows the write blocks until Codex has read it, which Codex does at
#' once, before its turn starts (D-019 item 5; D-106).
#'
#' Under a coaching role (`the$coach_role`: "run", else a coach) the exec is confined and never
#' resumed: an ephemeral thread is not stored, so each exec carries gptr's instructions and the
#' whole history. A coach's reply schema (`returns`) goes in strict form to `schema.json` in the
#' exec's private folder. coach_model_kind() ran the preflight before any coaching process
#' started; every session is checked (08 3.7).
#' @noRd
pcli_codex_build = function(model, context, opts) {
  state = pcli_state(opts)
  pcli_codex_settle(state)
  state$pcli_request_id = context[["request_id"]]
  pcli_track(opts[["session"]], state)
  path = pcli_find("codex")
  probe = pcli_probe(path)
  role = the$coach_role
  if (!is.null(role) && !identical(role, "run")) role = "coach"
  pcli_notice("codex")
  par = pcli_params(context)
  sandbox = if (is.null(role)) pcli_codex_sandbox(par$mode, path) else "read-only"
  relay = tempfile("gptr-codex-")
  dir.create(relay, mode = "0700")
  state$codex_relay = path_norm(relay)
  state$codex_role = role
  schema = NULL
  returns = context[["params"]][["returns"]]
  if (identical(role, "coach") && !is.null(returns)) {
    schema = file.path(state$codex_relay, "schema.json")
    write_utf8(schema, json_encode(pcli_codex_strict(returns)))
  }
  resume = if (isTRUE(probe$resume) && is.null(role)) state$codex_thread else NULL
  wd = path_norm(getwd())
  args = pcli_codex_args(pcli_model_id(model), wd, sandbox, state$codex_relay, resume = resume,
                         role = role, schema = schema)
  state$cli_api = "cli-codex"
  state$codex_sandbox = sandbox
  state$codex_cap = pcli_codex_cap(par)
  state$codex_control = NULL
  state$codex_root = NULL
  if (identical(sandbox, "workspace-write")) {
    root = project_root()
    state$codex_control = pcli_control_hash(root)
    state$codex_root = root
  }
  list(start = list(command = path[[1L]], args = c(as.character(path[-1L]), args),
                    env_profile = "cli-codex", env = character(), wd = wd),
       send = list(json_verbatim(pcli_codex_prompt(context, fresh = is.null(resume),
                                                  provider = model$provider))),
       close_stdin = TRUE)
}

#' Item types that are Codex tool steps (counted against the turn cap)
#' @noRd
pcli_codex_tool_kinds = c("mcp_tool_call", "command_execution", "file_change", "web_search",
                         "collab_tool_call")

#' The error text of an `error` or `turn.failed` event: `message`, or `error` as a string or as
#' an object with `message`; NULL when none is a nonempty string
#' @noRd
pcli_codex_why = function(obj) {
  err = obj[["error"]]
  why = pcli_chr(obj[["message"]]) %||% pcli_chr(err) %||%
    (if (is.list(err)) pcli_chr(err[["message"]]))
  if (is.null(why) || !nzchar(why)) NULL else why
}

#' Usage of turn.completed: input_tokens includes the cached ones (OpenAI semantics, 08 3.9), so
#' the record keeps the uncached part as `input`
#'
#' The counts are the thread's running totals, also in `codex exec resume`: with the adapter
#' `state`, an exec on the thread of the previous turn.completed (`codex_seen`) records the
#' increase of each count, an exec on another thread the whole (D-200).
#' IC-74 (07-local-ollama.md section 5; D-015 point 3): Codex reports no cost, so the cost is
#' unknown (NA), never a zero; a count Codex left out or reported malformed is unknown, and so is
#' an increase below zero and the uncached input when one of its parts is unknown or the parts
#' exceed the total. A reported cache-write count is all 5-minute writes (no 1-hour writes, as a
#' bare `cache_creation_input_tokens` of the claude CLI); without one both are unknown (D-106).
#' @noRd
pcli_codex_usage = function(u, state = NULL) {
  if (!is.list(u)) u = list()
  if (is.environment(state)) {
    seen = state$codex_seen
    state$codex_seen = list(thread = state$codex_thread, usage = u)
    if (!is.null(seen$thread) && identical(seen$thread, state$codex_thread)) {
      keys = c("input_tokens", "cached_input_tokens", "cache_write_input_tokens",
               "output_tokens", "reasoning_output_tokens")
      u = lapply(stats::setNames(nm = keys),
                 function(k) pcli_num(u[[k]]) - pcli_num(seen$usage[[k]]))
    }
  }
  cached = pcli_num(u[["cached_input_tokens"]])
  write = pcli_num(u[["cache_write_input_tokens"]])
  input = pcli_num(u[["input_tokens"]]) - cached - write
  if (!is.na(input) && input < 0) input = NA_real_
  usage_new(input = input, output = pcli_num(u[["output_tokens"]]), cache_read = cached,
            cache_write_5m = write, cache_write_1h = if (is.na(write)) NA_real_ else 0,
            reasoning = pcli_num(u[["reasoning_output_tokens"]]), cost = NULL)
}

#' Paths of a file_change item (entries without a path string name no file)
#' @noRd
pcli_codex_files = function(item) {
  changes = item[["changes"]]
  if (!is.list(changes)) return(character())
  paths = vapply(changes, function(ch) {
    (if (is.list(ch)) pcli_chr(ch[["path"]])) %||% ""
  }, "")
  paths[nzchar(paths)]
}

#' Informational tool name of a Codex item
#' @noRd
pcli_codex_tool_name = function(item) {
  switch(pcli_chr(item[["type"]]) %||% "",
         mcp_tool_call = paste0("mcp__", pcli_chr(item[["server"]]) %||% "?", "__",
                                pcli_chr(item[["tool"]]) %||% "?"),
         command_execution = "codex_shell", file_change = "codex_file_change",
         web_search = "codex_web_search", collab_tool_call = "codex_agent", "codex_item")
}

#' Emit the informational tool_execution_start/_end events of a Codex tool item (contract 8.5),
#' marked `informational` since the step runs outside R; calls of gptr's own tools are reported
#' where they run, mcp_serve_call() (D-192); a command's input drops the shell's `-lc` wrapper
#' of a single-quoted script or a bare word (D-207)
#' @noRd
pcli_codex_tool = function(s, item, phase) {
  kind = pcli_chr(item[["type"]]) %||% ""
  gptr_own = identical(kind, "mcp_tool_call") && identical(item[["server"]], "gptr")
  if (!(kind %in% pcli_codex_tool_kinds) || gptr_own) return(invisible(FALSE))
  emit = s$opts[["emit"]]
  if (!is.function(emit)) return(invisible(FALSE))
  id = paste0("codex_", pcli_chr(item[["id"]]) %||% "item")
  name = pcli_codex_tool_name(item)
  status = pcli_chr(item[["status"]])
  if (!(id %in% s$open_tools)) {
    s$open_tools = c(s$open_tools, id)
    arguments = item[["arguments"]]
    input = switch(kind,
                   command_execution = list(
                     command = sub("^\\S*sh -lc ('([^']*)'|([^\\s'\"\\\\]+))$", "\\2\\3",
                                   pcli_chr(item[["command"]]) %||% "", perl = TRUE)),
                   mcp_tool_call = if (is.list(arguments)) arguments else json_obj(),
                   file_change = list(paths = I(pcli_codex_files(item))),
                   web_search = list(query = pcli_chr(item[["query"]]) %||% ""), json_obj())
    emit(ev_new("tool_execution_start", tool_call_id = id, tool_name = name, input = input,
                informational = TRUE))
  }
  if (identical(phase, "end")) {
    failed = isTRUE(status %in% c("failed", "declined")) || !is.null(item[["error"]])
    emit(ev_new("tool_execution_end", tool_call_id = id, tool_name = name, is_error = failed,
                elapsed = NA_real_,
                details = list(status = status %||% NA_character_,
                               files = I(pcli_codex_files(item))), informational = TRUE))
  }
  invisible(TRUE)
}

#' The control-file check of the session's last workspace-write exec: the files added, removed
#' or changed since build() hashed them in its project root (`codex_root`, else the current
#' one), with that root as attribute `root`. The baseline is cleared first, so each exec is
#' checked once. Never signals: a check that failed gives no paths and the reason as attribute
#' `unchecked` (D-106).
#' @noRd
pcli_codex_check = function(state) {
  before = state$codex_control
  root = state$codex_root
  state$codex_control = NULL
  state$codex_root = NULL
  if (is.null(before)) return(character())
  tryCatch({
    root = root %||% project_root()
    structure(pcli_control_changed(before, pcli_control_hash(root)), root = root)
  }, error = function(e) structure(character(), unchecked = conditionMessage(e)))
}

#' Check, and warn about, the control files of the session's earlier workspace-write exec that
#' ended without the normaliser's own end, so it never reached pcli_codex_end()
#'
#' P05 lets go of an exec of an aborted or settled run without its normaliser
#' (stream_abort(), stream_detach()), and a stop of the child also cancels the exec's wall clock
#' (pcli_stop_child()). build() calls this before it takes the next baseline, so Codex's edits
#' are reported instead of absorbed into it; the changes may include edits made since that exec,
#' which the warning says. A no-op when the last exec was checked. Builtin:cli's `agent_end` and
#' `session_shutdown` hooks call it after pcli_stop_child(), so an aborted exec is
#' reported without waiting for the session's next one (D-106).
#' @noRd
pcli_codex_settle = function(state) {
  if (!is.environment(state) || is.null(state$codex_control)) return(invisible(character()))
  pcli_codex_warn(pcli_codex_check(state), earlier = TRUE)
}

#' Warn about changed control files once the exec has ended; the trust fingerprint of P08 then
#' treats changed trust-gated files as untrusted until confirmed. `earlier`: the check of an
#' earlier exec that ended unchecked (pcli_codex_settle()); paths are shown relative to the
#' root the exec ran in (attribute `root`)
#' @noRd
pcli_codex_warn = function(changed, earlier = FALSE) {
  why = attr(changed, "unchecked", exact = TRUE)
  if (!length(changed) && is.null(why)) return(invisible(changed))
  turn = paste0("Codex's ", if (isTRUE(earlier)) "earlier ", "workspace-write turn")
  what = if (is.null(why)) {
    root = attr(changed, "root", exact = TRUE) %||% project_root()
    paste0("control files changed since ", turn, " started: ",
           paste(path_rel(changed, root), collapse = ", "))
  } else {
    paste0("could not check its control files after ", turn, " (", why, ")")
  }
  gptr_warn(paste0("gptr ", what, ". Changed project settings, MCP servers, extensions and ",
                   "agents stay untrusted until you confirm them; review the project's R ",
                   "startup files and git hooks before you restart R."), "cli_sandbox")
  invisible(changed)
}

#' End an exec through `end()`, its terminal event: its relay ends and its private folder goes
#' first, so no reactor task outlives the turn, and the control files of a workspace-write exec
#' are checked first and reported after the event, also when `end()` fails (IC-54, IC-65; D-106)
#' @noRd
pcli_codex_end = function(s, end) {
  if (!is.null(s$relay)) reactor_cancel(s$relay)
  unlink(s$dir, recursive = TRUE)
  changed = pcli_codex_check(s$state)
  tryCatch(end(), finally = pcli_codex_warn(changed))
}

#' End an exec with the terminal error event; `kill` first stops the child (turn cap, wall clock,
#' an aborted run, an R error, a failed check), so the control files are checked once Codex can
#' no longer write them and the terminal event (whose done callback runs at once) finds it gone
#' (D-106). A provider error whose text, or the exec's last error, names a plan limit ends as
#' class `plan_limit` with the reset time Codex quoted (08 3.7).
#' @noRd
pcli_codex_error = function(s, class, text, reason = "error", status = NA_integer_,
                           kill = FALSE, usage = NULL) {
  if (kill) tryCatch(pcli_stop_child(s$state, wait_ack = FALSE), error = function(e) NULL)
  if (s$done) return(s$msg)
  resets = if (identical(class, "provider")) pcli_codex_limit(c(text, s$last_error))
  if (!is.null(resets)) class = "plan_limit"
  pcli_codex_end(s, function() {
    pcli_fail(s, class, text, reason = reason, status = status, usage = usage, resets_at = resets)
  })
}

#' The reset time of a Codex plan limit named in `texts`: the local time Codex quotes after "try
#' again at", NA when it gives none; NULL when no text names a usage limit, an empty workspace
#' credit or a spend cap (08 3.7)
#' @noRd
pcli_codex_limit = function(texts) {
  hit = texts[grepl("hit your usage limit|out of credits|spend cap", texts, ignore.case = TRUE)]
  if (!length(hit)) return(NULL)
  m = regmatches(hit[[1L]], regexec("try again at ([^.]+)[.]", hit[[1L]], ignore.case = TRUE))
  if (length(m[[1L]]) == 2L) m[[1L]][[2L]] else NA_character_
}

#' The kind of an item a confined exec may not report, or NULL: a coach may report only
#' messages, reasoning and warnings (`error` items), a run also calls of gptr's MCP server; any
#' other kind, a tool step or one Codex adds later, fails the check (08 3.7)
#' @noRd
pcli_codex_outside = function(s, item) {
  role = s$state$codex_role
  if (is.null(role)) return(NULL)
  kind = pcli_chr(item[["type"]]) %||% "untyped"
  gptr_call = identical(role, "run") && identical(kind, "mcp_tool_call") &&
    identical(item[["server"]], "gptr")
  if (kind %in% c("agent_message", "reasoning", "error") || gptr_call) NULL else kind
}

#' The log of gptr's Codex hook in an exec's private folder: whether its start line is there,
#' and the tools it denied, one per other line ("codex_tool" when a line names none), so a
#' garbled line counts against the session
#' @noRd
pcli_codex_hook_log = function(dir) {
  path = file.path(dir, "hook.log")
  text = if (file.exists(path)) tryCatch(read_utf8(path)$text, error = function(e) "") else ""
  lines = strsplit(text, "\n", fixed = TRUE)[[1L]]
  rows = lapply(lines[nzchar(lines)], function(x) tryCatch(json_decode(x), error = function(e) x))
  start = vapply(rows, function(r) is.list(r) && identical(r[["event"]], "start"), NA)
  denied = vapply(rows[!start], function(r) {
    (if (is.list(r)) pcli_chr(r[["tool_name"]])) %||% "codex_tool"
  }, "")
  list(start = any(start), denied = denied)
}

#' The checks of a confined exec whose turn completed (08 3.7), NULL when it passes: the bypass
#' warning proves the hook flag took effect, the hook's start line that the hook ran; a coach
#' must have no denial and exactly one message. A run's denials are reported as refused steps.
#' @noRd
pcli_codex_coach_check = function(s) {
  role = s$state$codex_role
  if (is.null(role)) return(NULL)
  if (!isTRUE(s$bypass)) {
    return(paste0("Codex did not confirm --dangerously-bypass-hook-trust, so gptr cannot tell ",
                  "that its hook was active; gptr discarded the session."))
  }
  log = pcli_codex_hook_log(s$dir)
  if (!log$start) {
    return("gptr's Codex hook never wrote its start line; gptr discarded the session.")
  }
  if (identical(role, "coach")) {
    if (length(log$denied)) {
      return(paste0("Codex tried to use a tool in a coaching session, which has none, and gptr's ",
                    "hook denied it (", paste(log$denied, collapse = ", "), "); gptr discarded ",
                    "the session."))
    }
    if (s$messages != 1L) {
      return(paste0("Codex sent ", s$messages, " messages, and a coaching session must send ",
                    "exactly one; gptr discarded the session."))
    }
    return(NULL)
  }
  emit = s$opts[["emit"]]
  if (!is.function(emit)) return(NULL)
  for (i in seq_along(log$denied)) {
    id = paste0("codex_hook_", i)
    emit(ev_new("tool_execution_start", tool_call_id = id, tool_name = log$denied[[i]],
                input = json_obj(), informational = TRUE))
    emit(ev_new("tool_execution_end", tool_call_id = id, tool_name = log$denied[[i]],
                is_error = TRUE, elapsed = 0, details = list(), informational = TRUE,
                refused = "gptr's Codex hook denied it: only gptr's tools may run"))
  }
  NULL
}

#' End an exec of an aborted run as aborted and stop it: once the terminal event has finished
#' P05's stream nothing else lets go of the child, and a workspace-write Codex would go on
#' editing unsupervised (D-106; as the claude adapter, D-104)
#' @noRd
pcli_codex_abort = function(s) {
  pcli_codex_error(s, "aborted", "The run was aborted.", reason = "aborted", kill = TRUE)
}

#' One completed item: text, a warning, reasoning, or a counted tool step
#' @noRd
pcli_codex_item = function(s, item) {
  kind = pcli_chr(item[["type"]]) %||% ""
  if (identical(kind, "agent_message")) {
    s$messages = s$messages + 1L
    pcli_text_block(s, item[["text"]] %||% "")
  } else if (identical(kind, "error")) {
    # a warning; the bypass flag always adds one
    text = pcli_chr(item[["message"]]) %||% ""
    if (grepl("--dangerously-bypass-hook-trust", text, fixed = TRUE)) s$bypass = TRUE
  } else if (identical(kind, "reasoning")) {
    text = trimws(pcli_chr(item[["text"]]) %||% "", "right")
    if (nzchar(text)) pcli_text_block(s, text, kind = "thinking")
  } else if (kind %in% pcli_codex_tool_kinds) {
    pcli_codex_tool(s, item, "end")
    s$items = s$items + 1L
    if (s$items > s$cap) {
      pcli_codex_error(s, "max_turns",
                      paste0("Codex exceeded the turn cap of this run (", s$cap,
                             " tool steps), so gptr stopped it."), kill = TRUE)
    }
  }
  invisible(NULL)
}

#' Dispatch one `codex exec --json` event (08 3.9). A top-level `error` event is noted, not
#' terminal (the verified driver of 08 5.1 records it and decides at `turn.failed` or the exit).
#' Fields are read only with the JSON types of 08 3.9; anything else is ignored or unknown.
#' A confined exec (08 3.7) is stopped at the first item outside gptr's tools, and its completed
#' turn is kept only when pcli_codex_coach_check() passes.
#' @noRd
pcli_codex_event = function(obj, s) {
  type = pcli_chr(obj[["type"]]) %||% ""
  item = obj[["item"]]
  if (!is.list(item)) item = list()
  outside = if (startsWith(type, "item.")) pcli_codex_outside(s, item)
  if (!is.null(outside)) {
    pcli_codex_error(s, "cli_check", paste0("Codex reported a ", outside, " step, which is ",
                                            "outside gptr's tools, so gptr stopped the session."),
                     kill = TRUE)
  } else if (identical(type, "thread.started")) {
    tid = pcli_sid(obj[["thread_id"]])
    if (!is.null(tid)) s$state$codex_thread = tid
    pcli_start(s)
  } else if (identical(type, "turn.started")) {
    pcli_start(s)
  } else if (identical(type, "item.started")) {
    pcli_start(s)
    pcli_codex_tool(s, item, "start")
  } else if (identical(type, "item.completed")) {
    pcli_start(s)
    pcli_codex_item(s, item)
  } else if (identical(type, "turn.completed")) {
    usage = pcli_codex_usage(obj[["usage"]], s$state)
    why = pcli_codex_coach_check(s)
    if (!is.null(why)) return(pcli_codex_error(s, "cli_check", why, usage = usage))
    pcli_codex_end(s, function() pcli_done(s, usage, "stop", "completed"))
  } else if (identical(type, "turn.failed")) {
    why = pcli_codex_why(obj) %||% s$last_error %||% "unknown error"
    pcli_codex_error(s, "provider", paste0("Codex reported an error: ", why))
  } else if (identical(type, "error")) {
    why = pcli_codex_why(obj)
    if (!is.null(why)) s$last_error = why
  }
  invisible(NULL)
}

#' The wall-clock limit of an exec passed: report and stop it (the words "out of budget" keep P06
#' from retrying the turn); in an aborted run the exec ends as aborted (D-104, D-106)
#' @noRd
pcli_codex_timeout = function(s) {
  if (pcli_aborted(s)) return(pcli_codex_abort(s))
  pcli_codex_error(s, "timeout", paste0("The codex exec is out of budget: it ran past the ",
                                       "per-turn limit of ", pcli_turn_seconds(),
                                       " s (option gptr.cli_turn_timeout)."), kill = TRUE)
}

#' The session side of the exec's stdio relay (IC-79): a reactor task of the run that answers each
#' request the relay leaves in the mailbox `dir` (`req`) through pcli_mcp() with `resp`, an empty
#' line for a notification. pcli_codex_end() ends it with the exec; a turn P05 let go of ends at
#' its next poll. Either removes the mailbox, which ends the relay.
#' @noRd
pcli_codex_relay = function(s, dir) {
  req = file.path(dir, "req")
  s$relay = reactor_task(function() {
    if (!pcli_turn_current(s)) {
      unlink(dir, recursive = TRUE)
      return(FALSE)
    }
    # a file just renamed can be locked for a moment on Windows: it is read at the next poll
    line = if (file.exists(req)) {
      tryCatch(read_utf8(req)$text, error = function(e) NULL, warning = function(w) NULL)
    }
    if (is.null(line)) return(0.02)
    unlink(req)
    msg = tryCatch(json_decode(line), error = function(e) NULL)
    if (!is.list(msg)) msg = list()
    pcli_mcp(msg, s, function(resp) {
      out = if (is.null(msg[["id"]])) "" else json_encode(resp)
      if (dir.exists(dir)) write_utf8(file.path(dir, "resp"), out)
    })
    0.02
  }, run = s$opts[["run"]])
}

#' parse(): the normaliser of one codex exec (contract 8.1, 8.5; pcli_normaliser()) and its relay
#' (pcli_codex_relay()). Every end checks the control files of a workspace-write exec
#' (pcli_codex_end()); an exec P05 ends without the normaliser is checked by the session's next
#' build() (pcli_codex_settle()).
#' @noRd
pcli_codex_parse = function(model, opts) {
  s = pcli_turn_new(model, opts)
  s$items = 0L
  s$open_tools = character()
  s$last_error = NULL
  s$messages = 0L
  s$bypass = FALSE
  s$dir = s$state$codex_relay
  s$cap = s$state$codex_cap %||% pcli_codex_cap(list())
  push = function(ev) {
    if (s$done) return(TRUE)
    obj = ev[["obj"]]
    if (!is.list(obj)) return(FALSE)
    if (pcli_aborted(s)) {
      pcli_codex_abort(s)
      return(TRUE)
    }
    pcli_codex_event(obj, s)
    s$done
  }
  exited = function() {
    paste0("codex exec exited before completing the turn.",
           if (!is.null(s$last_error)) paste0(" Its last error: ", s$last_error))
  }
  n = pcli_normaliser(s, "codex", push, pcli_codex_error, exited, function() pcli_codex_timeout(s))
  if (!is.null(s$dir) && !identical(s$state$codex_role, "coach")) pcli_codex_relay(s, s$dir)
  n
}

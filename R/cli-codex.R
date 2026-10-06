# The cli-codex adapter (P20): one `codex exec --json --ignore-user-config ... -` per turn with the
# prompt on stdin, gptr's live R session through gptr_mcp_serve() (the mcp.serve_ensure service
# of P18, a token bound to this session, IC-58), the sandbox mapping with control-file hashing,
# the turn counter and the per-exec wall clock (architecture 8.3; contract 8.5, IC-65). L1: L0
# helpers, the shared helpers of cli-common.R, P05's usage_new(), the injected opts and declared
# services only (IC-33). Adapted from the verified exec driver of report 08 section 5.1 (prompt
# on stdin through a looping writer, JSONL events of section 3.9) with the fixes of its
# verification log (items 14, 16, 54).

#' The `-c` overrides pointing Codex at gptr's MCP server (contract 8.5, verbatim)
#' @noRd
pcli_codex_mcp_args = function(port) {
  c("-c", paste0("mcp_servers.gptr.url=http://127.0.0.1:", as.integer(port), "/mcp"),
    "-c", "mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN",
    "-c", "mcp_servers.gptr.default_tools_approval_mode=\"approve\"",
    "-c", "mcp_servers.gptr.required=true",
    "-c", "mcp_servers.gptr.tool_timeout_sec=3600")
}

#' The codex argv of IC-65: a new exec, or `exec resume` (which rejects -s and -C, so the sandbox
#' travels as `-c sandbox_mode=`)
#' @noRd
pcli_codex_args = function(model_id, wd, sandbox, port = NULL, resume = NULL) {
  mcp = if (is.null(port)) character() else pcli_codex_mcp_args(port)
  if (is.null(resume)) {
    return(c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m", model_id,
             "-C", wd, mcp, "--sandbox", sandbox, "-"))
  }
  c("exec", "resume", resume, "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
    model_id, mcp, "-c", paste0("sandbox_mode=", sandbox), "-")
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
#' gptr's gated write/edit over MCP), auto -> workspace-write; on native Windows read-only with a
#' warning while the sandbox is not ready (IC-65)
#' @noRd
pcli_codex_sandbox = function(mode, path) {
  if (!identical(mode, "auto")) return("read-only")
  if (pcli_is_windows() && !pcli_codex_windows_ready(path)) {
    gptr_warn(paste0("Codex's Windows sandbox is not ready, so the codex route runs read-only. ",
                     "Set the sandbox up with the Codex CLI to let Codex edit files itself."),
              "cli_sandbox", .once = "cli_sandbox_windows")
    return("read-only")
  }
  "workspace-write"
}

#' Say once that Codex works on files only (no MCP server: httpuv, later or openssl missing)
#' @noRd
pcli_codex_files_only = function(why) {
  gptr_inform(paste0("Codex cannot evaluate R in this session (", why, "); the codex route ",
                     "works on files only. Install httpuv, later and openssl for live R access."),
              "notice", .once = "cli_codex_files_only")
  NULL
}

#' The child-environment addition of the handle: GPTR_MCP_TOKEN, taken from its Codex client
#' snippet (`$config$codex$env`, 04 5.11: the token lives only in child environments and in
#' snippets); empty when the handle has none
#' @noRd
pcli_codex_env = function(h) {
  if (is.null(h)) return(character())
  name = h$token_env %||% "GPTR_MCP_TOKEN"
  env = h$config$codex$env
  tok = if (is.null(env)) NULL else env[[name]]
  if (rlang::is_string(tok) && nzchar(tok)) c(GPTR_MCP_TOKEN = tok) else character()
}

#' Ensure gptr's MCP server for a session and keep what its next codex exec needs:
#' list(url, port, env = c(GPTR_MCP_TOKEN = <this session's token>)) (mcp.serve_ensure, IC-58),
#' or list(error) when there is no server or no token
#'
#' Called by builtin:cli's `request_params` hook with the session object, which the service
#' takes (P18 checks its class) while the adapter holds only ids (contract 8.1). Only strings
#' are kept, per session id, never the handle (its stop() would keep the session alive);
#' session_shutdown forgets them (pcli_codex_forget()).
#' @param session a gptr_session (anything with an `$id`).
#' @return invisible(the record kept), or invisible(NULL) without a session id.
#' @noRd
pcli_codex_ensure = function(session) {
  id = pcli_sid(tryCatch(session$id, error = function(e) NULL))
  if (is.null(id)) return(invisible(NULL))
  rec = if (!ext_service_has("mcp.serve_ensure")) {
    list(error = "gptr's MCP server is not loaded")
  } else {
    tryCatch({
      h = ext_service_get("mcp.serve_ensure")(session)
      env = pcli_codex_env(h)
      if (length(env)) {
        list(url = h$url, port = h$port, env = env)
      } else {
        list(error = "the MCP server gave no token for this session")
      }
    }, error = function(e) list(error = conditionMessage(e)))
  }
  tab = pcli_cache$mcp %||% list()
  tab[[id]] = rec
  pcli_cache$mcp = tab
  invisible(rec)
}

#' Forget the MCP record of a session (its session_shutdown)
#' @noRd
pcli_codex_forget = function(session) {
  tab = pcli_cache$mcp %||% list()
  if (!is.null(pcli_sid(session))) tab[[session]] = NULL
  pcli_cache$mcp = tab
  invisible(NULL)
}

#' The MCP record of this request's session (pcli_codex_ensure()), or NULL with the one-time
#' files-only notice
#' @noRd
pcli_codex_mcp = function(opts) {
  sid = pcli_sid(opts[["session"]])
  rec = if (is.null(sid)) NULL else (pcli_cache$mcp %||% list())[[sid]]
  if (is.null(rec)) {
    return(pcli_codex_files_only("gptr's MCP server was not started for this session"))
  }
  if (!is.null(rec$error)) return(pcli_codex_files_only(rec$error))
  rec
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

#' gptr's control files inside a project (IC-54), hashed around a workspace-write exec
#'
#' The listed directories' entries and the fixed files that exist, including symbolic links
#' whose target is gone (the listing keeps those inside the directories too, D-106).
#' @noRd
pcli_control_paths = function(root) {
  g = file.path(root, ".gptr")
  fixed = c(list.files(g, pattern = "^settings.*[.]json$", full.names = TRUE),
            file.path(g, c("mcp.json", "SYSTEM.md", "APPEND_SYSTEM.md")),
            file.path(root, c(".Rprofile", "Rprofile.site", "Renviron.site")),
            file.path(root, ".git", "config"))
  dirs = c(file.path(g, c("extensions", "plugins", "agents")), file.path(root, ".git", "hooks"))
  dirs = dirs[dir.exists(dirs)]
  inside = unlist(lapply(dirs, list.files, recursive = TRUE, full.names = TRUE,
                         all.files = TRUE, no.. = TRUE), use.names = FALSE)
  link = nzchar(pcli_control_link(fixed))
  paths = unique(c(fixed[!dir.exists(fixed) & (file.exists(fixed) | link)], inside))
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
#' hashing never fails and a change to the entry still shows: `link:<target>` for a link whose
#' target is gone, else `unreadable:<size> <modification time>` (D-106). R reads no link target
#' on Windows, where `file.info()` of a dangling link also warns; the marker says it already.
#' @noRd
pcli_control_digest = function(path) {
  tryCatch(as.character(hash_file(path)), error = function(e) {
    target = pcli_control_link(path)
    if (nzchar(target)) return(paste0("link:", target))
    info = tryCatch(suppressWarnings(file.info(path, extra_cols = FALSE)),
                    error = function(e2) NULL)
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
#' A workspace-write exec hashes the control files of the project root (`codex_control`, and
#' the root as `codex_root`); the session's earlier exec, if it ended unchecked, is checked first
#' (pcli_codex_settle()). P05's transport writes the prompt with write_all() and then closes
#' stdin. A fresh thread's prompt carries the instructions and the earlier conversation, so it
#' is not bounded: on Windows the write blocks until Codex has read it, which Codex does at
#' once, before its turn starts (D-019 item 5; D-106).
#' @noRd
pcli_codex_build = function(model, context, opts) {
  state = pcli_state(opts)
  pcli_codex_settle(state)
  state$pcli_request_id = context[["request_id"]]
  pcli_track(opts[["session"]], state)
  path = pcli_find("codex")
  probe = pcli_probe(path)
  pcli_notice("codex")
  par = pcli_params(context)
  sandbox = pcli_codex_sandbox(par$mode, path)
  h = pcli_codex_mcp(opts)
  port = h$port
  resume = if (isTRUE(probe$resume)) state$codex_thread else NULL
  wd = path_norm(getwd())
  args = pcli_codex_args(pcli_model_id(model), wd, sandbox, port = port, resume = resume)
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
  run = opts[["run"]]
  if (!is.null(port) && rlang::is_string(run)) {
    reactor_served(run, TRUE)
    state$served_run = run
  }
  list(start = list(command = path[[1L]], args = c(as.character(path[-1L]), args),
                    env_profile = "cli-codex", env = h$env %||% character(), wd = wd),
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
#' IC-74 (07-local-ollama.md section 5; D-015 point 3): Codex reports no cost, so the cost is
#' unknown (NA), never a zero; a count Codex left out or reported malformed is unknown, and so is
#' the uncached input when one of its parts is unknown or the parts exceed the total. A reported
#' cache-write count is all 5-minute writes (no 1-hour writes, as a bare
#' `cache_creation_input_tokens` of the claude CLI); without one both are unknown (D-106).
#' @noRd
pcli_codex_usage = function(u) {
  if (!is.list(u)) u = list()
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

#' Emit the informational tool_execution_start/_end events of a Codex tool item (contract 8.5)
#' @noRd
pcli_codex_tool = function(s, item, phase) {
  kind = pcli_chr(item[["type"]]) %||% ""
  if (!(kind %in% pcli_codex_tool_kinds)) return(invisible(FALSE))
  emit = s$opts[["emit"]]
  if (!is.function(emit)) return(invisible(FALSE))
  id = paste0("codex_", pcli_chr(item[["id"]]) %||% "item")
  name = pcli_codex_tool_name(item)
  status = pcli_chr(item[["status"]])
  if (!(id %in% s$open_tools)) {
    s$open_tools = c(s$open_tools, id)
    arguments = item[["arguments"]]
    input = switch(kind,
                   command_execution = list(command = pcli_chr(item[["command"]]) %||% ""),
                   mcp_tool_call = if (is.list(arguments)) arguments else json_obj(),
                   file_change = list(paths = I(pcli_codex_files(item))),
                   web_search = list(query = pcli_chr(item[["query"]]) %||% ""), json_obj())
    emit(ev_new("tool_execution_start", tool_call_id = id, tool_name = name, input = input))
  }
  if (identical(phase, "end")) {
    failed = isTRUE(status %in% c("failed", "declined")) || !is.null(item[["error"]])
    emit(ev_new("tool_execution_end", tool_call_id = id, tool_name = name, is_error = failed,
                elapsed = NA_real_,
                details = list(status = status %||% NA_character_,
                               files = I(pcli_codex_files(item)))))
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
#' `session_shutdown` hooks (Task 9) can call it after pcli_stop_child(), so an aborted exec is
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

#' End an exec through `end()`, its terminal event: the control files of a workspace-write exec
#' are checked first and reported after the event, also when `end()` fails (IC-54, IC-65; D-106)
#' @noRd
pcli_codex_end = function(s, end) {
  changed = pcli_codex_check(s$state)
  tryCatch(end(), finally = pcli_codex_warn(changed))
}

#' End an exec with the terminal error event; `kill` first stops the child (turn cap, wall clock,
#' an aborted run, an R error), so the control files are checked once Codex can no longer write
#' them and the terminal event (whose done callback runs at once) finds it gone (D-106)
#' @noRd
pcli_codex_error = function(s, class, text, reason = "error", status = NA_integer_,
                           kill = FALSE) {
  if (kill) tryCatch(pcli_stop_child(s$state, wait_ack = FALSE), error = function(e) NULL)
  if (s$done) return(s$msg)
  pcli_codex_end(s, function() pcli_fail(s, class, text, reason = reason, status = status))
}

#' End an exec of an aborted run as aborted and stop it: once the terminal event has finished
#' P05's stream nothing else lets go of the child, and a workspace-write Codex would go on
#' editing unsupervised (D-106; as the claude adapter, D-104)
#' @noRd
pcli_codex_abort = function(s) {
  pcli_codex_error(s, "aborted", "The run was aborted.", reason = "aborted", kill = TRUE)
}

#' One completed item: text, reasoning, or a counted tool step
#' @noRd
pcli_codex_item = function(s, item) {
  kind = pcli_chr(item[["type"]]) %||% ""
  if (identical(kind, "agent_message")) {
    pcli_text_block(s, item[["text"]] %||% "")
  } else if (identical(kind, "reasoning")) {
    pcli_text_block(s, item[["text"]] %||% "", kind = "thinking")
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
#' @noRd
pcli_codex_event = function(obj, s) {
  type = pcli_chr(obj[["type"]]) %||% ""
  item = obj[["item"]]
  if (!is.list(item)) item = list()
  if (identical(type, "thread.started")) {
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
    usage = pcli_codex_usage(obj[["usage"]])
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

#' parse(): the normaliser of one codex exec (contract 8.1, 8.5; pcli_normaliser()). Every end
#' checks the control files of a workspace-write exec (pcli_codex_end()); an exec P05 ends
#' without the normaliser is checked by the session's next build() (pcli_codex_settle()).
#' @noRd
pcli_codex_parse = function(model, opts) {
  s = pcli_turn_new(model, opts)
  s$items = 0L
  s$open_tools = character()
  s$last_error = NULL
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
  pcli_normaliser(s, "codex", push, pcli_codex_error, exited, function() pcli_codex_timeout(s))
}

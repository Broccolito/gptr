# ext-events.R -- the event catalogue (contract 10.4) and dispatch (contract 7.2, 10.7).
# Event names follow D-25 / IC-03: Pi names where the semantics match, gptr names otherwise.
# Claude and Codex hook names are refused with a hint (report G1 3.2; the v1.x importer maps
# them). Semantics are encoded as notify, collect, transform (chain), decision, first_decision,
# patch (chain) and block_patch.

#' One row of the event catalogue
#' @noRd
ev_row = function(event, semantics, payload, returns = "", origin = "pi", fail_closed = FALSE) {
  data.frame(event = event, semantics = semantics, fail_closed = fail_closed, payload = payload,
             returns = returns, origin = origin, stringsAsFactors = FALSE)
}

#' The event catalogue of contract 10.4 (46 events)
#' @noRd
ev_table = rbind(
  ev_row("project_trust", "first_decision", "cwd, changed",
         "list(decision = \"yes\" | \"no\", remember)"),
  ev_row("resources_discover", "collect", "cwd, reason",
         "list(skill_paths, prompt_paths, agent_paths)"),
  ev_row("session_start", "collect", "reason", "list(sections, blocks)"),
  ev_row("session_before_fork", "first_decision", "source, at", "list(cancel = TRUE, reason)"),
  ev_row("session_shutdown", "notify", "reason"),
  ev_row("input", "transform", "text, source",
         "list(action = \"continue\" | \"transform\" | \"handled\", text)"),
  ev_row("agent_start", "notify", ""),
  ev_row("agent_end", "notify", "status, reason, usage, doc, turns"),
  ev_row("turn_start", "notify", ""),
  ev_row("turn_end", "notify", "message, results"),
  ev_row("before_request", "notify", "provider, model, request_id, view, tokens_est",
         origin = "gptr"),
  ev_row("request_params", "patch", "provider, model, params", "list(params)", origin = "gptr"),
  ev_row("message_start", "notify", "role"),
  ev_row("message_update", "notify", "role, index, kind, delta"),
  ev_row("message_end", "notify", "role, message"),
  ev_row("tool_call", "decision",
         "tool_name, tool_call_id, input, nested, parent_tool_call_id, risk",
         "NULL, list(decision = \"block\", reason) or list(decision = \"modify\", input)",
         fail_closed = TRUE),
  ev_row("permission_request", "first_decision", "the permission request record (contract 7.11)",
         "list(decision = \"allow\" | \"deny\", reason)", origin = "gptr", fail_closed = TRUE),
  ev_row("tool_execution_start", "notify", "tool_call_id, tool_name, input"),
  ev_row("tool_execution_update", "notify", "tool_call_id, tool_name, text"),
  ev_row("tool_execution_end", "notify", "tool_call_id, tool_name, is_error, elapsed, details"),
  ev_row("tool_result", "patch", "tool_name, tool_call_id, input, content, details, is_error",
         "list(content, details, is_error)"),
  ev_row("queue_update", "notify", "steer, follow_up"),
  ev_row("retry_start", "notify", "attempt, delay, class", origin = "gptr"),
  ev_row("retry_end", "notify", "attempt, ok", origin = "gptr"),
  ev_row("session_before_compact", "first_decision", "reason, tokens",
         "list(cancel = TRUE) or list(result)"),
  ev_row("session_compact", "notify", "strategy, tokens_before, summary_tokens"),
  ev_row("session_before_tree", "first_decision", "from, to, plan", "list(cancel = TRUE, reason)"),
  ev_row("session_tree", "notify", "from, to, report"),
  ev_row("document_write", "block_patch", "path, format, kind, block_id, lines",
         "list(block = TRUE, reason) or list(lines)", origin = "gptr", fail_closed = TRUE),
  ev_row("decision", "notify", "model, question, type, n, summary, cached", origin = "gptr"),
  ev_row("route", "notify", "route, router, model, reason", origin = "gptr"),
  ev_row("model_select", "notify", "from, to, reason"),
  ev_row("subagent_start", "notify", "child, agent, backend, model", origin = "gptr"),
  ev_row("subagent_end", "notify", "child, agent, backend, model, status, usage",
         origin = "gptr"),
  ev_row("artifact_start", "notify", "id, url, version", origin = "gptr"),
  ev_row("artifact_stop", "notify", "id, url, version, reason", origin = "gptr"),
  ev_row("usage", "notify", "row", origin = "gptr"),
  ev_row("budget_near", "notify", "kind, budget, used", origin = "gptr"),
  ev_row("budget_exceeded", "notify", "kind, budget, used", origin = "gptr"),
  ev_row("cache_break", "notify", "provider, model, first_diff, entry, culprit", origin = "gptr"),
  ev_row("bridge_call", "notify",
         "bridge, id, cmd, level, status, seconds, bytes_out, bytes_err, spill, digest",
         origin = "gptr"),
  ev_row("checkpoint", "notify", "tool_call_id, objects, files, restorable", origin = "gptr"),
  ev_row("secret_registered", "notify", "name, source, count", origin = "gptr"),
  ev_row("mcp_servers_change", "notify", "added, removed"),
  ev_row("mcp_serve_start", "notify", "url", origin = "gptr"),
  ev_row("mcp_serve_stop", "notify", "url", origin = "gptr")
)

#' Hints for names that are not gptr events (Claude/Codex, pre-IC-03 and unported Pi names)
#' @noRd
ev_hints = c(
  PreToolUse = "did you mean 'tool_call'?", PostToolUse = "did you mean 'tool_result'?",
  UserPromptSubmit = "did you mean 'input'?", SessionStart = "did you mean 'session_start'?",
  SessionEnd = "did you mean 'session_shutdown'?", Stop = "did you mean 'agent_end'?",
  SubagentStart = "did you mean 'subagent_start'?", SubagentStop = "did you mean 'subagent_end'?",
  PreCompact = "did you mean 'session_before_compact'?",
  PostCompact = "did you mean 'session_compact'?",
  PermissionRequest = "did you mean 'permission_request'?",
  session_end = "did you mean 'session_shutdown'?",
  pre_compact = "did you mean 'session_before_compact'?",
  post_compact = "did you mean 'session_compact'?", compaction = "did you mean 'session_compact'?",
  before_agent_start = "not ported from Pi; use 'session_start'",
  agent_settled = "not ported from Pi; use 'agent_end'",
  agent_before_settle = "not ported from Pi; use 'agent_end'",
  context = "not ported from Pi; use a compactor, context_block or request_params record",
  context_with_system = "not ported from Pi; use a prompt_section or context_block record",
  before_provider_request = "not ported from Pi; use 'before_request' or 'request_params'",
  before_provider_headers = "not ported from Pi; use 'request_params'",
  after_provider_response = "not ported from Pi; use 'usage'",
  provider_stream_event = "not ported from Pi; use 'message_update'",
  session_before_switch = "not ported from Pi", session_compact_failed = "not ported from Pi",
  session_info_changed = "not ported from Pi", thinking_level_select = "not ported from Pi",
  ui_prompt_start = "not ported from Pi", ui_prompt_end = "not ported from Pi",
  user_bash = "not ported from Pi (gptr has no bash tool)"
)

#' The event catalogue as a data frame (contract 7.2)
#' @noRd
ev_catalogue = function() {
  ev_table[, c("event", "semantics", "fail_closed", "payload", "returns", "origin")]
}

#' Is `event` a plugin channel name ("<plugin>:<topic>")?
#' @noRd
ev_is_channel = function(event) {
  is.character(event) && length(event) == 1L && !is.na(event) &&
    grepl("^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+$", event, perl = TRUE)
}

#' Dispatch semantics of an event; channels notify; NULL for unknown names
#' @noRd
ev_semantics = function(event) {
  i = match(event, ev_table$event)
  if (!is.na(i)) return(ev_table$semantics[[i]])
  if (ev_is_channel(event)) return("notify")
  NULL
}

#' A hint for an unknown event name, or NULL
#' @noRd
ev_hint = function(event) {
  if (!is.character(event) || length(event) != 1L || is.na(event)) return(NULL)
  h = ev_hints[event]
  if (!is.na(h)) return(unname(h))
  i = match(tolower(event), tolower(ev_table$event))
  if (!is.na(i)) return(paste0("did you mean '", ev_table$event[[i]], "'?"))
  NULL
}

#' Validate an event name for hook registration (contract 7.2 hook_add)
#' @noRd
ev_check_name = function(event, arg = "event") {
  ok = is.character(event) && length(event) == 1L && !is.na(event) &&
    (event %in% ev_table$event || ev_is_channel(event))
  if (ok) return(invisible(event))
  label = if (is.character(event) && length(event) == 1L && !is.na(event)) event else "?"
  hint = ev_hint(event)
  gptr_abort(paste0("Unknown gptr event '", label, "'",
                    if (is.null(hint)) "" else paste0("; ", hint),
                    ". Events are listed by gptr_api()$features; plugin channels are named ",
                    "'<plugin>:<topic>'."),
             "invalid_argument", arg = arg,
             expected = "a catalogued event name or a <plugin>:<topic> channel")
}

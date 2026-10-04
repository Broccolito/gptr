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
    grepl("\\A[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+\\z", event, perl = TRUE)
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

# ---- dispatch (contract 7.2, 10.7) --------------------------------------------------------------

#' Hook-injected context is capped at 10,000 characters per dispatch (contract 10.7)
#' @noRd
ev_cap = 10000L

#' Does a block carry opaque binary or replay `data` (images, redacted thinking)?
#' @noRd
ev_opaque_data = function(x) {
  typ = x[["type"]]
  if (!is.character(typ) || length(typ) != 1L || is.na(typ)) return(FALSE)
  typ %in% c("image", "redacted_thinking") || (typ == "thinking" && isTRUE(x[["redacted"]]))
}

#' Redact every string of a payload with a profile, leaving opaque replay fields untouched
#' @noRd
ev_redact_payload = function(x, profile = "stream", preserve_replay = TRUE) {
  if (is.character(x)) return(redact_hook(x, profile))
  if (!is.list(x)) return(x)
  typ = x[["type"]]
  replay = character()
  if (preserve_replay && spec_field_ok(typ, "chr1", kind_field("chr1"))) {
    replay = switch(typ,
      text = c("signature", "text_signature", "textSignature"),
      thinking = c("signature", "thinking_signature", "encrypted_content"),
      tool_call = c("thought_signature", "thoughtSignature"),
      opaque = "json", character())
    if (ev_opaque_data(x)) replay = c(replay, "data")
  }
  nms = names(x)
  for (i in seq_along(x)) {
    nm = if (is.null(nms)) "" else nms[[i]]
    if (nm %in% replay) next
    v = x[[i]]
    generic = nm %in% c("input", "arguments", "raw_arguments", "details", "params", "attrs")
    if (is.character(v) || is.list(v)) {
      x[i] = list(ev_redact_payload(v, profile, preserve_replay && !generic))
    }
  }
  x
}

#' The event record a handler sees: type first, session and ts filled, stream-redacted
#' @noRd
ev_view = function(event, payload, sid) {
  x = payload[setdiff(names(payload) %||% character(), "type")]
  x = c(list(type = event), x)
  if (is.null(x[["session"]])) x["session"] = list(sid)
  if (is.null(x[["ts"]])) x$ts = as.numeric(Sys.time())
  ev_redact_payload(x, "stream")
}

#' The result of an event without handlers
#' @noRd
ev_default = function(sem, payload) {
  switch(sem,
    collect = list(),
    transform = list(action = "continue", text = payload[["text"]]),
    decision = list(decision = "allow", reason = NULL, input = payload[["input"]]),
    patch = payload,
    block_patch = list(block = FALSE, reason = NULL, lines = payload[["lines"]]),
    NULL
  )
}

#' Mirror active runs and executing tools from the events P06 dispatches (IC-53): agent_start
#' and agent_end bracket a run; tool_execution_start and tool_execution_end bracket a tool. The
#' one-shot grants of a run (ext_control_grant()) end with the top-level call they were granted
#' in (a tool_call_id without "/"; nested calls are "<outer>/<k>"), as P06's tool_execute_frame()
#' clears run$signal$control, so an unused approval never reaches a later call
#' @noRd
ev_track = function(reg, event, payload) {
  run = payload[["run"]]
  run = if (is.character(run) && length(run) == 1L && !is.na(run)) run else NULL
  drop_grants = function() {
    keep = vapply(reg$grants, function(g) !identical(g$run, run), NA)
    reg$grants = reg$grants[keep]
  }
  if (identical(event, "agent_start") && !is.null(run)) reg$runs = union(reg$runs, run)
  if (identical(event, "agent_end") && !is.null(run)) {
    reg$runs = setdiff(reg$runs, run)
    reg$executing = reg$executing[reg$executing != run]
    drop_grants()
  }
  id = payload[["tool_call_id"]]
  if (is.character(id) && length(id) == 1L && !is.na(id)) {
    key = paste0(run %||% "", "\r", id)
    if (identical(event, "tool_execution_start")) reg$executing[[key]] = run %||% ""
    if (identical(event, "tool_execution_end")) {
      reg$executing = reg$executing[names(reg$executing) != key]
      if (!is.null(run) && !grepl("/", id, fixed = TRUE)) drop_grants()
    }
  }
  invisible(NULL)
}

#' Is a record a lazy placeholder?
#' @noRd
ev_lazy = function(rec) identical(rec$state, "lazy")

#' Hook records for an event: session listeners (rank 0) first, then by rank; lazy ones activated
#' @noRd
ev_hooks = function(reg, event, sid) {
  pick = function() {
    recs = registry_recs(reg, get0(event, envir = reg$hooks, inherits = FALSE))
    recs[vapply(recs, function(r) registry_visible(r, sid) && !registry_rec_filtered(r, reg),
                NA)]
  }
  recs = pick()
  lazy = recs[vapply(recs, ev_lazy, NA)]
  if (length(lazy)) {
    for (r in lazy) ext_activate_record(r)
    recs = pick()
    recs = recs[!vapply(recs, ev_lazy, NA)]
  }
  registry_sort(recs)
}

#' Does a hook's matcher accept the event (NULL, a tool-name glob, or a predicate)?
#' @noRd
ev_matches = function(matcher, ev) {
  if (is.null(matcher)) return(TRUE)
  if (is.function(matcher)) return(isTRUE(matcher(ev)))
  tool = ev[["tool_name"]]
  is.character(tool) && length(tool) == 1L && grepl(utils::glob2rx(matcher), tool, perl = TRUE)
}

#' Sentinel returned for a handler whose matcher did not match
#' @noRd
ev_skip = structure(list(), class = "gptr_ev_skip")

#' Call one hook handler with the ctx attributed to its source
#' @noRd
ev_call = function(rec, ev, ctx) {
  if (!ev_matches(rec$spec[["matcher"]], ev)) return(ev_skip)
  ctx_with_source(ctx, rec$source, function() rec$spec[["handler"]](ev, ctx))
}

#' Call a handler; an error becomes a diagnostic and the value `on_error` (or its result)
#' @noRd
ev_try = function(rec, ev, ctx, event, on_error = NULL) {
  tryCatch({
    result = ev_call(rec, ev, ctx)
    if (is.list(result) && length(result)) {
      check_list(result, "hook result", named = TRUE)
      if (is.data.frame(result)) {
        gptr_abort("Hook results must be named lists, not data frames.", "invalid_argument",
                   arg = "hook result", expected = "a named list")
      }
      if (event %in% c("tool_call", "permission_request", "document_write")) {
        check_string(result[["reason"]], "reason", null = TRUE, empty = TRUE)
      }
      if (identical(event, "document_write")) {
        if ("block" %in% names(result)) check_flag(result[["block"]], "block")
        if ("lines" %in% names(result)) check_strings(result[["lines"]], "lines")
      }
    }
    result
  }, error = function(e) {
    registry_diagnostic(rec$source, event, class(e)[[1]], conditionMessage(e))
    if (is.function(on_error)) on_error(conditionMessage(e)) else on_error
  })
}

#' Is a handler return usable (a list, not the skip sentinel)?
#' @noRd
ev_usable = function(r) is.list(r) && !inherits(r, "gptr_ev_skip")

#' The reason a handler gave, as one string
#' @noRd
ev_reason = function(r, source) {
  paste(as.character(r[["reason"]] %||% paste0("blocked by a hook from ", source)), collapse = " ")
}

#' Merge a collect result: named lists merge with earlier handlers winning, others concatenate
#' @noRd
ev_merge = function(acc, r) {
  for (k in names(r)) {
    if (!nzchar(k)) next
    v = r[[k]]
    named = is.list(v) && length(v) && !is.null(names(v)) && all(nzchar(names(v)))
    if (named) {
      old = acc[[k]] %||% list()
      add = setdiff(names(v), names(old))
      old[add] = v[add]
      acc[[k]] = old
    } else if (!is.null(v)) {
      acc[[k]] = c(acc[[k]], v)
    }
  }
  acc
}

#' Cap hook-injected context blocks at ev_cap characters in total
#' @noRd
ev_cap_blocks = function(blocks, event) {
  if (!length(blocks)) return(blocks)
  size = function(b) {
    nchar(paste(as.character(if (is.list(b)) b[["text"]] else b), collapse = ""), type = "chars")
  }
  keep = cumsum(vapply(blocks, size, 0)) <= ev_cap
  if (!all(keep)) {
    registry_diagnostic("dispatch", event, "context_cap",
                        paste0("hook-injected blocks cut at ", ev_cap, " characters"))
  }
  blocks[keep]
}

#' Merge a handler's `params` patch into the current params (request_params, IC-69). The payload
#' holds only the declared request_params that are set, so a handler may add a declared key that
#' is unset (`metadata`, `user`); which keys the adapter accepts is known only to the emitter,
#' P06's run_request_params(), which drops undeclared keys with its own diagnostic
#' @noRd
ev_params_patch = function(old, new, rec, event) {
  old = old %||% list()
  ok = spec_field_ok(new, "nlist", kind_field("nlist"))
  if (!ok) {
    registry_diagnostic(rec$source, event, "patch_ignored", "params must be a named list")
    return(old)
  }
  for (k in names(new)) old[k] = list(new[[k]])
  old
}

#' notify: call every handler, ignore the returns
#' @noRd
ev_run_notify = function(hooks, ev, ctx, event, payload) {
  for (h in hooks) ev_try(h, ev, ctx, event)
  NULL
}

#' collect: merge the returned lists (injected blocks are capped)
#' @noRd
ev_run_collect = function(hooks, ev, ctx, event, payload) {
  acc = list()
  for (h in hooks) {
    r = ev_try(h, ev, ctx, event)
    if (ev_usable(r)) acc = ev_merge(acc, r)
  }
  if (!is.null(acc$blocks)) acc$blocks = ev_cap_blocks(acc$blocks, event)
  acc
}

#' transform chain: text flows through; "transform" replaces it, "handled" stops the chain
#' @noRd
ev_run_transform = function(hooks, ev, ctx, event, payload) {
  text = payload[["text"]]
  changed = FALSE
  finish = function(action) {
    if (changed && nchar(text, type = "chars") > ev_cap) {
      text = substr(text, 1L, ev_cap)
      registry_diagnostic("dispatch", event, "context_cap",
                          paste0("transformed text cut at ", ev_cap, " characters"))
    }
    list(action = action, text = text)
  }
  for (h in hooks) {
    r = ev_try(h, ev, ctx, event)
    if (!ev_usable(r)) next
    if (identical(r[["action"]], "handled")) {
      if (is.character(r[["text"]])) {
        text = paste(r[["text"]], collapse = "\n")
        changed = TRUE
      }
      return(finish("handled"))
    }
    if (identical(r[["action"]], "transform") && is.character(r[["text"]])) {
      text = paste(r[["text"]], collapse = "\n")
      changed = TRUE
      ev$text = redact_hook(text, "stream")
    }
  }
  finish(if (changed) "transform" else "continue")
}

#' decision (tool_call): the first block wins; modify patches the input; an error or an unknown
#' decision blocks (fail closed: list(decision = "deny") must not mean allow)
#' @noRd
ev_run_decision = function(hooks, ev, ctx, event, payload) {
  input = payload[["input"]]
  modified = FALSE
  for (h in hooks) {
    fail = function(msg) {
      list(decision = "block",
           reason = paste0("a ", event, " hook from ", h$source, " failed: ", msg))
    }
    r = ev_try(h, ev, ctx, event, on_error = fail)
    if (!ev_usable(r) || !length(r)) next
    d = r[["decision"]]
    if (identical(d, "block")) {
      return(list(decision = "block", reason = ev_reason(r, h$source), input = input))
    }
    if (identical(d, "modify") && spec_field_ok(r[["input"]], "nlist", kind_field("nlist"))) {
      input = r[["input"]]
      modified = TRUE
      ev$input = ev_redact_payload(input, "stream", preserve_replay = FALSE)
    } else if (!identical(d, "allow")) {
      why = paste0("a ", event, " hook from ", h$source, " returned an unknown decision; return ",
                   "NULL, list(decision = \"block\", reason) or list(decision = \"modify\", input)")
      registry_diagnostic(h$source, event, "malformed_decision", why)
      return(list(decision = "block", reason = why, input = input))
    }
  }
  list(decision = if (modified) "modify" else "allow", reason = NULL, input = input)
}

#' first decision: the first non-empty list returned wins; a failing permission_request handler
#' denies. Returns are lists (contract 10.4); a non-list return (the value of a logging
#' assignment such as `log$n = log$n + 1`) has no opinion, so it neither hides the handlers after
#' it nor reaches emitters that read `res$cancel`
#' @noRd
ev_run_first = function(hooks, ev, ctx, event, payload) {
  for (h in hooks) {
    deny = function(msg) {
      if (!identical(event, "permission_request")) return(NULL)
      list(decision = "deny",
           reason = paste0("a permission_request hook from ", h$source, " failed: ", msg))
    }
    r = ev_try(h, ev, ctx, event, on_error = deny)
    if (!ev_usable(r) || !length(r)) next
    if (identical(event, "permission_request") &&
        !spec_field_ok(r[["decision"]], "enum", kind_field("enum", values = c("allow", "deny")))) {
      why = "a permission_request hook returned a malformed decision"
      registry_diagnostic(h$source, event, "malformed_decision", why)
      return(list(decision = "deny", reason = why))
    }
    return(r)
  }
  NULL
}

#' Validate one canonical tool-result patch field without changing the original result
#' @noRd
ev_tool_patch_ok = function(field, value) {
  if (identical(field, "is_error")) return(spec_field_ok(value, "lgl1", kind_field("lgl1")))
  if (identical(field, "details")) {
    return(is.null(value) || spec_field_ok(value, "nlist", kind_field("nlist")))
  }
  if (!is.list(value) || is.data.frame(value)) return(FALSE)
  isTRUE(tryCatch({
    for (block in value) {
      check_list(block, "content block", named = TRUE)
      type = check_choice(block[["type"]], c("text", "image"), "type")
      if (identical(type, "text")) {
        check_string(block[["text"]], "text", empty = TRUE)
        check_string(block[["signature"]], "signature", empty = TRUE, null = TRUE)
      } else {
        check_string(block[["data"]], "data", empty = TRUE)
        spec_result_images(list(block))
      }
    }
    TRUE
  }, error = function(e) FALSE))
}

#' patch chain: each handler sees the payload patched by the previous ones
#' @noRd
ev_run_patch = function(hooks, ev, ctx, event, payload) {
  cur = payload
  allowed = switch(event,
    tool_result = c("content", "details", "is_error"),
    request_params = "params",
    NULL
  )
  sid = ev[["session"]]
  for (h in hooks) {
    r = ev_try(h, ev, ctx, event)
    if (!ev_usable(r) || !length(r)) next
    fields = names(r) %||% character()
    if (!is.null(allowed)) {
      extra = setdiff(fields, allowed)
      if (length(extra)) {
        registry_diagnostic(h$source, event, "patch_ignored",
                            paste0("ignored fields: ", paste(extra, collapse = ", ")))
      }
      fields = intersect(fields, allowed)
    }
    if (identical(event, "request_params") && "params" %in% fields) {
      r$params = ev_params_patch(cur[["params"]], r[["params"]], h, event)
    }
    for (f in fields) {
      if (identical(event, "tool_result") && !ev_tool_patch_ok(f, r[[f]])) {
        registry_diagnostic(h$source, event, "patch_ignored", paste0("invalid ", f, " patch"))
        next
      }
      cur[f] = list(r[[f]])
    }
    ev = ev_view(event, cur, sid)
  }
  cur
}

#' block + patch (document_write): the first block wins; lines patch; an error blocks
#' @noRd
ev_run_block_patch = function(hooks, ev, ctx, event, payload) {
  lines = payload[["lines"]]
  for (h in hooks) {
    fail = function(msg) {
      list(block = TRUE, reason = paste0("a ", event, " hook from ", h$source, " failed: ", msg))
    }
    r = ev_try(h, ev, ctx, event, on_error = fail)
    if (!ev_usable(r)) next
    if (isTRUE(r[["block"]])) {
      return(list(block = TRUE, reason = ev_reason(r, h$source), lines = lines))
    }
    if (!is.null(r[["lines"]])) {
      lines = r[["lines"]]
      ev$lines = ev_redact_payload(lines, "stream")
    }
  }
  list(block = FALSE, reason = NULL, lines = lines)
}

#' Dispatch an event to session listeners, then registry hooks by rank (contract 7.2, 10.7)
#'
#' Returns NULL (notify), the merged list (collect), list(action, text) (transform),
#' list(decision, reason, input) (tool_call), the first answer or NULL (first decision), the
#' patched payload (patch) or list(block, reason, lines) (document_write). A session_shutdown
#' removes the session's records after its handlers ran (IC-69).
#' @noRd
ev_dispatch = function(event, payload, session = NULL, ctx = NULL) {
  check_string(event, "event")
  sem = ev_semantics(event)
  if (is.null(sem)) ev_check_name(event)
  payload = payload %||% list()
  reg = registry_env()
  sid = ext_session_id(session)
  ev_track(reg, event, payload)
  if (identical(event, "session_shutdown") && !is.null(sid)) {
    on.exit(registry_session_drop(sid), add = TRUE)
  }
  hooks = ev_hooks(reg, event, sid)
  if (!length(hooks)) return(ev_default(sem, payload))
  ctx = ctx %||% ctx_default(session)
  run = switch(sem,
    collect = ev_run_collect,
    transform = ev_run_transform,
    decision = ev_run_decision,
    first_decision = ev_run_first,
    patch = ev_run_patch,
    block_patch = ev_run_block_patch,
    ev_run_notify
  )
  run(hooks, ev_view(event, payload, sid), ctx, event, payload)
}

#' Register a hook record (contract 7.2); returns its id
#' @noRd
hook_add = function(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL) {
  ev_check_name(event)
  registry_add(gptr_hook(event, handler, matcher), source = source, rank = rank, session = session)
}

#' Remove a hook record (contract 7.2)
#' @noRd
hook_remove = function(id) registry_remove(id)

# ---- policies (contract 10.2 row 12) ------------------------------------------------------------

#' A well-formed policy decision: allow, deny, ask, ask_human (IC-53 item 6, combined as deny >
#' ask_human > ask > modify > allow by P06's perm_check(), 04 section 7.6), or modify with an
#' input list
#' @noRd
ext_policy_ok = function(r) {
  if (!spec_field_ok(r, "nlist", kind_field("nlist"))) return(FALSE)
  if (!is.null(r[["reason"]]) && !spec_field_ok(r[["reason"]], "chr1", kind_field("chr1"))) {
    return(FALSE)
  }
  d = r[["decision"]]
  known = c("allow", "deny", "ask", "ask_human", "modify")
  if (!is.character(d) || length(d) != 1L || !(d %in% known)) {
    return(FALSE)
  }
  !identical(d, "modify") || spec_field_ok(r[["input"]], "nlist", kind_field("nlist"))
}

#' Evaluate one policy on a call, failing closed: NULL (no opinion) or list(decision, reason,
#' input); an error or a malformed answer denies (contract 10.2 row 12; P06's perm_policies()
#' applies the same rule while combining policies)
#' @noRd
ext_policy_decide = function(spec, call, ctx = NULL) {
  deny = function(why) {
    list(decision = "deny", reason = paste0("policy '", spec[["name"]], "' ", why),
         input = call[["input"]])
  }
  r = tryCatch(spec[["check"]](call, ctx), error = function(e) e)
  if (inherits(r, "error")) {
    registry_diagnostic(paste0("policy:", spec[["name"]]), "policy", class(r)[[1]],
                        conditionMessage(r))
    return(deny(paste0("failed: ", conditionMessage(r))))
  }
  if (is.null(r)) return(NULL)
  if (!ext_policy_ok(r)) return(deny("returned a malformed decision"))
  input = if (identical(r[["decision"]], "modify")) r[["input"]] else call[["input"]]
  reason = paste(as.character(r[["reason"]] %||% ""), collapse = " ")
  list(decision = r[["decision"]], reason = reason, input = input)
}

# The cli-claude adapter (P20): the user's own claude CLI in stream-json mode, one long-lived
# child per session (per run while it carries budget flags), gptr's tools through the
# in-process `sdk` MCP server over the control protocol (architecture 8.3; contract 8.5,
# IC-65). L1: besides L0 helpers, the shared helpers of cli-common.R and P05's usage_new() it
# calls only the injected opts$send, opts$gate and opts$mcp_dispatch and P12's
# anthropic_normaliser() (IC-33).
# Adapted from the verified driver of report 07 section 5.7 (cc_proto.R: argv, control
# protocol, notification acks) and its live capture 3.14 (the fixture claude-call2.ndjson).

# ---- build (Task 5) ----------------------------------------------------------------------------

#' The claude argv of architecture 8.3 in its exact order, then the budget flags (IC-65,
#' IC-66), the documented --bare opt-out when the probe found one, and --resume (never --bare)
#'
#' A budget value that is not a positive finite number adds no flag (pcli_claude_flags());
#' `turns` is rounded down (at least 1), `cost` rounded to 4 decimals (at least 0.01), both
#' written as plain decimal numbers whatever `OutDec` and `digits` say.
#' @noRd
pcli_claude_args = function(model_id, mcp_config, system_file, budget = NULL, optout = NULL,
                           resume = NULL) {
  args = c("-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
           "--include-partial-messages", "--tools", "", "--strict-mcp-config",
           "--setting-sources", "", "--disable-slash-commands", "--mcp-config", mcp_config,
           "--permission-prompt-tool", "stdio", "--permission-mode", "default",
           "--allowedTools", "mcp__gptr__*", "--system-prompt-file", system_file,
           "--model", model_id)
  flags = pcli_claude_flags(budget)
  if (!is.null(flags$turns)) {
    args = c(args, "--max-turns", pcli_claude_number(max(1, floor(flags$turns))))
  }
  if (!is.null(flags$cost)) {
    args = c(args, "--max-budget-usd", pcli_claude_number(max(0.01, round(flags$cost, 4))))
  }
  if (!is.null(optout)) args = c(args, optout)
  if (!is.null(resume)) args = c(args, "--resume", resume)
  args
}

#' The budget flags a child is started with: `turns` and `cost` when each is a positive finite
#' number, else NULL (no flag, no limit, as without a budget; P06's budget_check() stays
#' authoritative between requests)
#' @param budget list(turns, cost) or NULL.
#' @return list(turns = num(1) | NULL, cost = num(1) | NULL)
#' @noRd
pcli_claude_flags = function(budget) {
  fin = function(x) {
    x = pcli_scalar_num(x)
    if (!is.null(x) && is.finite(x)) x else NULL
  }
  list(turns = fin(budget[["turns"]]), cost = fin(budget[["cost"]]))
}

#' A budget number as an argv word: plain decimal, `.` as the decimal mark, up to 15
#' significant digits, independent of options(OutDec, digits, scipen)
#' @noRd
pcli_claude_number = function(x) {
  format(x, scientific = FALSE, trim = TRUE, digits = 15L, decimal.mark = ".", big.mark = "")
}

#' The --mcp-config file content: gptr's in-process sdk server (contract 8.5, verbatim)
#' @noRd
pcli_claude_mcp_json = function() '{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}'

#' Write the MCP config and the system-prompt files of a session once, under tempdir(); a
#' restarted child (--resume) gets the same files (07 2.16: the same system prompt on resume)
#' @return list(mcp, system): the two paths, also kept in `state` (`claude_mcp_file`,
#'   `claude_system_file`).
#' @noRd
pcli_claude_files = function(state, context, session) {
  dir = file.path(tempdir(), "gptr", "cli")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  stem = paste0(session %||% id_new("s", 10L), "-claude")
  if (is.null(state$claude_mcp_file) || !file.exists(state$claude_mcp_file)) {
    state$claude_mcp_file = path_norm(file.path(dir, paste0(stem, "-mcp.json")))
    write_utf8(state$claude_mcp_file, pcli_claude_mcp_json())
  }
  if (is.null(state$claude_system_file) || !file.exists(state$claude_system_file)) {
    state$claude_system_file = path_norm(file.path(dir, paste0(stem, "-system.md")))
    write_utf8(state$claude_system_file, pcli_system_text(context))
  }
  list(mcp = state$claude_mcp_file, system = state$claude_system_file)
}

#' Anthropic content blocks of the new input: text, rendered context blocks, base64 images
#' (07 2.14: the stream-json user message takes Anthropic content blocks)
#'
#' A block whose text is empty or only white space is dropped, as P12's anthropic_user() does:
#' the Messages API refuses white-space-only text blocks. Input without any block becomes the
#' single text block "(no new input)".
#' @noRd
pcli_claude_content = function(input) {
  out = list()
  for (m in input) {
    for (b in m[["content"]] %||% list()) {
      type = b[["type"]] %||% ""
      blk = if (identical(type, "image") && is.character(b[["data"]])) {
        list(type = "image", source = list(type = "base64",
                                           media_type = b[["mime"]] %||% "image/png",
                                           data = b[["data"]]))
      } else {
        txt = pcli_block_text(b)
        if (nzchar(trimws(txt))) list(type = "text", text = txt) else NULL
      }
      if (!is.null(blk)) out[[length(out) + 1L]] = blk
    }
  }
  if (!length(out)) out = list(list(type = "text", text = "(no new input)"))
  out
}

#' The stdin line of one user turn (contract 8.5; 07 3.12)
#' @noRd
pcli_claude_user_line = function(content) {
  list(type = "user", message = list(role = "user", content = content),
       parent_tool_use_id = NULL, session_id = "")
}

#' Does a child carry budget flags (`--max-turns`, `--max-budget-usd`)? Only a positive finite
#' value makes a flag (pcli_claude_flags()), so the argv, the reuse rule of build() and Task 9's
#' retirement of a budgeted child agree
#' @param flags list(turns, cost) or NULL.
#' @noRd
pcli_claude_budgeted = function(flags) {
  fl = pcli_claude_flags(flags)
  !is.null(fl$turns) || !is.null(fl$cost)
}

#' build(): reuse the session's live claude child, or start one (find, probe, notice, files,
#' argv, the `initialize` control request), then send the turn (contract 8.1 process_jsonl,
#' 8.5)
#'
#' A child is reused for the same model while it lives, but a child with budget flags only
#' within the run that started it: the flags are fixed at launch and the CLI counts cost for its
#' whole process, while gptr's budgets restart with every top-level call (IC-66). A replaced
#' child is retired here through pcli_stop_child() (stdin closed, then P05's
#' stream_process_kill()), and the new one resumes the CLI session. A reused child or a resumed
#' session gets the turns it has not seen (another model may have answered them,
#' pcli_unseen()); a fresh child gets the whole earlier conversation.
#'
#' The turn's lines are written by P05's transport with write_all(); a fresh child's first user
#' line carries the earlier conversation and the input's images, so it is not bounded. On
#' Windows that write blocks until the CLI has read it (D-019 item 5).
#' @noRd
pcli_claude_build = function(model, context, opts) {
  state = pcli_state(opts)
  state$pcli_request_id = context[["request_id"]]
  state$interrupt_id = NULL
  state$interrupt_acked = FALSE
  pcli_track(opts[["session"]], state)
  model_id = pcli_model_id(model)
  par = pcli_params(context)
  parts = pcli_split(context[["messages"]] %||% list())
  flags = pcli_claude_flags(par)
  same_run = identical(state$claude_run, opts[["run"]])
  unbudgeted = !pcli_claude_budgeted(flags) && !pcli_claude_budgeted(state$claude_flags)
  reuse = identical(state$cli_api, "cli-claude") && identical(state$claude_model, model_id) &&
    pcli_alive(pcli_child(state)) && (same_run || unbudgeted)
  start = NULL
  send = list()
  resume = NULL
  if (!reuse) {
    if (pcli_alive(pcli_child(state))) pcli_stop_child(state, wait_ack = FALSE)
    path = pcli_find("claude")
    probe = pcli_probe(path)
    pcli_notice("claude")
    files = pcli_claude_files(state, context, opts[["session"]])
    resume = state$claude_session
    args = pcli_claude_args(model_id, files$mcp, files$system, budget = flags,
                           optout = probe$bare_optout, resume = resume)
    start = list(command = path[[1L]], args = c(as.character(path[-1L]), args),
                 env_profile = "cli-claude", env = character(), wd = path_norm(getwd()))
    state$cli_api = "cli-claude"
    state$claude_model = model_id
    state$claude_run = opts[["run"]]
    state$claude_flags = flags
    # the new process's own cumulative total_cost_usd starts here (Task 6 records increases)
    state$claude_cost_seen = 0
    state$n_req = 0L
    send = list(pcli_control_request(state, list(subtype = "initialize", hooks = NULL)))
  }
  seen = reuse || !is.null(resume)
  history = pcli_history_text(if (seen) pcli_unseen(parts$prior, model$provider) else parts$prior)
  content = pcli_claude_content(parts$input)
  if (nzchar(history)) content = c(list(list(type = "text", text = history)), content)
  list(start = start, send = c(send, list(pcli_claude_user_line(content))), close_stdin = FALSE)
}

# ---- the cli-claude normaliser (Task 6) --------------------------------------------------------

#' A success control_response (07 3.10)
#' @noRd
pcli_control_ok = function(id, response) {
  list(type = "control_response",
       response = list(subtype = "success", request_id = id, response = response))
}

#' An error control_response (07 3.10)
#' @noRd
pcli_control_err = function(id, error) {
  list(type = "control_response",
       response = list(subtype = "error", request_id = id, error = error))
}

#' A JSON-RPC error answering `msg`
#' @noRd
pcli_jsonrpc_error = function(msg, code, text) {
  list(jsonrpc = "2.0", id = msg[["id"]], error = list(code = code, message = text))
}

#' Note the CLI's answer to gptr's interrupt request (pcli_stop_child() waits for it)
#' @noRd
pcli_claude_ack = function(obj, state) {
  id = obj[["response"]][["request_id"]]
  if (!is.null(id) && identical(id, state$interrupt_id)) state$interrupt_acked = TRUE
  invisible(NULL)
}

#' mcp_message: one JSON-RPC message for gptr's tools, answered through opts$mcp_dispatch (P18's
#' mcp_dispatch_local, the single gate of the claude route, IC-65)
#'
#' `tools/call` runs from the reactor's tool FIFO of the run, so the R tools of other agents
#' never overlap with it (IC-57); the handshake and notifications are answered at once. A
#' notification (no id) gets the ack `{"jsonrpc":"2.0","result":{}}` (07 3.10). A queued
#' `tools/call` whose turn ended before the FIFO reached it (the wall clock stopped the child, or
#' P05 let go of the turn and the session started another, pcli_turn_current()) is refused,
#' never evaluated (D-104).
#'
#' Every answer is built before pcli_send() is called: an argument forced only inside the
#' transport's send() would turn an error into a silent no-answer, and the CLI would wait for it
#' until the wall clock fires (D-104).
#' @noRd
pcli_claude_mcp = function(req, id, s) {
  opts = s$opts
  msg = req[["message"]] %||% list()
  answer = function(resp) {
    out = pcli_control_ok(id, list(mcp_response = resp))
    pcli_send(opts, out)
  }
  if (!identical(req[["server_name"]], "gptr")) {
    return(answer(pcli_jsonrpc_error(msg, -32601L, "Server not found")))
  }
  dispatch = opts[["mcp_dispatch"]]
  if (!is.function(dispatch)) {
    return(answer(pcli_jsonrpc_error(msg, -32603L, "gptr's MCP dispatcher is not available")))
  }
  run_it = function() {
    if (pcli_aborted(s)) {
      return(answer(pcli_jsonrpc_error(msg, -32603L, "The gptr run was aborted.")))
    }
    if (s$done || !pcli_turn_current(s)) {
      return(answer(pcli_jsonrpc_error(msg, -32603L, "The gptr turn is over.")))
    }
    resp = tryCatch(dispatch(msg), error = function(e) {
      pcli_jsonrpc_error(msg, -32603L, redact(conditionMessage(e), "context"))
    })
    if (is.null(resp)) resp = list(jsonrpc = "2.0", result = json_obj())
    answer(resp)
  }
  run = opts[["run"]]
  if (identical(msg[["method"]], "tools/call") && is.character(run) && length(run) == 1L) {
    reactor_enqueue_tool(run, run_it)
  } else {
    run_it()
  }
  invisible(NULL)
}

#' can_use_tool: gptr's own tools are pre-allowed by --allowedTools mcp__gptr__* and gated once,
#' in mcp_message; any other tool goes through the injected opts$gate (03 8.3)
#' @noRd
pcli_claude_permission = function(req, opts) {
  name = req[["tool_name"]] %||% ""
  input = req[["input"]]
  if (!length(input)) input = json_obj()
  if (startsWith(name, "mcp__gptr__")) return(list(behavior = "allow", updatedInput = input))
  gate = opts[["gate"]]
  if (!is.function(gate)) {
    return(list(behavior = "deny", message = "gptr has no permission gate for this request."))
  }
  call = list(id = req[["tool_use_id"]] %||% "cli", name = name, input = input, raw = NULL,
              tool = NULL, nested = FALSE, parent_id = NULL, outer_level = NULL, risk = NULL)
  d = tryCatch(gate(call), error = function(e) {
    list(decision = "deny", reason = conditionMessage(e))
  })
  if ((d[["decision"]] %||% "") %in% c("allow", "modify")) {
    upd = d[["input"]]
    if (!length(upd)) upd = input
    return(list(behavior = "allow", updatedInput = upd))
  }
  list(behavior = "deny", message = d[["reason"]] %||% "Denied by gptr's permission gate.")
}

#' Answer a control_request from the CLI (contract 8.5)
#'
#' The answer, and so the gate's decision, is computed here, before pcli_send(): an error in it
#' reaches parse()'s push() and ends the turn (D-104), instead of being swallowed by the write.
#' @noRd
pcli_claude_control = function(obj, s) {
  req = obj[["request"]] %||% list()
  id = obj[["request_id"]]
  sub = req[["subtype"]] %||% ""
  if (identical(sub, "mcp_message")) return(pcli_claude_mcp(req, id, s))
  out = if (identical(sub, "can_use_tool")) {
    pcli_control_ok(id, pcli_claude_permission(req, s$opts))
  } else {
    pcli_control_err(id, paste("Unsupported control request subtype:", sub))
  }
  pcli_send(s$opts, out)
}

#' Refuse a control request that arrives after the turn ended or after an abort
#' @noRd
pcli_claude_refuse = function(obj, s) {
  req = obj[["request"]] %||% list()
  id = obj[["request_id"]]
  if (identical(req[["subtype"]], "mcp_message")) {
    msg = req[["message"]] %||% list()
    resp = pcli_jsonrpc_error(msg, -32603L, "The gptr turn is over.")
    return(pcli_send(s$opts, pcli_control_ok(id, list(mcp_response = resp))))
  }
  if (identical(req[["subtype"]], "can_use_tool")) {
    answer = list(behavior = "deny", message = "The gptr turn is over.")
    return(pcli_send(s$opts, pcli_control_ok(id, answer)))
  }
  pcli_send(s$opts, pcli_control_err(id, "The gptr turn is over."))
}

#' Forward one event of the inner (per API message) Anthropic normaliser into the turn's stream
#'
#' One outer stream per CLI turn: inner `start` and terminal events are absorbed, text and
#' thinking blocks are re-indexed, tool calls are not forwarded (they ran through mcp_message).
#' @noRd
pcli_claude_forward = function(ev, s) {
  type = ev[["type"]] %||% ""
  if (identical(type, "start")) return(pcli_start(s, ev[["response_id"]]))
  kinds = c("text_start", "text_delta", "text_end", "thinking_start", "thinking_delta",
            "thinking_end")
  if (!(type %in% kinds) || s$done) return(invisible(NULL))
  key = as.character(ev[["index"]])
  if (type %in% c("text_start", "thinking_start")) {
    pcli_start(s)
    s$n = s$n + 1L
    s$map[key] = s$n
    o = new.env(parent = emptyenv())
    o$kind = sub("_start$", "", type)
    o$parts = vector("list", 16L)
    o$n = 0L
    s$open[[s$n]] = o
  }
  i = unname(s$map[key])
  if (!length(i) || is.na(i)) return(invisible(NULL))
  ev[["index"]] = i
  if (type %in% c("text_delta", "thinking_delta")) {
    o = s$open[[i]]
    if (o$n == length(o$parts)) length(o$parts) = 2L * length(o$parts)
    o$n = o$n + 1L
    o$parts[[o$n]] = ev[["delta"]]
  }
  if (type %in% c("text_end", "thinking_end")) s$blocks[[i]] = ev[["block"]]
  emit = s$opts[["emit"]]
  if (is.function(emit)) emit(ev)
  invisible(NULL)
}

#' Feed one `stream_event` (a raw Anthropic SSE data object) to the inner normaliser; a new one
#' starts at each `message_start` (07 5.8: the CLI stream reuses the native accumulator)
#' @noRd
pcli_claude_stream = function(event, s) {
  if (!is.list(event)) return(invisible(NULL))
  if (identical(event[["type"]], "message_start") || is.null(s$inner)) {
    s$map = integer()
    inner_opts = list(emit = function(ev) pcli_claude_forward(ev, s),
                      retry = function(info) invisible(NULL), signal = s$opts[["signal"]])
    s$inner = anthropic_normaliser(s$model, inner_opts)
  }
  s$inner$push_parsed(event)
  invisible(NULL)
}

#' system lines: `init` records the CLI session id and model; an `apiKeySource` other than
#' "none" stops the turn with gptr_error_billing and the child (07 line 503; IC-65)
#' @noRd
pcli_claude_system = function(obj, s) {
  if (!identical(obj[["subtype"]], "init")) return(invisible(NULL))
  sid = obj[["session_id"]]
  if (is.character(sid) && length(sid) == 1L && nzchar(sid)) s$state$claude_session = sid
  model = pcli_claude_chr(obj[["model"]])
  if (!is.null(model)) s$response_model = model
  src = obj[["apiKeySource"]]
  if (is.null(src) || identical(src, "none")) return(invisible(NULL))
  why = paste0("The claude CLI reported apiKeySource ", src, ": this turn would be billed to ",
               "an API key instead of your Claude plan, so gptr stopped it. Remove the key from ",
               "the claude CLI's own settings, or use the anthropic provider for API billing.")
  pcli_fail(s, "billing", why)
  pcli_stop_child(s$state, wait_ack = FALSE)
  invisible(NULL)
}

#' The plan-cost estimate of one turn from a `result` line (contract 8.5). `total_cost_usd`
#' covers the whole CLI process (07 3.14: it equals `modelUsage.costUSD`, which also counts the
#' CLI's auxiliary calls), so the turn costs its increase since the child's previous result;
#' a smaller value (a new process) counts whole. NULL when the line carries no cost or a value
#' that is not one finite nonnegative number (unknown, IC-74; the child's baseline is kept).
#' @noRd
pcli_claude_cost = function(obj, state = NULL) {
  total = obj[["total_cost_usd"]]
  ok = is.numeric(total) && length(total) == 1L && is.finite(total) && total >= 0
  if (!ok) return(NULL)
  total = as.numeric(total)
  if (!is.environment(state)) return(total)
  seen = state$claude_cost_seen %||% 0
  state$claude_cost_seen = total
  if (total >= seen) total - seen else total
}

#' One string reported by the CLI, or NULL when the value is anything else
#' @noRd
pcli_claude_chr = function(x) if (is.character(x) && length(x) == 1L && !is.na(x)) x else NULL

#' A token count of a `result` line: the number when it is one finite nonnegative number, else
#' NA (absent or malformed counts are unknown, IC-74, as in P12's normaliser core)
#' @noRd
pcli_claude_count = function(x) {
  if (is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0) as.numeric(x) else NA_real_
}

#' The cost record of a turn's estimate (contract 4.3): the CLI reports only the total, so the
#' components are unknown (NA) rather than the constructor's legacy zeros; NULL (an unknown
#' cost, usage_new()'s cost_unknown()) when the CLI reported none (IC-74; D-015 point 3)
#' @noRd
pcli_claude_cost_record = function(total) {
  if (is.null(total)) return(NULL)
  list(input = NA_real_, output = NA_real_, cache_read = NA_real_, cache_write = NA_real_,
       total = total)
}

#' Usage of a `result` line: the CLI's token totals for the turn and its plan-cost estimate
#' (contract 8.5); 5-minute and 1-hour cache writes split as in 07 5.2
#'
#' A bare `cache_creation_input_tokens` without the split counts as 5-minute writes (07 3.5);
#' without either the cache writes are unknown. Every count the line does not report is NA and
#' so is the cost (IC-74: missing usage remains unknown; D-104).
#' @noRd
pcli_claude_usage = function(obj, state = NULL) {
  u = obj[["usage"]]
  if (!is.list(u)) u = list()
  cc = u[["cache_creation"]]
  if (is.list(cc)) {
    w5 = cc[["ephemeral_5m_input_tokens"]]
    w1 = cc[["ephemeral_1h_input_tokens"]]
  } else {
    w5 = u[["cache_creation_input_tokens"]]
    w1 = if (is.null(w5)) NULL else 0
  }
  details = u[["output_tokens_details"]]
  n = pcli_claude_count
  usage_new(input = n(u[["input_tokens"]]), output = n(u[["output_tokens"]]),
            cache_read = n(u[["cache_read_input_tokens"]]), cache_write_5m = n(w5),
            cache_write_1h = n(w1),
            reasoning = n(if (is.list(details)) details[["thinking_tokens"]]),
            cost = pcli_claude_cost_record(pcli_claude_cost(obj, state)))
}

#' gptr stop reason of the CLI's final stop reason (04 4.2; no tool_use: tools ran in the CLI)
#' @noRd
pcli_claude_stop = function(raw) {
  switch(pcli_claude_chr(raw) %||% "end_turn", max_tokens = "length", refusal = "refusal",
         pause_turn = "pause", "stop")
}

#' Condition class (04 2.2 suffix) of a failed `result` line
#' @noRd
pcli_claude_error_class = function(obj) {
  sub = obj[["subtype"]] %||% ""
  if (identical(sub, "error_max_turns")) return("max_turns")
  if (identical(sub, "error_max_budget_usd")) return("budget_cost")
  st = suppressWarnings(as.integer(obj[["api_error_status"]] %||% NA_integer_))
  if (!is.na(st) && st %in% c(401L, 403L)) return("auth")
  if (!is.na(st) && st == 429L) return("rate_limit")
  if (!is.na(st) && st >= 500L) return("overloaded")
  "provider"
}

#' result: the end of the turn (usage, plan cost estimate, route plan-cli) or its failure
#' @noRd
pcli_claude_result = function(obj, s) {
  text = obj[["result"]]
  has_text = any(vapply(pcli_blocks(s), function(b) identical(b[["type"]], "text"), NA))
  if (!has_text && is.character(text) && length(text) == 1L) pcli_text_block(s, text)
  usage = pcli_claude_usage(obj, s$state)
  aborted = startsWith(pcli_claude_chr(obj[["terminal_reason"]]) %||% "", "aborted")
  failed = isTRUE(obj[["is_error"]]) || !identical(obj[["subtype"]] %||% "success", "success")
  if (!aborted && !failed) {
    raw = pcli_claude_chr(obj[["stop_reason"]]) %||% "end_turn"
    return(pcli_done(s, usage, pcli_claude_stop(raw), raw))
  }
  detail = as.character(unlist(obj[["errors"]]))
  if (any(grepl("No conversation found", detail, fixed = TRUE))) s$state$claude_session = NULL
  cls = if (aborted) "aborted" else pcli_claude_error_class(obj)
  what = switch(cls,
                max_turns = "it reached --max-turns",
                budget_cost = "the turn is out of budget (--max-budget-usd)",
                aborted = "the turn was interrupted",
                paste0("it reported ", pcli_claude_chr(obj[["subtype"]]) %||% "an error"))
  if (length(detail)) what = paste0(what, ": ", paste(detail, collapse = "; "))
  pcli_fail(s, cls, paste0("The claude CLI ended the turn: ", what, "."),
           reason = if (aborted) "aborted" else "error",
           status = obj[["api_error_status"]] %||% NA_integer_, usage = usage)
}

#' The per-turn wall-clock limit passed: interrupt, report and stop the child. The words "out
#' of budget" keep P06 from retrying the turn as a transient failure. In an aborted run the
#' turn ends as aborted, with its one terminal event and final message (INFRA-02), and the
#' child is stopped without an interrupt (D-104): the terminal event finishes P05's stream, so
#' neither P05 (whose abort watch run_abort() cancelled) nor the next turn lets go of the child,
#' and with the turn closed builtin:cli's `agent_end` hook would leave it running.
#'
#' Only while the turn is its session's current one (pcli_turn_current()): P05 can end a turn
#' without its normaliser, and the session's next turn then has the shared state and its own
#' child, which this callback must not close or stop (D-104).
#' @noRd
pcli_claude_timeout = function(s) {
  if (s$done || !pcli_turn_current(s)) return(invisible(NULL))
  if (pcli_aborted(s)) {
    pcli_fail(s, "aborted", "The run was aborted.", reason = "aborted")
    pcli_stop_child(s$state, wait_ack = FALSE)
    return(invisible(NULL))
  }
  secs = pcli_turn_seconds()
  pcli_send(s$opts, pcli_control_request(s$state, list(subtype = "interrupt")))
  pcli_fail(s, "timeout", paste0("The claude CLI turn is out of budget: it ran past the ",
                                "per-turn limit of ", secs, " s (option gptr.cli_turn_timeout)."))
  pcli_stop_child(s$state, wait_ack = FALSE)
  invisible(NULL)
}

#' parse(): the normaliser of one claude turn (contract 8.1, 8.5)
#'
#' No function of the normaliser signals an R condition: an error while a line, the end of
#' input or a transport failure is processed becomes the turn's one terminal `error` event
#' (class `internal`), as P12's normaliser core does (contract 8.1; D-104). An error in push()
#' also stops the child, which may still be working on the turn: the terminal event finishes
#' P05's stream, so P05 no longer drops the child as it does for an error escaping push(), and
#' a later turn would otherwise reuse it and read this turn's late output. push() only reaches
#' the open turn's normaliser, so the session's current child is this turn's.
#' @noRd
pcli_claude_parse = function(model, opts) {
  s = pcli_turn_new(model, opts)
  s$inner = NULL
  s$map = integer()
  pcli_wire_log(s, "start")
  pcli_turn_timer(s, function() pcli_claude_timeout(s))

  push = function(ev) {
    obj = ev[["obj"]] %||% pcli_parse_line(ev[["data"]])
    if (!is.list(obj)) return(s$done)
    type = obj[["type"]] %||% ""
    if (identical(type, "control_response")) {
      pcli_claude_ack(obj, s$state)
      return(s$done)
    }
    if (identical(type, "control_request")) {
      if (s$done || pcli_aborted(s)) pcli_claude_refuse(obj, s) else pcli_claude_control(obj, s)
      return(s$done)
    }
    if (s$done) return(TRUE)
    if (pcli_aborted(s)) {
      if (identical(type, "result")) {
        pcli_fail(s, "aborted", "The run was aborted.", reason = "aborted",
                 usage = pcli_claude_usage(obj, s$state))
      }
      return(s$done)
    }
    if (identical(type, "system")) {
      pcli_claude_system(obj, s)
    } else if (identical(type, "rate_limit_event")) {
      pcli_plan_set(model$provider, obj[["rate_limit_info"]] %||% list())
    } else if (identical(type, "stream_event")) {
      if (is.null(obj[["parent_tool_use_id"]])) pcli_claude_stream(obj[["event"]], s)
    } else if (identical(type, "result")) {
      pcli_claude_result(obj, s)
    }
    s$done
  }

  finish = function() {
    if (!s$done) {
      if (pcli_aborted(s)) {
        pcli_fail(s, "aborted", "The run was aborted.", reason = "aborted")
      } else {
        pcli_fail(s, "provider", "The claude CLI exited before the end of the turn.")
      }
    }
    s$msg
  }

  fail = function(cnd) {
    if (!s$done) {
      aborted = pcli_aborted(s)
      cls = sub("^gptr_error_", "", class(cnd)[[1L]])
      pcli_fail(s, if (aborted) "aborted" else cls, conditionMessage(cnd),
               reason = if (aborted) "aborted" else "error",
               status = cnd[["status"]] %||% NA_integer_)
    }
    s$msg
  }

  message = function() s$msg %||% pcli_message(s)

  internal = function(e) {
    pcli_fail(s, "internal", paste0("The cli-claude adapter could not process the claude ",
                                   "CLI's output: ", conditionMessage(e)))
  }

  push_safe = function(ev) {
    tryCatch(push(ev), error = function(e) {
      internal(e)
      tryCatch(pcli_stop_child(s$state, wait_ack = FALSE), error = function(e2) NULL)
      TRUE
    })
  }

  list(push = push_safe, finish = function() tryCatch(finish(), error = internal),
       fail = function(cnd) tryCatch(fail(cnd), error = internal), message = message)
}
